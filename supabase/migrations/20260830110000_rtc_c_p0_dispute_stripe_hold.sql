-- RTC-C-P0-001 + F-CAP-01 (staging BATATA)
-- P0: após wallet disputa disputa disputa disputa disputa (disputa), refund-order Stripe não pode
--      restituir de novo o mesmo amount_paid (cap residual).
-- P1: reserva_pendente volta a contar no hold COM TTL 90 min
--      (B-2012 tirou pending por DoS infinito; Indep explorou N Sessions).
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- F-CAP-01: hold inclui pending recente (TTL) + estados accept
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_status_holds_product_qty(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento',
    'reserva_pendente',
    'pendente'
  );
$$;

comment on function public.batata_order_status_holds_product_qty(text) is
  'F-CAP-01: hold inclui reserva_pendente; TTL aplicado em batata_product_held_qty.';

create or replace function public.batata_product_held_qty(
  p_product_id uuid,
  p_exclude_order_id uuid default null,
  p_exclude_order_ids uuid[] default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_held int := 0;
  v_live int := 0;
  v_pending_ttl interval := interval '90 minutes';
begin
  if p_product_id is null then
    return 0;
  end if;
  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = p_product_id
    and (p_exclude_order_id is null or o.id is distinct from p_exclude_order_id)
    and (
      p_exclude_order_ids is null
      or cardinality(p_exclude_order_ids) = 0
      or not (o.id = any (p_exclude_order_ids))
    )
    and coalesce(o.status, '') not in (
      'cancelado', 'cancelled', 'rejected', 'expired'
    )
    and public.batata_order_status_holds_product_qty(o.status)
    and (
      -- Accept / pagamento em curso: hold sem TTL
      lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento'
      )
      -- Lista de espera: só recente (anti-DoS B-2012 + anti N-Sessions Indep)
      or (
        lower(trim(coalesce(o.status, ''))) in ('reserva_pendente', 'pendente')
        and o.created_at > (timezone('utc', now()) - v_pending_ttl)
      )
    );

  select coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
    into v_live
  from public.live_reservation_requests r
  join public.live_items li on li.id = r.live_item_id
  where r.status = 'accepted'
    and coalesce(li.product_id, li.checkout_product_id) = p_product_id;

  return v_held + v_live;
end;
$$;

comment on function public.batata_product_held_qty(uuid, uuid, uuid[]) is
  'F-CAP-01: pending <90min conta no hold; accept conta sempre; live accepted.';

-- ---------------------------------------------------------------------------
-- Helper: cêntimos já restituídos via wallet (reembolso − estorno) nesta order
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_wallet_reembolso_cents(p_order_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eur numeric := 0;
begin
  if p_order_id is null then
    return 0;
  end if;
  select coalesce(sum(
    case
      when type = 'reembolso' then amount
      when type = 'estorno' then -amount
      else 0
    end
  ), 0) into v_eur
  from public.wallet_transactions
  where order_id = p_order_id;
  return greatest(round(v_eur * 100), 0)::int;
end;
$$;

revoke all on function public.batata_order_wallet_reembolso_cents(uuid)
  from public, anon;
grant execute on function public.batata_order_wallet_reembolso_cents(uuid)
  to authenticated, service_role;

comment on function public.batata_order_wallet_reembolso_cents(uuid) is
  'RTC-C-P0-001: quanto já foi mintado/reembolsado em wallet nesta order (cêntimos).';

notify pgrst, 'reload schema';
