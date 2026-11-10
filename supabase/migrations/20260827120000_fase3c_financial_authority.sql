-- =============================================================================
-- FASE 3C — Autoridade financeira + autorização crítica (BATATA)
-- Staging only · Stripe TEST · NÃO é Fase 4 (consolidação schema).
-- Idempotente. Fecha classe: JWT não fabrica saldo levantável sem fundos
-- autoritativos da plataforma (amount_paid_cents / captura settle).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) Colunas auxiliares
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists amount_paid_cents integer;

alter table public.order_disputes
  add column if not exists seller_offer_set_by uuid,
  add column if not exists seller_offer_set_at timestamptz;

comment on column public.order_disputes.seller_offer_set_by is
  'FASE3C: uuid do vendedor (ou service) que gravou a oferta de refund; comprador nunca.';

-- ---------------------------------------------------------------------------
-- 1) Autoridade financeira da plataforma
-- ---------------------------------------------------------------------------
-- Fundos Fleaber capturados: só amount_paid_cents>0 (escrito por settle/service).
-- MB WAY / «vendedor diz que recebeu» → 0 (estados de negócio OK; wallet NÃO).
create or replace function public.batata_order_platform_funds_eur(
  p_order public.orders
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
begin
  if coalesce(p_order.amount_paid_cents, 0) > 0 then
    return round(p_order.amount_paid_cents::numeric / 100.0, 2);
  end if;
  return 0::numeric(12, 2);
end;
$$;

-- Base para qualquer crédito/refund/release wallet: least(comercial, capturado).
-- Sem captura → 0 (fail-closed).
create or replace function public.batata_order_wallet_base_eur(
  p_order public.orders
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_funds numeric;
  v_price numeric;
begin
  v_funds := public.batata_order_platform_funds_eur(p_order);
  if v_funds <= 0 then
    return 0::numeric(12, 2);
  end if;
  v_price := greatest(coalesce(p_order.price_total, 0), 0)::numeric(12, 2);
  if v_price <= 0 then
    return v_funds;
  end if;
  return least(v_price, v_funds)::numeric(12, 2);
end;
$$;

revoke all on function public.batata_order_platform_funds_eur(public.orders)
  from public, anon;
grant execute on function public.batata_order_platform_funds_eur(public.orders)
  to authenticated, service_role;

revoke all on function public.batata_order_wallet_base_eur(public.orders)
  from public, anon;
grant execute on function public.batata_order_wallet_base_eur(public.orders)
  to authenticated, service_role;

comment on function public.batata_order_platform_funds_eur(public.orders) is
  'FASE3C: EUR capturados pela plataforma (amount_paid_cents). MB WAY=0.';
comment on function public.batata_order_wallet_base_eur(public.orders) is
  'FASE3C: least(price_total, platform_funds); 0 se sem captura.';

-- ---------------------------------------------------------------------------
-- 2) Release seller — só com fundos de plataforma
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

  v_base := public.batata_order_wallet_base_eur(v_order);

  -- Sem fundos Fleaber (ex. MB WAY): marcar libertação sem mint.
  if v_base <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id
      and wallet_release_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products
  where id = v_order.product_id;

  v_amount := greatest(
    v_base - public.batata_order_commission_amount(v_base),
    0
  );
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
-- 3) Refund buyer on devolvida — só com fundos de plataforma
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

  -- Sem captura Fleaber: fechar o caminho sem mint (MB WAY / fake-pago).
  if v_base <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now())
    where id = v_order.id
      and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  v_amount := v_base;

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
        returned_at = coalesce(returned_at, now())
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

  if v_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now())
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
-- 4) Partial refund disputa — autoridade + % só do vendedor
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

  if v_order.wallet_release_processed_at is not null
     or v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  v_paid_ok := v_status in (
    'pago',
    'enviado',
    'entregue',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );

  if not v_paid_ok then
    raise exception 'order_not_paid_for_refund';
  end if;

  -- Sem captura plataforma → sem crédito wallet (fecha P0-01+P0-02 encadeados).
  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
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

  -- p_refund_percent do cliente continua ignorado.
  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);
  v_refund := round(v_total * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(v_total - v_refund - v_commission, 0);

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id,
      v_order.id,
      v_refund,
      'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
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

  if v_buyer_done or v_refund <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return (v_refund <= 0 or v_buyer_done) and v_seller_done;
end;
$$;

revoke all on function public.batata_process_partial_refund_dispute(uuid, numeric)
  from public, anon;
grant execute on function public.batata_process_partial_refund_dispute(uuid, numeric)
  to authenticated, service_role;

comment on function public.batata_process_partial_refund_dispute(uuid, numeric) is
  'FASE3C: buyer-only; pós-pago; % só oferta vendedor (seller_offer_set_by); base=wallet_base (captura).';

-- ---------------------------------------------------------------------------
-- 5) Disputa: trigger — comprador não grava oferta do vendedor
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_seller_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_is_seller boolean := false;
  v_offer_touched boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    -- service_role / triggers internos: se oferta presente, carimbar seller.
    if TG_OP = 'INSERT' then
      if NEW.seller_refund_percent is not null
         or NEW.seller_offer_type is not null then
        select o.seller_id into v_seller from public.orders o where o.id = NEW.order_id;
        NEW.seller_offer_set_by := coalesce(NEW.seller_offer_set_by, v_seller);
        NEW.seller_offer_set_at := coalesce(NEW.seller_offer_set_at, now());
      end if;
    elsif TG_OP = 'UPDATE' then
      if NEW.seller_refund_percent is distinct from OLD.seller_refund_percent
         or NEW.seller_offer_type is distinct from OLD.seller_offer_type
         or NEW.seller_pays_return_shipping is distinct from OLD.seller_pays_return_shipping then
        select o.seller_id into v_seller from public.orders o where o.id = NEW.order_id;
        NEW.seller_offer_set_by := coalesce(v_seller, NEW.seller_offer_set_by);
        NEW.seller_offer_set_at := now();
      end if;
    end if;
    return NEW;
  end if;

  select o.seller_id into v_seller
  from public.orders o
  where o.id = NEW.order_id;
  v_is_seller := v_seller is not null and v_seller = v_uid;

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.seller_refund_percent := null;
      NEW.seller_offer_type := null;
      NEW.seller_pays_return_shipping := false;
      NEW.seller_offer_set_by := null;
      NEW.seller_offer_set_at := null;
    else
      if NEW.seller_refund_percent is not null
         or NEW.seller_offer_type is not null then
        NEW.seller_offer_set_by := v_uid;
        NEW.seller_offer_set_at := now();
      end if;
    end if;
    return NEW;
  end if;

  -- UPDATE
  v_offer_touched :=
    NEW.seller_refund_percent is distinct from OLD.seller_refund_percent
    or NEW.seller_offer_type is distinct from OLD.seller_offer_type
    or NEW.seller_pays_return_shipping is distinct from OLD.seller_pays_return_shipping
    or NEW.seller_offer_set_by is distinct from OLD.seller_offer_set_by
    or NEW.seller_offer_set_at is distinct from OLD.seller_offer_set_at;

  if v_offer_touched and not v_is_seller then
    NEW.seller_refund_percent := OLD.seller_refund_percent;
    NEW.seller_offer_type := OLD.seller_offer_type;
    NEW.seller_pays_return_shipping := OLD.seller_pays_return_shipping;
    NEW.seller_offer_set_by := OLD.seller_offer_set_by;
    NEW.seller_offer_set_at := OLD.seller_offer_set_at;
  elsif v_offer_touched and v_is_seller then
    NEW.seller_offer_set_by := v_uid;
    NEW.seller_offer_set_at := now();
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_seller_offer
  on public.order_disputes;
create trigger trg_batata_order_disputes_guard_seller_offer
  before insert or update on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_seller_offer();

-- ---------------------------------------------------------------------------
-- 6) Stock: restaurar também em devolvida (claim stock_units_applied)
-- ---------------------------------------------------------------------------
create or replace function public.batata_restore_product_stock_on_cancelled_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_after int;
  v_old text;
  v_new text;
  v_pm text;
  v_cleared int;
  v_restore boolean := false;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if new.product_id is null then
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;

  if v_new in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) or position('cancelad' in v_new) > 0
    or position('anulad' in v_new) > 0 then
    v_restore := true;
  end if;

  -- FASE3C: devolvida também liberta stock claimado (P1-04).
  if v_new = 'devolvida' then
    v_restore := true;
  end if;

  if not v_restore then
    return new;
  end if;

  v_pm := lower(trim(coalesce(new.payment_method, '')));
  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    update public.orders
       set stock_units_applied = null
     where id = new.id
       and stock_units_applied is not null;
    return new;
  end if;

  v_units := new.stock_units_applied;
  if v_units is null or v_units <= 0 then
    return new;
  end if;

  update public.orders
     set stock_units_applied = null
   where id = new.id
     and stock_units_applied is not null;
  get diagnostics v_cleared = row_count;
  if v_cleared = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = new.product_id
   returning quantity into v_after;

  raise log
    'BATATA_STOCK restore order=% product=% units=% qty_before=% qty_after=% old_status=% new_status=%',
    new.id, new.product_id, v_units, v_before, v_after, v_old, v_new;

  return new;
end;
$$;

comment on function public.batata_restore_product_stock_on_cancelled_order() is
  'FASE2+3C: repõe stock em cancelado OU devolvida via claim stock_units_applied 1×.';

-- ---------------------------------------------------------------------------
-- 7) Live qty: quantity=0 não vira 1
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
    -- NULL legado → 1; 0 explícito → 0 (não inventar unidade).
    if v_qty is null then
      return 1;
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

  if v_li.quantity is null then
    return 1;
  end if;
  return greatest(v_li.quantity, 0);
end;
$$;

revoke all on function public.batata_live_item_total_qty(uuid) from public;
grant execute on function public.batata_live_item_total_qty(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8b) Remover policies abertas legado (OR com as novas = buraco)
-- ---------------------------------------------------------------------------
alter table public.chats enable row level security;
alter table public.chat_messages enable row level security;
drop policy if exists "Permitir tudo chats" on public.chats;
drop policy if exists "Permitir tudo mensagens" on public.chat_messages;
drop policy if exists "Acesso Total" on public.reviews;
-- Reviews: leitura pública de marketplace OK; escrita só via policies 3C.
drop policy if exists "Permitir leitura pública" on public.reviews;
drop policy if exists "reviews_select_public_marketplace" on public.reviews;
create policy "reviews_select_public_marketplace"
  on public.reviews for select
  using (true);


drop policy if exists "chats_select_participants" on public.chats;
create policy "chats_select_participants"
  on public.chats for select
  using (auth.uid() = user_a or auth.uid() = user_b);

drop policy if exists "chats_insert_participant" on public.chats;
create policy "chats_insert_participant"
  on public.chats for insert
  with check (
    auth.uid() is not null
    and (auth.uid() = user_a or auth.uid() = user_b)
    and user_a is not null
    and user_b is not null
    and user_a is distinct from user_b
  );

drop policy if exists "chats_update_participants" on public.chats;
create policy "chats_update_participants"
  on public.chats for update
  using (auth.uid() = user_a or auth.uid() = user_b)
  with check (auth.uid() = user_a or auth.uid() = user_b);

drop policy if exists "chats_delete_participants" on public.chats;
create policy "chats_delete_participants"
  on public.chats for delete
  using (auth.uid() = user_a or auth.uid() = user_b);

-- Helper: participante do chat
create or replace function public.batata_chat_is_participant(p_chat_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.chats c
    where c.id = p_chat_id
      and (c.user_a = auth.uid() or c.user_b = auth.uid())
  );
$$;

revoke all on function public.batata_chat_is_participant(uuid) from public, anon;
grant execute on function public.batata_chat_is_participant(uuid)
  to authenticated, service_role;

drop policy if exists "chat_messages_select_participants" on public.chat_messages;
create policy "chat_messages_select_participants"
  on public.chat_messages for select
  using (public.batata_chat_is_participant(chat_id));

drop policy if exists "chat_messages_insert_self_sender" on public.chat_messages;
create policy "chat_messages_insert_self_sender"
  on public.chat_messages for insert
  with check (
    auth.uid() is not null
    and sender_id = auth.uid()
    and public.batata_chat_is_participant(chat_id)
  );

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

-- Defesa: forçar sender_id = auth.uid() em INSERT JWT
create or replace function public.batata_chat_messages_guard_sender()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role = 'authenticated' and v_uid is not null then
    NEW.sender_id := v_uid;
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_sender on public.chat_messages;
create trigger trg_batata_chat_messages_guard_sender
  before insert on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_sender();

-- ---------------------------------------------------------------------------
-- 9) Reviews — autorização + não spoof
-- ---------------------------------------------------------------------------
alter table public.reviews enable row level security;

drop policy if exists "reviews_select_parties" on public.reviews;
create policy "reviews_select_parties"
  on public.reviews for select
  using (
    buyer_id = auth.uid()
    or target_id = auth.uid()
    or exists (
      select 1 from public.orders o
      where o.id = reviews.order_id
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
  );

drop policy if exists "reviews_insert_buyer_own_order" on public.reviews;
create policy "reviews_insert_buyer_own_order"
  on public.reviews for insert
  with check (
    auth.uid() is not null
    and buyer_id = auth.uid()
    and order_id is not null
    and exists (
      select 1 from public.orders o
      where o.id = reviews.order_id
        and o.buyer_id = auth.uid()
        and lower(coalesce(o.status, '')) in ('concluido', 'entregue')
    )
  );

drop policy if exists "reviews_update_own" on public.reviews;
create policy "reviews_update_own"
  on public.reviews for update
  using (buyer_id = auth.uid())
  with check (buyer_id = auth.uid());

drop policy if exists "reviews_delete_own" on public.reviews;
create policy "reviews_delete_own"
  on public.reviews for delete
  using (buyer_id = auth.uid());

create or replace function public.batata_reviews_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_order public.orders%rowtype;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.buyer_id := v_uid;
  NEW.is_automatic := coalesce(NEW.is_automatic, false);

  if NEW.order_id is null then
    raise exception 'review_order_required' using errcode = '23514';
  end if;

  select * into v_order from public.orders where id = NEW.order_id;
  if not found or v_order.buyer_id is distinct from v_uid then
    raise exception 'review_order_not_yours' using errcode = '42501';
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido', 'entregue') then
    raise exception 'review_order_invalid_status' using errcode = '23514';
  end if;

  -- target = seller da order (não spoof)
  NEW.target_id := v_order.seller_id;
  if lower(coalesce(NEW.author_role, '')) = '' then
    NEW.author_role := 'comprador';
  end if;

  if exists (
    select 1 from public.reviews r
    where r.order_id = NEW.order_id
      and r.buyer_id = v_uid
      and lower(coalesce(r.author_role, 'comprador')) = 'comprador'
  ) then
    raise exception 'review_duplicate' using errcode = '23505';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_insert on public.reviews;
create trigger trg_batata_reviews_guard_insert
  before insert on public.reviews
  for each row
  execute function public.batata_reviews_guard_insert();

-- Unique soft: um review comprador por order (se ainda não existir índice)
create unique index if not exists reviews_buyer_order_comprador_uidx
  on public.reviews (order_id, buyer_id)
  where order_id is not null
    and lower(coalesce(author_role, 'comprador')) = 'comprador';

-- ---------------------------------------------------------------------------
-- 10) Accept reserva: não criar disponibilidade inexistente (qty=0)
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_live_reservation_request(
  p_request_id uuid,
  p_action text,
  p_processed_by uuid default auth.uid(),
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_item_qty int := 0;
  v_reserved_qty int := 0;
  v_sibling_qty int := 0;
  v_final_qty int := 1;
  v_already int := 0;
  v_avail int := 0;
  v_next_status text;
  v_item_status text;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if p_action not in ('accept', 'reject', 'skip', 'expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'invalid_action');
  end if;

  select coalesce(status, '') into v_item_status
  from public.live_items
  where id = v_req.live_item_id;

  if v_item_status = 'sold' and p_action in ('accept', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'item_sold');
  end if;

  if not (
    auth.uid() = v_req.seller_id
    or public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if p_action = 'accept' then
    select coalesce(sum(r.requested_qty), 0)::int
    into v_sibling_qty
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.live_id = v_req.live_id
      and r.buyer_id = v_req.buyer_id
      and r.id <> v_req.id
      and r.status = 'pending';

    v_final_qty := greatest(
      coalesce(v_req.requested_qty, 1) + coalesce(v_sibling_qty, 0),
      1
    );

    v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);
    if v_item_qty <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'no_stock',
        'available_qty', 0
      );
    end if;

    select coalesce(sum(r.requested_qty), 0)::int
    into v_already
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.status in ('accepted', 'converted')
      and r.id is distinct from v_req.id;

    v_avail := greatest(v_item_qty - v_already, 0);
    if v_final_qty > v_avail then
      return jsonb_build_object(
        'ok', false,
        'error', 'qty_exceeds_stock',
        'available_qty', v_avail,
        'requested', v_final_qty
      );
    end if;

    update public.live_reservation_requests
    set
      status = 'rejected',
      notes = trim(both ' |' from coalesce(notes, '') || ' | superseded:sibling_accept'),
      updated_at = now()
    where live_item_id = v_req.live_item_id
      and live_id = v_req.live_id
      and buyer_id = v_req.buyer_id
      and id <> v_req.id
      and status = 'pending';
  end if;

  update public.live_reservation_requests
  set
    requested_qty = case
      when p_action = 'accept' then v_final_qty
      else requested_qty
    end,
    status = case
      when p_action = 'accept' then 'accepted'
      when p_action = 'reject' then 'rejected'
      when p_action = 'skip' then 'rejected'
      when p_action = 'expire' then 'expired'
      else 'converted'
    end,
    expires_at = case
      when p_action = 'accept' then now() + interval '5 days'
      else expires_at
    end,
    notes = case
      when p_action = 'accept' then trim(both ' |' from regexp_replace(
        regexp_replace(coalesce(notes, ''), 'qty_confirm_needed', '', 'gi'),
        '\s*\|\s*\|', ' | ', 'g'))
      when p_action = 'skip' then coalesce('skip:' || p_notes, 'skip')
      else coalesce(p_notes, notes)
    end,
    processed_by_user_id = coalesce(p_processed_by, auth.uid()),
    updated_at = now()
  where id = v_req.id;

  if v_item_status = 'sold' then
    return jsonb_build_object(
      'ok', true,
      'request_id', v_req.id,
      'item_status', 'sold'
    );
  end if;

  v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  if p_action in ('reject', 'skip', 'expire') then
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  end if;

  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  if p_action = 'accept' then
    perform public.batata_live_reservation_accept_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id,
      v_final_qty
    );
  elsif p_action = 'convert' then
    perform public.batata_live_purchase_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'reserved_qty', v_reserved_qty,
    'item_qty', v_item_qty
  );
end;
$$;

revoke all on function public.batata_process_live_reservation_request(uuid, text, uuid, text)
  from public, anon;
grant execute on function public.batata_process_live_reservation_request(uuid, text, uuid, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
