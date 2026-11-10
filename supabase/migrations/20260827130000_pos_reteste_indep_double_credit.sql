-- =============================================================================
-- PÓS-RETESTE INDEPENDENTE — double-credit class + chat UPDATE + qty authority
-- Staging only · Stripe TEST · NÃO é Fase 4.
-- Idempotente.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) Ledger: estorno (clawback) + helpers de teto por captura
-- ---------------------------------------------------------------------------
do $$
begin
  alter table public.wallet_transactions
    drop constraint if exists wallet_transactions_type_check;
exception when undefined_object then
  null;
end $$;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check
  check (type in (
    'venda',
    'compra',
    'reembolso',
    'levantamento',
    'estorno',
    'gorjeta_enviada',
    'gorjeta_recebida'
  ));

-- Créditos líquidos da plataforma já desembolsados nesta order (venda+reembolso − estorno).
create or replace function public.batata_order_wallet_net_disbursed_eur(
  p_order_id uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sum numeric := 0;
begin
  if p_order_id is null then
    return 0::numeric(12, 2);
  end if;

  select coalesce(sum(
    case
      when type in ('venda', 'reembolso') then amount
      when type = 'estorno' then -amount
      else 0
    end
  ), 0)
  into v_sum
  from public.wallet_transactions
  where order_id = p_order_id;

  return round(greatest(v_sum, 0), 2)::numeric(12, 2);
end;
$$;

-- Débito opcional (reservado); clawback seller apaga 'venda' + debita saldo.

create or replace function public.batata_order_wallet_remaining_eur(
  p_order public.orders
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base numeric;
  v_net numeric;
begin
  v_base := public.batata_order_wallet_base_eur(p_order);
  if v_base <= 0 then
    return 0::numeric(12, 2);
  end if;
  v_net := public.batata_order_wallet_net_disbursed_eur(p_order.id);
  return greatest(v_base - v_net, 0)::numeric(12, 2);
end;
$$;

revoke all on function public.batata_order_wallet_net_disbursed_eur(uuid)
  from public, anon;
grant execute on function public.batata_order_wallet_net_disbursed_eur(uuid)
  to authenticated, service_role;

revoke all on function public.batata_order_wallet_remaining_eur(public.orders)
  from public, anon;
grant execute on function public.batata_order_wallet_remaining_eur(public.orders)
  to authenticated, service_role;

-- Débito idempotente (clawback). Unique parcial por (wallet, order, type, description)?
-- Usamos type=estorno + description estável; unique index actual é (wallet_id, order_id, type)
-- → um estorno por wallet/order. Suficiente para clawback de venda única.
create or replace function public.batata_debit_wallet_once(
  p_wallet_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_description text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
  v_row_count integer := 0;
  v_bal numeric;
begin
  if p_wallet_id is null or p_order_id is null then
    return false;
  end if;
  if coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    order_id
  ) values (
    p_wallet_id,
    round(p_amount, 2),
    'estorno',
    coalesce(nullif(trim(p_description), ''), 'Estorno encomenda'),
    p_order_id
  )
  on conflict (wallet_id, order_id, type) where order_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  v_inserted := v_row_count > 0;

  if v_inserted then
    select balance into v_bal from public.wallets where id = p_wallet_id for update;
    update public.wallets
    set balance = round(greatest(coalesce(v_bal, 0) - p_amount, 0), 2),
        updated_at = now()
    where id = p_wallet_id;
  end if;

  return v_inserted;
end;
$$;

revoke all on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  to service_role;

-- Clawback: remove créditos 'venda' do seller nesta order e debita saldo.
-- Apaga a row 'venda' para libertar o slot do unique (wallet, order, type)
-- e permitir residual pós-disputa. Audit: raise log.
create or replace function public.batata_clawback_seller_wallet_for_order(
  p_order_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_credited numeric := 0;
  v_bal numeric;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id is null then
    return 0;
  end if;

  select coalesce(sum(amount), 0) into v_credited
  from public.wallet_transactions
  where order_id = p_order_id
    and wallet_id = v_order.seller_id
    and type = 'venda';

  if v_credited <= 0 then
    return 0;
  end if;

  delete from public.wallet_transactions
  where order_id = p_order_id
    and wallet_id = v_order.seller_id
    and type = 'venda';

  perform public.batata_ensure_wallet(v_order.seller_id);
  select balance into v_bal
  from public.wallets
  where id = v_order.seller_id
  for update;

  update public.wallets
  set balance = round(greatest(coalesce(v_bal, 0) - v_credited, 0), 2),
      updated_at = now()
  where id = v_order.seller_id;

  raise log
    'BATATA_WALLET clawback order=% seller=% amount=%',
    p_order_id, v_order.seller_id, v_credited;

  return v_credited;
end;
$$;

revoke all on function public.batata_clawback_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_clawback_seller_wallet_for_order(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 1) Release seller — teto = remaining (nunca > captura − já desembolsado)
-- ---------------------------------------------------------------------------
create or replace function public.batata_release_seller_wallet_for_order(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_product_title text;
  v_amount numeric;
  v_base numeric;
  v_remaining numeric;
  v_done boolean;
  v_cleared int;
begin
  perform set_config('batata.wallet_internal', '1', true);

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.seller_id is null then
    return false;
  end if;

  if auth.uid() is not null and auth.uid() <> v_order.buyer_id
     and coalesce(auth.role(), '') = 'authenticated'
     and not public.batata_is_admin() then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido') then
    return false;
  end if;

  if v_order.wallet_release_processed_at is not null then
    return false;
  end if;

  -- Já houve reembolso buyer (total/parcial): não libertar de novo.
  if v_order.wallet_refund_processed_at is not null then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id
      and wallet_release_processed_at is null;
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);

  if v_base <= 0 or v_remaining <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id
      and wallet_release_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0 and v_base <= 0;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products
  where id = v_order.product_id;

  -- Seller = min(base − commission, remaining)
  v_amount := greatest(v_base - public.batata_order_commission_amount(v_base), 0);
  v_amount := least(v_amount, v_remaining);

  if v_amount <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id
      and wallet_release_processed_at is null;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_amount,
    'venda',
    'Venda de ' || coalesce(v_product_title, 'artigo Fleaber')
  );

  if v_done then
    perform public.batata_record_fleaber_commission_once(
      v_order.id,
      public.batata_order_commission_amount(v_base),
      'protection_fee',
      'Taxa de Proteção Fleaber'
    );
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id;
  end if;

  return v_done;
end;
$$;

revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Refund buyer (devolvida) — clawback seller se já libertado; teto remaining
-- ---------------------------------------------------------------------------
create or replace function public.batata_refund_buyer_wallet_for_order(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
  v_base numeric;
  v_remaining numeric;
  v_label_fee numeric := 0;
  v_done boolean;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute record;
  v_cleared int;
begin
  perform set_config('batata.wallet_internal', '1', true);

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null then
      return false;
    end if;
    if v_uid is distinct from v_order.buyer_id
       and v_uid is distinct from v_order.seller_id
       and not public.batata_is_admin() then
      return false;
    end if;
  end if;

  if lower(coalesce(v_order.status, '')) <> 'devolvida' then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);

  if v_base <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id
      and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  -- Devolver após release: recuperar fundos do seller antes de creditar buyer.
  perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  delete from public.fleaber_commissions
  where order_id = v_order.id
    and source = 'protection_fee';

  -- Re-ler remaining após clawback.
  select * into v_order from public.orders where id = p_order_id;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);

  v_amount := least(v_base, v_remaining);

  select od.seller_pays_return_shipping,
         od.return_label_created_at,
         od.buyer_decision
    into v_dispute
  from public.order_disputes od
  where od.order_id = v_order.id
  order by od.created_at desc
  limit 1;

  if found
     and coalesce(v_dispute.seller_pays_return_shipping, false) = false
     and v_dispute.return_label_created_at is not null
     and coalesce(v_dispute.buyer_decision, '') = 'accepted_return'
  then
    v_label_fee := 3.50;
  end if;

  if v_label_fee > 0 and v_amount > v_label_fee then
    v_amount := v_amount - v_label_fee;
  elsif v_label_fee > 0 and v_amount <= v_label_fee then
    v_amount := 0;
  end if;

  if v_amount <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
    return true;
  end if;

  -- Teto final: nunca exceder remaining actual.
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  v_amount := least(v_amount, v_remaining);

  if v_amount <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_amount,
    'reembolso',
    case
      when v_label_fee > 0 then
        'Reembolso Encomenda #' || left(v_order.id::text, 8)
          || ' (abatida etiqueta ' || to_char(v_label_fee, 'FM999990.00') || ' €)'
      else
        'Reembolso Encomenda #' || left(v_order.id::text, 8)
    end
  );

  if v_done or v_amount <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return v_done;
end;
$$;

revoke all on function public.batata_refund_buyer_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_refund_buyer_wallet_for_order(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Partial refund — clawback prévio se release já ocorreu; teto remaining
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_remaining numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute public.order_disputes%rowtype;
  v_status text;
  v_paid_ok boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);

  if p_order_id is null then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  elsif v_role is distinct from 'service_role' and v_uid is not null then
    if v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  v_paid_ok := v_status in (
    'pago', 'enviado', 'entregue', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );
  if not v_paid_ok then
    raise exception 'order_not_paid_for_refund';
  end if;

  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
  end if;

  -- Se já houve release, clawback para recalcular split sobre a captura.
  if v_order.wallet_release_processed_at is not null then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
    -- permitir re-release residual abaixo
    update public.orders
    set wallet_release_processed_at = null
    where id = v_order.id;
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  if v_remaining <= 0 then
    raise exception 'no_wallet_remaining_for_refund';
  end if;

  select *
  into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and d.seller_offer_set_by is not null
    and d.seller_offer_set_by = v_order.seller_id
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and lower(coalesce(d.seller_offer_type, '')) in (
      'partial_refund',
      'return_and_partial_refund'
    )
  order by d.created_at desc
  limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);
  v_refund := round(least(v_total, v_remaining) * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  -- Residual seller capped by what remains after buyer refund within remaining pool.
  v_seller_amount := greatest(
    least(v_remaining - v_refund, greatest(v_total - v_refund - v_commission, 0)),
    0
  );

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id,
      v_order.id,
      v_refund,
      'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
  else
    v_buyer_done := true;
  end if;

  if v_seller_amount > 0 then
    v_seller_done := public.batata_credit_wallet_once(
      v_order.seller_id,
      v_order.id,
      v_seller_amount,
      'venda',
      'Venda residual após disputa #' || left(v_order.id::text, 8)
    );
  else
    v_seller_done := true;
  end if;

  if v_buyer_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return v_buyer_done and v_seller_done;
end;
$$;

revoke all on function public.batata_process_partial_refund_dispute(uuid, numeric)
  from public, anon;
grant execute on function public.batata_process_partial_refund_dispute(uuid, numeric)
  to authenticated, service_role;

comment on function public.batata_process_partial_refund_dispute(uuid, numeric) is
  'RETESTE: buyer-only; oferta seller; base captura; clawback se release prévio; net disbursed ≤ captura.';

-- ---------------------------------------------------------------------------
-- 4) Stripe cancelado após release: clawback seller (sem mint buyer — Stripe refund)
-- ---------------------------------------------------------------------------
create or replace function public.batata_wallet_order_status_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if v_new = 'devolvida' then
    perform public.batata_refund_buyer_wallet_for_order(new.id);
  end if;

  -- Cancelamento pós-pago (refund-order / oversell): se seller já recebeu, estornar.
  if v_new in ('cancelado', 'cancelada', 'cancelled', 'canceled')
     and v_new is distinct from v_old then
    if new.wallet_release_processed_at is not null
       or exists (
         select 1 from public.wallet_transactions wt
         where wt.order_id = new.id and wt.type = 'venda'
       ) then
      perform public.batata_clawback_seller_wallet_for_order(new.id);
    end if;
    -- Fechar flags sem creditar buyer (dinheiro volta via Stripe).
    update public.orders
    set wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists batata_wallet_order_status_trg on public.orders;
create trigger batata_wallet_order_status_trg
after insert or update of status on public.orders
for each row
execute function public.batata_wallet_order_status_trigger();

-- ---------------------------------------------------------------------------
-- 5) Chat: participante não edita/apaga mensagem alheia
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  -- Nunca spoof identidade / chat.
  NEW.sender_id := OLD.sender_id;
  NEW.chat_id := OLD.chat_id;
  NEW.created_at := OLD.created_at;

  if OLD.sender_id is distinct from v_uid then
    -- Outro participante: só pode marcar lida (is_read).
    NEW.text := OLD.text;
    NEW.receiver_id := OLD.receiver_id;
    NEW.is_reservation := OLD.is_reservation;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_update on public.chat_messages;
create trigger trg_batata_chat_messages_guard_update
  before update on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_update();

drop policy if exists "chat_messages_update_participants" on public.chat_messages;
create policy "chat_messages_update_participants"
  on public.chat_messages for update
  using (public.batata_chat_is_participant(chat_id))
  with check (public.batata_chat_is_participant(chat_id));

drop policy if exists "chat_messages_delete_own" on public.chat_messages;
create policy "chat_messages_delete_own"
  on public.chat_messages for delete
  using (
    sender_id = auth.uid()
    and public.batata_chat_is_participant(chat_id)
  );

-- ---------------------------------------------------------------------------
-- 6) Quantity pré-pago: cap por stock do produto + max 99 (multi-qty legítimo)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_quantity_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_stock int;
  v_qty int;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  v_qty := coalesce(NEW.quantity, 1);
  if v_qty < 1 then
    v_qty := 1;
  end if;
  if v_qty > 99 then
    v_qty := 99;
  end if;

  if NEW.product_id is not null then
    select coalesce(p.quantity, 0) into v_stock
    from public.products p
    where p.id = NEW.product_id;
    if v_stock is null then
      v_stock := 0;
    end if;
    -- Pré-pago: não reservar mais do que stock actual (settle FASE2 continua atómico).
    if lower(trim(coalesce(NEW.status, ''))) not in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor', 'cancelado'
    ) then
      if v_stock < 1 then
        v_qty := 1; -- row may still exist; checkout/settle will fail closed on stock
      elsif v_qty > v_stock then
        v_qty := v_stock;
      end if;
    end if;
  end if;

  NEW.quantity := v_qty;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_quantity_authority on public.orders;
create trigger trg_batata_orders_guard_quantity_authority
  before insert or update of quantity
  on public.orders
  for each row
  execute function public.batata_orders_guard_quantity_authority();

-- ---------------------------------------------------------------------------
-- 7) NULL product qty → 0 (não inventar unidade); live_item NULL qty path
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_item_total_qty(p_live_item_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_qty integer;
  v_seller uuid;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    select p.quantity into v_qty
    from public.products p
    where p.id = v_li.product_id;
    -- NULL = desconhecido → 0 (fail-closed). 0 explícito → 0.
    if v_qty is null then
      return 0;
    end if;
    return greatest(v_qty, 0);
  end if;

  if v_li.item_kind = 'live_only' then
    select coalesce(l.seller_id, l.vendedor_id) into v_seller
    from public.lives l
    where l.id = v_li.live_id;
    if v_seller is not null then
      return public.batata_ref_history_pool_base_qty(
        v_seller,
        coalesce(v_li.logical_item_id, v_li.id)
      );
    end if;
  end if;

  -- live_items.quantity: CHECK exige >=1 para live_only; marketplace usa NULL.
  if v_li.quantity is null then
    return 0;
  end if;
  return greatest(v_li.quantity, 0);
end;
$$;

revoke all on function public.batata_live_item_total_qty(uuid) from public;
grant execute on function public.batata_live_item_total_qty(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
