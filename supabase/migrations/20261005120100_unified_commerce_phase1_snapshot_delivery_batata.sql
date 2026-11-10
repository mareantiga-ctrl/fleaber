-- =============================================================================
-- BATATA 2026-10-05 — Unified commerce Fase 1: LRR snapshot + orders delivery
-- Additive columns. Backfill request_kind=approval_pending. No reinterpret as C.2.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) live_reservation_requests — snapshot / kind / expiry / extend
-- -----------------------------------------------------------------------------
alter table public.live_reservation_requests
  add column if not exists request_kind text;

alter table public.live_reservation_requests
  add column if not exists policy_mode_snapshot text;

alter table public.live_reservation_requests
  add column if not exists untrusted_mode_snapshot text;

alter table public.live_reservation_requests
  add column if not exists trust_decision_snapshot text;

alter table public.live_reservation_requests
  add column if not exists ttl_seconds_snapshot integer;

alter table public.live_reservation_requests
  add column if not exists policy_version_snapshot integer;

alter table public.live_reservation_requests
  add column if not exists extended_once boolean not null default false;

alter table public.live_reservation_requests
  add column if not exists expiry_reason text;

alter table public.live_reservation_requests
  add column if not exists unavailable_at timestamptz;

alter table public.live_reservation_requests
  add column if not exists trust_promoted_at timestamptz;

alter table public.live_reservation_requests
  add column if not exists guest_session_id uuid;

-- live_id nullable for future Marketplace rows in same table (Phase 3). Keep FK.
alter table public.live_reservation_requests
  alter column live_id drop not null;

-- Backfill ONLY current behaviour — never invent C.2
update public.live_reservation_requests
set request_kind = 'approval_pending'
where request_kind is null;

alter table public.live_reservation_requests
  alter column request_kind set default 'approval_pending';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_request_kind_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_request_kind_chk
      check (request_kind in ('approval_pending', 'bag_hold_none', 'guaranteed'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_policy_mode_snapshot_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_policy_mode_snapshot_chk
      check (
        policy_mode_snapshot is null
        or policy_mode_snapshot in ('manual', 'auto', 'trust', 'pay_only')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_untrusted_mode_snapshot_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_untrusted_mode_snapshot_chk
      check (
        untrusted_mode_snapshot is null
        or untrusted_mode_snapshot in ('approval', 'pay_required')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_trust_decision_snapshot_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_trust_decision_snapshot_chk
      check (
        trust_decision_snapshot is null
        or trust_decision_snapshot in (
          'IDENTITY_INSUFFICIENT',
          'TRUSTED_DEFAULT',
          'SELLER_TRUST',
          'SELLER_DISTRUST',
          'GLOBAL_LOST'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_ttl_seconds_snapshot_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_ttl_seconds_snapshot_chk
      check (
        ttl_seconds_snapshot is null
        or (ttl_seconds_snapshot >= 900 and ttl_seconds_snapshot <= 432000)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_expiry_reason_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_expiry_reason_chk
      check (
        expiry_reason is null
        or expiry_reason in (
          'pending_ttl_expired',
          'guaranteed_hold_expired_unpaid',
          'buyer_abandonment',
          'stock_unavailable',
          'seller_cancelled',
          'buyer_cancelled',
          'system_error',
          'payment_processing',
          'payment_provider_technical_failure',
          'superseded_by_policy',
          'identity_insufficient_closed'
        )
      );
  end if;
end $$;

create index if not exists idx_lrr_guest_session
  on public.live_reservation_requests (guest_session_id)
  where guest_session_id is not null;

create index if not exists idx_lrr_request_kind_status
  on public.live_reservation_requests (request_kind, status);

comment on column public.live_reservation_requests.request_kind is
  'approval_pending=C.1 pedido; bag_hold_none=C.2 saco sem hold; guaranteed=nasceu aceite';
comment on column public.live_reservation_requests.expiry_reason is
  'Motivo tipado de fecho. pending_ttl ≠ falha de confiança.';
comment on column public.live_reservation_requests.guest_session_id is
  'Sessão convidada futura. Sem trust até claim com buyer_id.';

-- Queue: bag_hold_none should not receive queue_position (foundation trigger tweak)
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max integer;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  -- C.2 bag lines: no approval queue
  if coalesce(new.request_kind, 'approval_pending') = 'bag_hold_none' then
    new.queue_position := null;
    if new.expires_at is null then
      -- bag cleanup TTL left to product; do not force 45m approval semantics
      new.expires_at := null;
    end if;
    return new;
  end if;

  if new.queue_position is null and new.live_item_id is not null then
    select coalesce(max(r.queue_position), 0)
      into v_max
    from public.live_reservation_requests r
    where r.live_item_id = new.live_item_id
      and r.status = 'pending'
      and coalesce(r.request_kind, 'approval_pending') = 'approval_pending';
    new.queue_position := v_max + 1;
  end if;

  if new.expires_at is null then
    new.expires_at := timezone('utc', now()) + interval '45 minutes';
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- B) orders — checkout attempt, guest, delivery snapshot, typed cancel reason
-- -----------------------------------------------------------------------------
alter table public.orders
  add column if not exists checkout_attempt_id uuid;

alter table public.orders
  add column if not exists guest_session_id uuid;

alter table public.orders
  add column if not exists expiry_reason text;

alter table public.orders
  add column if not exists delivery_recipient_name text;

alter table public.orders
  add column if not exists delivery_line1 text;

alter table public.orders
  add column if not exists delivery_line2 text;

alter table public.orders
  add column if not exists delivery_postal_code text;

alter table public.orders
  add column if not exists delivery_city text;

alter table public.orders
  add column if not exists delivery_country text;

alter table public.orders
  add column if not exists delivery_phone text;

alter table public.orders
  add column if not exists delivery_point_ref text;

alter table public.orders
  add column if not exists delivery_point_provider text;

alter table public.orders
  add column if not exists delivery_point_label text;

alter table public.orders
  add column if not exists delivery_snapshot_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_expiry_reason_chk'
  ) then
    alter table public.orders
      add constraint orders_expiry_reason_chk
      check (
        expiry_reason is null
        or expiry_reason in (
          'pending_ttl_expired',
          'guaranteed_hold_expired_unpaid',
          'buyer_abandonment',
          'stock_unavailable',
          'seller_cancelled',
          'buyer_cancelled',
          'system_error',
          'payment_processing',
          'payment_provider_technical_failure'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'orders_delivery_point_provider_chk'
  ) then
    alter table public.orders
      add constraint orders_delivery_point_provider_chk
      check (
        delivery_point_provider is null
        or delivery_point_provider in ('dpd_pickup', 'dpd_locker', 'other', 'home')
      );
  end if;
end $$;

create index if not exists idx_orders_checkout_attempt
  on public.orders (checkout_attempt_id)
  where checkout_attempt_id is not null;

create index if not exists idx_orders_guest_session
  on public.orders (guest_session_id)
  where guest_session_id is not null;

comment on column public.orders.checkout_attempt_id is
  'Uma chave partilhada pelas linhas do mesmo pagamento → 1 cumprimento (D25).';
comment on column public.orders.guest_session_id is
  'Guest checkout futuro. buyer_id pode ser null; claim posterior liga conta.';
comment on column public.orders.delivery_line1 is
  'Snapshot imutável da morada usada nesta encomenda (não lê perfil dinamicamente).';
comment on column public.orders.delivery_point_ref is
  'Referência futura Pickup/Locker. Sem integração DPD nesta fase.';

-- Freeze delivery snapshot after payment (same spirit as shipping_method freeze)
create or replace function public.batata_orders_freeze_delivery_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- Once snapshot stamped, block client/profile drift from rewriting logistics
  if old.delivery_snapshot_at is not null then
    if new.delivery_recipient_name is distinct from old.delivery_recipient_name
      or new.delivery_line1 is distinct from old.delivery_line1
      or new.delivery_line2 is distinct from old.delivery_line2
      or new.delivery_postal_code is distinct from old.delivery_postal_code
      or new.delivery_city is distinct from old.delivery_city
      or new.delivery_country is distinct from old.delivery_country
      or new.delivery_phone is distinct from old.delivery_phone
      or new.delivery_point_ref is distinct from old.delivery_point_ref
      or new.delivery_point_provider is distinct from old.delivery_point_provider
      or new.delivery_point_label is distinct from old.delivery_point_label
      or new.delivery_snapshot_at is distinct from old.delivery_snapshot_at
    then
      if public.batata_order_status_is_sold_fulfilled(old.status)
         or lower(trim(coalesce(old.status, ''))) in (
           'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa'
         )
         or coalesce(old.stock_units_applied, 0) > 0
         or old.amount_paid_cents is not null
      then
        raise exception 'order_delivery_snapshot_frozen' using errcode = '42501';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_batata_orders_freeze_delivery_snapshot on public.orders;
create trigger trg_batata_orders_freeze_delivery_snapshot
before update on public.orders
for each row execute function public.batata_orders_freeze_delivery_snapshot();

notify pgrst, 'reload schema';
