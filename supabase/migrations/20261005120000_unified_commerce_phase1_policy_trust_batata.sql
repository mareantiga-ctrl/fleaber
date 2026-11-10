-- =============================================================================
-- BATATA 2026-10-05 — Unified commerce Fase 1: política + confiança (fundação)
-- Staging only intended. Additive. No DROP of real data. No UI. No PSP/Meta/PS.
-- Docs: 09-unified-commerce-reservations-architecture (19, 05, 17, 26, 30, 20)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) seller_reservation_settings — 1 linha por seller; nasce só quando configura
-- -----------------------------------------------------------------------------
create table if not exists public.seller_reservation_settings (
  seller_id uuid primary key references auth.users (id) on delete cascade,
  policy_mode text not null
    check (policy_mode in ('manual', 'auto', 'trust', 'pay_only')),
  untrusted_mode text not null
    check (untrusted_mode in ('approval', 'pay_required')),
  normal_ttl_seconds integer not null
    check (normal_ttl_seconds >= 900 and normal_ttl_seconds <= 432000),
  trusted_ttl_seconds integer not null
    check (trusted_ttl_seconds >= 900 and trusted_ttl_seconds <= 432000),
  accept_fleaber_global_trust boolean not null default true,
  policy_version integer not null default 1,
  configured_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.seller_reservation_settings is
  'Política única de reservas por seller (Live+Market+Facebook). Sem row = não configurada (D1).';

create or replace function public.batata_touch_seller_reservation_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := timezone('utc', now());
  if tg_op = 'UPDATE' then
    new.policy_version := coalesce(old.policy_version, 0) + 1;
    new.seller_id := old.seller_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_batata_seller_reservation_settings_touch
  on public.seller_reservation_settings;
create trigger trg_batata_seller_reservation_settings_touch
before update on public.seller_reservation_settings
for each row execute function public.batata_touch_seller_reservation_settings();

alter table public.seller_reservation_settings enable row level security;

drop policy if exists seller_reservation_settings_select_own
  on public.seller_reservation_settings;
create policy seller_reservation_settings_select_own
  on public.seller_reservation_settings
  for select to authenticated
  using (seller_id = auth.uid());

drop policy if exists seller_reservation_settings_insert_own
  on public.seller_reservation_settings;
create policy seller_reservation_settings_insert_own
  on public.seller_reservation_settings
  for insert to authenticated
  with check (seller_id = auth.uid());

drop policy if exists seller_reservation_settings_update_own
  on public.seller_reservation_settings;
create policy seller_reservation_settings_update_own
  on public.seller_reservation_settings
  for update to authenticated
  using (seller_id = auth.uid())
  with check (seller_id = auth.uid());

-- Sem DELETE policy para authenticated (evita apagar config por engano via client).
revoke all on table public.seller_reservation_settings from anon;
grant select, insert, update on table public.seller_reservation_settings to authenticated;
grant all on table public.seller_reservation_settings to service_role;

-- -----------------------------------------------------------------------------
-- B) seller_buyer_trust — só override manual (não cria linha por buyer nova)
-- -----------------------------------------------------------------------------
create table if not exists public.seller_buyer_trust (
  seller_id uuid not null references auth.users (id) on delete cascade,
  buyer_id uuid not null references auth.users (id) on delete cascade,
  mode text not null check (mode in ('trusted', 'distrusted')),
  source text not null default 'manual'
    check (source in ('manual')),
  updated_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (seller_id, buyer_id),
  check (seller_id <> buyer_id)
);

comment on table public.seller_buyer_trust is
  'Override manual por seller. Ausência de linha + global trusted = confiança (D24). Sem external_buyer_ref.';

create index if not exists idx_seller_buyer_trust_buyer
  on public.seller_buyer_trust (buyer_id);

alter table public.seller_buyer_trust enable row level security;

drop policy if exists seller_buyer_trust_seller_select
  on public.seller_buyer_trust;
create policy seller_buyer_trust_seller_select
  on public.seller_buyer_trust
  for select to authenticated
  using (seller_id = auth.uid() or buyer_id = auth.uid());

-- Escrita só via RPC security definer (sem insert/update/delete directos do client)
revoke all on table public.seller_buyer_trust from anon;
revoke insert, update, delete on table public.seller_buyer_trust from authenticated;
grant select on table public.seller_buyer_trust to authenticated;
grant all on table public.seller_buyer_trust to service_role;

create or replace function public.batata_seller_buyer_trust_set(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_mode text := lower(trim(coalesce(p_mode, '')));
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_seller_id is null or p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_ids');
  end if;
  if v_uid is distinct from p_seller_id then
    return jsonb_build_object('ok', false, 'error', 'seller_only');
  end if;
  if p_seller_id = p_buyer_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_pair');
  end if;
  if v_mode not in ('trusted', 'distrusted', 'clear') then
    return jsonb_build_object('ok', false, 'error', 'invalid_mode');
  end if;

  if v_mode = 'clear' then
    delete from public.seller_buyer_trust
    where seller_id = p_seller_id and buyer_id = p_buyer_id;
    return jsonb_build_object('ok', true, 'mode', 'auto');
  end if;

  insert into public.seller_buyer_trust (seller_id, buyer_id, mode, source, updated_at)
  values (p_seller_id, p_buyer_id, v_mode, 'manual', timezone('utc', now()))
  on conflict (seller_id, buyer_id) do update
    set mode = excluded.mode,
        source = 'manual',
        updated_at = timezone('utc', now());

  return jsonb_build_object('ok', true, 'mode', v_mode);
end;
$$;

revoke all on function public.batata_seller_buyer_trust_set(uuid, uuid, text) from public;
grant execute on function public.batata_seller_buyer_trust_set(uuid, uuid, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- C) buyer_trust_events + buyer_trust_state (Decisão 25 foundation)
-- -----------------------------------------------------------------------------
create table if not exists public.buyer_trust_events (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in (
    'fulfillment',
    'failure',
    'loss',
    'recovery_progress',
    'recovered',
    'fulfillment_revoked'
  )),
  source_type text not null check (source_type in (
    'checkout_attempt',
    'stripe_checkout_session',
    'stripe_payment_intent',
    'order',
    'live_reservation_request',
    'system'
  )),
  source_id text not null,
  failure_reason text
    check (
      failure_reason is null
      or failure_reason in (
        'guaranteed_hold_expired_unpaid',
        'buyer_abandonment'
      )
    ),
  meta jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz
);

comment on table public.buyer_trust_events is
  'Ledger auditável confiança global. Cumprimentos/falhas tipadas. Sem client writes.';

-- Dedup fulfillment / failure / revoke by natural key
create unique index if not exists uq_buyer_trust_events_fulfillment
  on public.buyer_trust_events (kind, source_type, source_id)
  where kind in ('fulfillment', 'failure', 'fulfillment_revoked');

create index if not exists idx_buyer_trust_events_buyer_occurred
  on public.buyer_trust_events (buyer_id, occurred_at desc);

create index if not exists idx_buyer_trust_events_buyer_kind
  on public.buyer_trust_events (buyer_id, kind, occurred_at desc);

create table if not exists public.buyer_trust_state (
  buyer_id uuid primary key references auth.users (id) on delete cascade,
  global_status text not null check (global_status in ('trusted', 'lost')),
  recovery_count integer not null default 0
    check (recovery_count >= 0 and recovery_count <= 3),
  lost_at timestamptz,
  recovered_at timestamptz,
  fulfillment_count integer not null default 0,
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.buyer_trust_state is
  'Materialização do ledger. Ausência de row = trusted por defeito (D24).';

alter table public.buyer_trust_events enable row level security;
alter table public.buyer_trust_state enable row level security;

drop policy if exists buyer_trust_events_select_own on public.buyer_trust_events;
create policy buyer_trust_events_select_own
  on public.buyer_trust_events
  for select to authenticated
  using (buyer_id = auth.uid());

drop policy if exists buyer_trust_state_select_own on public.buyer_trust_state;
create policy buyer_trust_state_select_own
  on public.buyer_trust_state
  for select to authenticated
  using (buyer_id = auth.uid());

revoke all on table public.buyer_trust_events from anon, authenticated;
revoke all on table public.buyer_trust_state from anon, authenticated;
grant select on table public.buyer_trust_events to authenticated;
grant select on table public.buyer_trust_state to authenticated;
grant all on table public.buyer_trust_events to service_role;
grant all on table public.buyer_trust_state to service_role;

-- -----------------------------------------------------------------------------
-- D) Trust evaluate + recompute (security definer)
-- -----------------------------------------------------------------------------
create or replace function public.batata_buyer_global_trust_status(p_buyer_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if p_buyer_id is null then
    return 'identity_insufficient';
  end if;
  select global_status into v_status
  from public.buyer_trust_state
  where buyer_id = p_buyer_id;
  if v_status is null then
    return 'trusted'; -- D24: sem row = benefício da dúvida
  end if;
  return v_status;
end;
$$;

create or replace function public.batata_buyer_trust_decision(
  p_seller_id uuid,
  p_buyer_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_override text;
  v_global text;
  v_benefit boolean := false;
  v_decision text;
begin
  if p_buyer_id is null then
    return jsonb_build_object(
      'ok', true,
      'decision', 'IDENTITY_INSUFFICIENT',
      'has_benefit', false,
      'global_status', null,
      'seller_override', null
    );
  end if;

  select sbt.mode into v_override
  from public.seller_buyer_trust sbt
  where sbt.seller_id = p_seller_id
    and sbt.buyer_id = p_buyer_id;

  v_global := public.batata_buyer_global_trust_status(p_buyer_id);

  if v_override = 'distrusted' then
    v_decision := 'SELLER_DISTRUST';
    v_benefit := false;
  elsif v_override = 'trusted' then
    v_decision := 'SELLER_TRUST';
    v_benefit := true;
  elsif v_global = 'lost' then
    v_decision := 'GLOBAL_LOST';
    v_benefit := false;
  else
    v_decision := 'TRUSTED_DEFAULT';
    v_benefit := true;
  end if;

  return jsonb_build_object(
    'ok', true,
    'decision', v_decision,
    'has_benefit', v_benefit,
    'global_status', v_global,
    'seller_override', v_override
  );
end;
$$;

revoke all on function public.batata_buyer_global_trust_status(uuid) from public;
revoke all on function public.batata_buyer_trust_decision(uuid, uuid) from public;
grant execute on function public.batata_buyer_global_trust_status(uuid)
  to authenticated, service_role;
grant execute on function public.batata_buyer_trust_decision(uuid, uuid)
  to authenticated, service_role;

-- NOTE: body replaced by 20261005120300_unified_commerce_phase1_trust_recompute_fix_batata.sql
-- Keep stub create so fresh applies still define the function before the fix migration.
create or replace function public.batata_buyer_trust_recompute(p_buyer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Placeholder overwritten by subsequent fix migration in same Phase 1 pack.
  return jsonb_build_object('ok', false, 'error', 'recompute_placeholder');
end;
$$;

create or replace function public.batata_buyer_trust_record_fulfillment(
  p_buyer_id uuid,
  p_source_type text,
  p_source_id text,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_inserted boolean := false;
begin
  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
    -- allow service_role / postgres; block authenticated client forge
    if auth.uid() is not null then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;
  if p_buyer_id is null or coalesce(trim(p_source_id), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if p_source_type not in (
    'checkout_attempt', 'stripe_checkout_session', 'stripe_payment_intent', 'order'
  ) then
    return jsonb_build_object('ok', false, 'error', 'invalid_source_type');
  end if;

  begin
    insert into public.buyer_trust_events (
      buyer_id, kind, source_type, source_id, meta, occurred_at
    ) values (
      p_buyer_id, 'fulfillment', p_source_type, trim(p_source_id),
      coalesce(p_meta, '{}'::jsonb), timezone('utc', now())
    );
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  return public.batata_buyer_trust_recompute(p_buyer_id)
    || jsonb_build_object('inserted', v_inserted);
end;
$$;

create or replace function public.batata_buyer_trust_record_failure(
  p_buyer_id uuid,
  p_source_type text,
  p_source_id text,
  p_failure_reason text,
  p_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_inserted boolean := false;
  v_reason text := lower(trim(coalesce(p_failure_reason, '')));
begin
  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
    if auth.uid() is not null then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;
  if p_buyer_id is null or coalesce(trim(p_source_id), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  -- Only buyer-abandonment style failures affect reputation
  if v_reason not in ('guaranteed_hold_expired_unpaid', 'buyer_abandonment') then
    return jsonb_build_object(
      'ok', true,
      'inserted', false,
      'skipped', true,
      'reason', 'non_reputational_failure'
    );
  end if;
  if p_source_type not in ('order', 'live_reservation_request') then
    return jsonb_build_object('ok', false, 'error', 'invalid_source_type');
  end if;

  begin
    insert into public.buyer_trust_events (
      buyer_id, kind, source_type, source_id, failure_reason, meta, occurred_at
    ) values (
      p_buyer_id, 'failure', p_source_type, trim(p_source_id), v_reason,
      coalesce(p_meta, '{}'::jsonb), timezone('utc', now())
    );
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  return public.batata_buyer_trust_recompute(p_buyer_id)
    || jsonb_build_object('inserted', v_inserted);
end;
$$;

revoke all on function public.batata_buyer_trust_recompute(uuid) from public;
revoke all on function public.batata_buyer_trust_record_fulfillment(uuid, text, text, jsonb) from public;
revoke all on function public.batata_buyer_trust_record_failure(uuid, text, text, text, jsonb) from public;

-- Recompute readable for service; record_* only service_role (no authenticated forge)
grant execute on function public.batata_buyer_trust_recompute(uuid) to service_role;
grant execute on function public.batata_buyer_trust_record_fulfillment(uuid, text, text, jsonb)
  to service_role;
grant execute on function public.batata_buyer_trust_record_failure(uuid, text, text, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';
