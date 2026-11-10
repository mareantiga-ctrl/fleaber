-- =============================================================================
-- BATATA 2026-10-06 — Unified Commerce Phase 4
-- Canonical checkout attempt + technical payment holds (not commercial reservation).
-- Additive. Staging only. Does NOT edit prior migrations. production_touched: false
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) commerce_checkout_attempts — 1 logical payment / fulfillment key
-- -----------------------------------------------------------------------------
create table if not exists public.commerce_checkout_attempts (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users (id),
  seller_id uuid not null,
  guest_session_id uuid null,
  payment_rail text not null
    check (payment_rail in ('stripe', 'off_platform')),
  status text not null default 'drafted'
    check (status in (
      'drafted',
      'payment_started_valid',
      'payment_processing',
      'payment_succeeded',
      'payment_failed_technical',
      'payment_abandoned',
      'timed_out'
    )),
  shipping_method text null,
  items_cents integer not null default 0,
  shipping_cents integer not null default 0,
  protection_fee_cents integer not null default 0,
  total_cents integer not null default 0,
  currency text not null default 'eur',
  stripe_checkout_session_id text null,
  stripe_payment_intent_id text null,
  provider_reference text null,
  live_id uuid null,
  delivery_recipient_name text null,
  delivery_line1 text null,
  delivery_line2 text null,
  delivery_postal_code text null,
  delivery_city text null,
  delivery_country text null,
  delivery_phone text null,
  delivery_point_ref text null,
  delivery_point_provider text null
    check (
      delivery_point_provider is null
      or delivery_point_provider in ('dpd_pickup', 'dpd_locker', 'other', 'home')
    ),
  delivery_point_label text null,
  delivery_snapshot_at timestamptz null,
  fulfillment_recorded_at timestamptz null,
  client_idempotency_key text null,
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists uq_commerce_checkout_attempts_buyer_idem
  on public.commerce_checkout_attempts (buyer_id, client_idempotency_key)
  where client_idempotency_key is not null;

create index if not exists idx_commerce_checkout_attempts_buyer_status
  on public.commerce_checkout_attempts (buyer_id, status);

create index if not exists idx_commerce_checkout_attempts_expires
  on public.commerce_checkout_attempts (expires_at)
  where status in ('drafted', 'payment_started_valid', 'payment_processing');

revoke all on table public.commerce_checkout_attempts from public, anon, authenticated;
grant select, insert, update, delete on table public.commerce_checkout_attempts to service_role;
-- Buyer may read own attempts (no write — RPCs are definer)
grant select on table public.commerce_checkout_attempts to authenticated;

alter table public.commerce_checkout_attempts enable row level security;

drop policy if exists commerce_checkout_attempts_select_own on public.commerce_checkout_attempts;
create policy commerce_checkout_attempts_select_own
  on public.commerce_checkout_attempts
  for select to authenticated
  using (buyer_id = auth.uid());

comment on table public.commerce_checkout_attempts is
  'Phase 4: one logical checkout/payment → N order lines → 1 fulfillment (D25). Technical, not commercial reservation.';

-- -----------------------------------------------------------------------------
-- B) commerce_checkout_holds — short technical stock protection during payment
-- -----------------------------------------------------------------------------
create table if not exists public.commerce_checkout_holds (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.commerce_checkout_attempts (id) on delete cascade,
  buyer_id uuid not null,
  seller_id uuid not null,
  product_id uuid not null,
  live_item_id uuid null,
  reservation_request_id uuid null,
  quantity integer not null check (quantity > 0),
  -- When true, stock was already blocked by accepted/guaranteed LRR — hold links
  -- attempt but does NOT add a second stock debit.
  covers_guaranteed boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'consumed', 'released')),
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  released_at timestamptz null,
  consumed_at timestamptz null
);

create index if not exists idx_commerce_checkout_holds_product_active
  on public.commerce_checkout_holds (product_id)
  where status = 'active';

create index if not exists idx_commerce_checkout_holds_attempt
  on public.commerce_checkout_holds (attempt_id);

create index if not exists idx_commerce_checkout_holds_expires
  on public.commerce_checkout_holds (expires_at)
  where status = 'active';

revoke all on table public.commerce_checkout_holds from public, anon, authenticated;
grant all on table public.commerce_checkout_holds to service_role;
grant select on table public.commerce_checkout_holds to authenticated;

alter table public.commerce_checkout_holds enable row level security;

drop policy if exists commerce_checkout_holds_select_own on public.commerce_checkout_holds;
create policy commerce_checkout_holds_select_own
  on public.commerce_checkout_holds
  for select to authenticated
  using (buyer_id = auth.uid());

comment on table public.commerce_checkout_holds is
  'Phase 4 technical payment hold. Not a commercial reservation. covers_guaranteed=true → no extra stock debit.';

-- -----------------------------------------------------------------------------
-- C) Quote helpers (server money authority)
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_shipping_cents(p_method text)
returns integer
language plpgsql
immutable
as $$
declare
  m text := lower(trim(coalesce(p_method, '')));
begin
  if m = '' then
    raise exception 'invalid_shipping_method' using errcode = '22023';
  end if;
  if m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)'
  ) or m like '%mão%' or m like '%mao%' then
    if m like '%transportadora%' or m like '%3.50%' or m like '%3,50%' then
      return 350;
    end if;
    return 0;
  end if;
  if m in (
    'carrier', 'transportadora', 'ctt', 'correios',
    'envio transportadora (€3.50)', 'envio transportadora (€3,50)'
  ) or m like '%transportadora%' or m like '%carrier%' then
    return 350;
  end if;
  raise exception 'invalid_shipping_method' using errcode = '22023';
end;
$$;

create or replace function public.batata_commerce_protection_fee_cents(
  p_items_cents integer,
  p_shipping_cents integer
)
returns integer
language sql
immutable
as $$
  select greatest(
    0,
    round(65 + 0.05 * (greatest(coalesce(p_items_cents, 0), 0)
                       + greatest(coalesce(p_shipping_cents, 0), 0)))::int
  );
$$;

revoke all on function public.batata_commerce_shipping_cents(text) from public;
grant execute on function public.batata_commerce_shipping_cents(text)
  to authenticated, service_role;
revoke all on function public.batata_commerce_protection_fee_cents(integer, integer) from public;
grant execute on function public.batata_commerce_protection_fee_cents(integer, integer)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- D) held_qty — include active technical holds; avoid double-count with guaranteed
-- -----------------------------------------------------------------------------
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
  v_raffle int := 0;
  v_tech int := 0;
  v_pending_ttl interval := interval '90 minutes';
begin
  if p_product_id is null then
    return 0;
  end if;

  -- Orders: reserva_pendente with checkout_attempt_id does NOT double-count —
  -- technical hold (or guaranteed cover) is the stock authority for Phase 4 attempts.
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
    and (
      public.batata_order_status_holds_product_qty(o.status)
      or lower(trim(coalesce(o.status, ''))) = 'premio_rifa'
    )
    and (
      lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'premio_rifa'
      )
      or (
        lower(trim(coalesce(o.status, ''))) in ('reserva_pendente', 'pendente')
        and o.created_at > (timezone('utc', now()) - v_pending_ttl)
        and o.checkout_attempt_id is null
      )
    );

  -- Accepted LRR blocks stock. Phase4: covers_guaranteed holds do NOT add a second
  -- debit; reserva_pendente with checkout_attempt_id is excluded above.
  select coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
    into v_live
  from public.live_reservation_requests r
  join public.live_items li on li.id = r.live_item_id
  where r.status = 'accepted'
    and coalesce(li.product_id, li.checkout_product_id) = p_product_id
    and not exists (
      -- After successful convert / paid order for same buyer+item, stop double-count
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
        and (
          o.live_item_id = r.live_item_id
          or o.product_id = p_product_id
        )
    );

  select coalesce(count(*)::int, 0)
    into v_raffle
  from public.live_raffle_winners w
  join public.live_raffles rf on rf.id = w.raffle_id
  join public.live_items li on li.id = rf.live_item_id
  where coalesce(li.product_id, li.checkout_product_id) = p_product_id
    and lower(trim(coalesce(rf.status, ''))) = 'drawn'
    and not exists (
      select 1 from public.orders o
      where o.live_raffle_id = rf.id
        and o.buyer_id = w.user_id
        and lower(trim(coalesce(o.status, ''))) in (
          'premio_rifa', 'pago', 'enviado', 'entregue', 'concluido',
          'aguarda_pagamento', 'aguarda_confirmacao', 'reservado'
        )
    );

  -- Technical holds that actually debit stock (not covers_guaranteed)
  select coalesce(sum(h.quantity), 0)::int
    into v_tech
  from public.commerce_checkout_holds h
  where h.product_id = p_product_id
    and h.status = 'active'
    and h.covers_guaranteed = false
    and h.expires_at > timezone('utc', now());

  return v_held + v_live + v_raffle + v_tech;
end;
$$;

comment on function public.batata_product_held_qty(uuid, uuid, uuid[]) is
  'Phase4: orders holds + accepted LRR + raffle + active technical holds; no double debit for guaranteed+attempt.';

notify pgrst, 'reload schema';
