-- =============================================================================
-- PÓS-REAUDITORIA DC — estados devolução · ledger append-only · Stripe×wallet
-- · concorrência · qty fail-closed · reviews públicas sem PII
-- Staging only · Stripe TEST · NÃO Fase 4.
-- Idempotente.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) Ledger unique: permitir venda + estorno (+ residual com desc distinta)
-- ---------------------------------------------------------------------------
drop index if exists public.wallet_transactions_order_type_uidx;

-- Idempotência por (wallet, order, type, description) — trilha append-only.
-- Permite venda + estorno + residual venda (descrições distintas).
create unique index if not exists wallet_transactions_order_ledger_uidx
  on public.wallet_transactions (
    wallet_id,
    order_id,
    type,
    (coalesce(description, ''))
  )
  where order_id is not null;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check
  check (type in (
    'venda', 'compra', 'reembolso', 'levantamento', 'estorno',
    'gorjeta_enviada', 'gorjeta_recebida'
  ));

-- credit_wallet_once: conflito no novo índice
create or replace function public.batata_credit_wallet_once(
  p_wallet_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_type text,
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
  v_desc text := coalesce(nullif(trim(p_description), ''), p_type);
begin
  if p_wallet_id is null or p_order_id is null then
    return false;
  end if;
  if coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id, amount, type, description, order_id
  ) values (
    p_wallet_id, round(p_amount, 2), p_type, v_desc, p_order_id
  )
  on conflict (wallet_id, order_id, type, (coalesce(description, '')))
    where order_id is not null
  do nothing;

  get diagnostics v_row_count = row_count;
  v_inserted := v_row_count > 0;

  if v_inserted then
    update public.wallets
    set balance = round(balance + p_amount, 2),
        updated_at = now()
    where id = p_wallet_id;
  end if;

  return v_inserted;
end;
$$;

revoke all on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  to service_role;

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
  v_row_count integer := 0;
  v_bal numeric;
  v_desc text := coalesce(nullif(trim(p_description), ''), 'Estorno encomenda');
begin
  if p_wallet_id is null or p_order_id is null or coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id, amount, type, description, order_id
  ) values (
    p_wallet_id, round(p_amount, 2), 'estorno', v_desc, p_order_id
  )
  on conflict (wallet_id, order_id, type, (coalesce(description, '')))
    where order_id is not null
  do nothing;

  get diagnostics v_row_count = row_count;
  if v_row_count = 0 then
    return false;
  end if;

  select balance into v_bal from public.wallets where id = p_wallet_id for update;
  update public.wallets
  set balance = round(greatest(coalesce(v_bal, 0) - p_amount, 0), 2),
      updated_at = now()
  where id = p_wallet_id;

  return true;
end;
$$;

revoke all on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  to service_role;

-- Clawback APPEND-ONLY: estorno, NÃO apaga venda
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
  v_estornado numeric := 0;
  v_to_claw numeric := 0;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id is null then
    return 0;
  end if;

  -- Lock económico da order (concorrência release||refund).
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select coalesce(sum(amount), 0) into v_credited
  from public.wallet_transactions
  where order_id = p_order_id
    and wallet_id = v_order.seller_id
    and type = 'venda';

  select coalesce(sum(amount), 0) into v_estornado
  from public.wallet_transactions
  where order_id = p_order_id
    and wallet_id = v_order.seller_id
    and type = 'estorno';

  v_to_claw := greatest(v_credited - v_estornado, 0);
  if v_to_claw <= 0 then
    return 0;
  end if;

  -- Description inclui montante para ondas sucessivas (clawback → residual → clawback).
  if public.batata_debit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_to_claw,
    'Estorno venda encomenda #' || left(v_order.id::text, 8)
      || ' (' || to_char(v_to_claw, 'FM999990.00') || '€)'
  ) then
    raise log
      'BATATA_WALLET clawback_append order=% seller=% amount=%',
      p_order_id, v_order.seller_id, v_to_claw;
    return v_to_claw;
  end if;
  return 0;
end;
$$;

revoke all on function public.batata_clawback_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_clawback_seller_wallet_for_order(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 1) Máquina de estados JWT — devolução / pós-release
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  -- ---- Comprador ----
  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- Após libertação wallet: comprador não inicia/continua cadeia de devolução.
    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- pedido_devolucao só a partir de concluido/entregue + disputa existente.
    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'concluido' then
      if v_old not in (
        'enviado', 'entregue', 'pago', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    -- devolvida: só após cadeia de devolução + disputa da MESMA order.
    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    -- Seller não fabrica pedido_devolucao (é do buyer).
    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- Estranho (nem buyer nem seller): não muda status financeiro.
  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_paid_status on public.orders;
create trigger trg_batata_orders_guard_paid_status
  before insert or update of status
  on public.orders
  for each row
  execute function public.batata_orders_guard_paid_status();

comment on function public.batata_orders_guard_paid_status() is
  'DC-reauditoria: JWT não fabrica devolvida/pedido_devolucao fora do fluxo disputa; pós-release buyer bloqueado.';

-- ---------------------------------------------------------------------------
-- 2) Release / refund / partial — advisory lock + Stripe orphan + sem null release
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_wallet_net_disbursed_eur(p_order_id uuid)
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
  ), 0) into v_sum
  from public.wallet_transactions
  where order_id = p_order_id;
  return round(greatest(v_sum, 0), 2)::numeric(12, 2);
end;
$$;

create or replace function public.batata_order_wallet_remaining_eur(p_order public.orders)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base numeric;
begin
  v_base := public.batata_order_wallet_base_eur(p_order);
  if v_base <= 0 then
    return 0::numeric(12, 2);
  end if;
  return greatest(v_base - public.batata_order_wallet_net_disbursed_eur(p_order.id), 0)::numeric(12, 2);
end;
$$;

create or replace function public.batata_release_seller_wallet_for_order(p_order_id uuid)
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
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
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

  if v_order.wallet_refund_processed_at is not null then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  -- Disputa aberta: não libertar (evita payout → clawback floor → perda plataforma).
  -- Não marca wallet_release_processed_at — permite release depois se disputa fechar sem devolução.
  if exists (
    select 1 from public.order_disputes d
    where d.order_id = v_order.id
      and lower(coalesce(d.status, '')) is distinct from 'recusada'
      and lower(coalesce(d.status, '')) is distinct from 'fechada'
      and lower(coalesce(d.status, '')) is distinct from 'resolvida'
  ) then
    return false;
  end if;

  -- Stripe já reembolsou o cartão: não libertar wallet seller sobre a mesma captura.
  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    update public.orders
    set wallet_release_processed_at = now(),
        wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now())
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);

  if v_base <= 0 or v_remaining <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0 and v_base <= 0;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products where id = v_order.product_id;

  v_amount := least(
    greatest(v_base - public.batata_order_commission_amount(v_base), 0),
    v_remaining
  );

  if v_amount <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.seller_id, v_order.id, v_amount, 'venda',
    'Venda de ' || coalesce(v_product_title, 'artigo Fleaber')
  );

  if v_done then
    perform public.batata_record_fleaber_commission_once(
      v_order.id, public.batata_order_commission_amount(v_base),
      'protection_fee', 'Taxa de Proteção Fleaber'
    );
    update public.orders set wallet_release_processed_at = now() where id = v_order.id;
  end if;
  return v_done;
end;
$$;

revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

create or replace function public.batata_refund_buyer_wallet_for_order(p_order_id uuid)
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
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null then return false; end if;
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

  -- Mesma captura já devolvida no Stripe (oficial ou órfão): sem mint wallet.
  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  if v_base <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  delete from public.fleaber_commissions
  where order_id = v_order.id and source = 'protection_fee';

  select * into v_order from public.orders where id = p_order_id;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  v_amount := least(v_base, v_remaining);

  select od.seller_pays_return_shipping, od.return_label_created_at, od.buyer_decision
    into v_dispute
  from public.order_disputes od
  where od.order_id = v_order.id
  order by od.created_at desc limit 1;

  if found
     and coalesce(v_dispute.seller_pays_return_shipping, false) = false
     and v_dispute.return_label_created_at is not null
     and coalesce(v_dispute.buyer_decision, '') = 'accepted_return'
  then
    v_label_fee := 3.50;
  end if;

  if v_label_fee > 0 then
    v_amount := greatest(v_amount - v_label_fee, 0);
  end if;

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
    v_order.buyer_id, v_order.id, v_amount, 'reembolso',
    case when v_label_fee > 0 then
      'Reembolso Encomenda #' || left(v_order.id::text, 8)
        || ' (abatida etiqueta ' || to_char(v_label_fee, 'FM999990.00') || ' €)'
    else
      'Reembolso Encomenda #' || left(v_order.id::text, 8)
    end
  );

  if v_done then
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
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  if p_order_id is null then return false; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    raise exception 'stripe_refund_already_exists';
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  if v_status not in (
    'pago', 'enviado', 'entregue', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    raise exception 'order_not_paid_for_refund';
  end if;

  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
  end if;

  -- Clawback se já houve release; NÃO limpar flag (evita race re-release).
  if v_order.wallet_release_processed_at is not null then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  if v_remaining <= 0 then
    raise exception 'no_wallet_remaining_for_refund';
  end if;

  select * into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and d.seller_offer_set_by is not null
    and d.seller_offer_set_by = v_order.seller_id
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and lower(coalesce(d.seller_offer_type, '')) in (
      'partial_refund', 'return_and_partial_refund'
    )
  order by d.created_at desc limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);
  v_refund := round(least(v_total, v_remaining) * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(
    least(v_remaining - v_refund, greatest(v_total - v_refund - v_commission, 0)),
    0
  );

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id, v_order.id, v_refund, 'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
  else
    v_buyer_done := true;
  end if;

  if v_seller_amount > 0 then
    v_seller_done := public.batata_credit_wallet_once(
      v_order.seller_id, v_order.id, v_seller_amount, 'venda',
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

  if v_new in ('cancelado', 'cancelada', 'cancelled', 'canceled')
     and v_new is distinct from v_old then
    if new.wallet_release_processed_at is not null
       or exists (
         select 1 from public.wallet_transactions wt
         where wt.order_id = new.id and wt.type = 'venda'
       ) then
      perform public.batata_clawback_seller_wallet_for_order(new.id);
    end if;
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
-- 3) Qty inválida: fail-closed (não coerir 0/−1 → 1)
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

  if NEW.quantity is null or NEW.quantity < 1 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;
  if NEW.quantity > 99 then
    NEW.quantity := 99;
  end if;
  v_qty := NEW.quantity;

  if NEW.product_id is not null then
    select coalesce(p.quantity, 0) into v_stock
    from public.products p where p.id = NEW.product_id;
    if lower(trim(coalesce(NEW.status, ''))) not in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor', 'cancelado'
    ) then
      if v_stock < 1 then
        raise exception 'no_stock_for_order_quantity' using errcode = '23514';
      end if;
      if v_qty > v_stock then
        NEW.quantity := v_stock;
      end if;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_quantity_authority on public.orders;
create trigger trg_batata_orders_guard_quantity_authority
  before insert or update of quantity on public.orders
  for each row
  execute function public.batata_orders_guard_quantity_authority();

-- ---------------------------------------------------------------------------
-- 4) Reviews públicas sem order_id / buyer_id
-- ---------------------------------------------------------------------------
drop policy if exists "reviews_select_public_marketplace" on public.reviews;

-- Parties (buyer/seller da order ou autor) continuam a ler a tabela completa.
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

create or replace view public.reviews_public_ratings
as
select
  id,
  created_at,
  target_id,
  stars,
  comment,
  is_automatic,
  target_type,
  author_role
from public.reviews;

-- Owner bypass RLS → reputação pública sem expor buyer_id/order_id.
alter view public.reviews_public_ratings set (security_invoker = false);

revoke all on public.reviews_public_ratings from public;
grant select on public.reviews_public_ratings to anon, authenticated, service_role;

comment on view public.reviews_public_ratings is
  'DC-reauditoria: reputação pública sem buyer_id/order_id. Tabela reviews = parties only.';

notify pgrst, 'reload schema';
