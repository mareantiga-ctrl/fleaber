-- =============================================================================
-- BATATA 2026-10-06 — Phase 4 FINAL CORRECTION
-- Guest checkout foundation (additive). Same Unified Commerce lifecycle.
-- STRIPE = implemented. IFTHENPAY = rail reserved, integration pending.
-- production_touched: false
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) Guest sessions — server-issued secret (hash stored; token shown once)
-- -----------------------------------------------------------------------------
create table if not exists public.commerce_guest_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz null
);

create unique index if not exists uq_commerce_guest_sessions_token_hash
  on public.commerce_guest_sessions (token_hash);

create index if not exists idx_commerce_guest_sessions_expires
  on public.commerce_guest_sessions (expires_at)
  where revoked_at is null;

revoke all on table public.commerce_guest_sessions from public, anon, authenticated;
grant all on table public.commerce_guest_sessions to service_role;

alter table public.commerce_guest_sessions enable row level security;
-- No direct client SELECT of hashes. RPCs only.

comment on table public.commerce_guest_sessions is
  'Phase4 guest identity. Client holds opaque token once; server stores sha256 only.';

-- -----------------------------------------------------------------------------
-- B) Attempts / holds — nullable buyer_id + XOR guest identity
-- -----------------------------------------------------------------------------
alter table public.commerce_checkout_attempts
  alter column buyer_id drop not null;

alter table public.commerce_checkout_attempts
  drop constraint if exists commerce_checkout_attempts_identity_chk;

alter table public.commerce_checkout_attempts
  add constraint commerce_checkout_attempts_identity_chk
  check (
    (buyer_id is not null and guest_session_id is null)
    or (buyer_id is null and guest_session_id is not null)
  );

-- Multi-provider readiness: reserve ifthenpay rail (no PSP client yet)
alter table public.commerce_checkout_attempts
  drop constraint if exists commerce_checkout_attempts_payment_rail_check;

alter table public.commerce_checkout_attempts
  add constraint commerce_checkout_attempts_payment_rail_check
  check (payment_rail in ('stripe', 'off_platform', 'ifthenpay'));

drop index if exists uq_commerce_checkout_attempts_buyer_idem;
create unique index uq_commerce_checkout_attempts_buyer_idem
  on public.commerce_checkout_attempts (buyer_id, client_idempotency_key)
  where client_idempotency_key is not null and buyer_id is not null;

create unique index if not exists uq_commerce_checkout_attempts_guest_idem
  on public.commerce_checkout_attempts (guest_session_id, client_idempotency_key)
  where client_idempotency_key is not null and guest_session_id is not null;

create index if not exists idx_commerce_checkout_attempts_guest
  on public.commerce_checkout_attempts (guest_session_id)
  where guest_session_id is not null;

alter table public.commerce_checkout_holds
  alter column buyer_id drop not null;

alter table public.commerce_checkout_holds
  add column if not exists guest_session_id uuid null;

alter table public.commerce_checkout_holds
  drop constraint if exists commerce_checkout_holds_identity_chk;

alter table public.commerce_checkout_holds
  add constraint commerce_checkout_holds_identity_chk
  check (
    (buyer_id is not null and guest_session_id is null)
    or (buyer_id is null and guest_session_id is not null)
  );

-- FK guest session (nullable)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'commerce_checkout_attempts_guest_fk'
  ) then
    alter table public.commerce_checkout_attempts
      add constraint commerce_checkout_attempts_guest_fk
      foreign key (guest_session_id) references public.commerce_guest_sessions (id);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'commerce_checkout_holds_guest_fk'
  ) then
    alter table public.commerce_checkout_holds
      add constraint commerce_checkout_holds_guest_fk
      foreign key (guest_session_id) references public.commerce_guest_sessions (id);
  end if;
end $$;

-- RLS: authenticated own buyer attempts; guests never read via PostgREST policies
drop policy if exists commerce_checkout_attempts_select_own on public.commerce_checkout_attempts;
create policy commerce_checkout_attempts_select_own
  on public.commerce_checkout_attempts
  for select to authenticated
  using (buyer_id is not null and buyer_id = auth.uid());

drop policy if exists commerce_checkout_holds_select_own on public.commerce_checkout_holds;
create policy commerce_checkout_holds_select_own
  on public.commerce_checkout_holds
  for select to authenticated
  using (buyer_id is not null and buyer_id = auth.uid());

-- -----------------------------------------------------------------------------
-- C) Guest session create + resolve
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_guest_session_create(
  p_ttl_seconds integer default 86400
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := gen_random_uuid();
  v_token text;
  v_hash text;
  v_ttl int := greatest(coalesce(p_ttl_seconds, 86400), 900);
  v_exp timestamptz;
begin
  -- 32-byte opaque token (hex). Shown once; only hash stored.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_exp := timezone('utc', now()) + make_interval(secs => v_ttl);

  insert into public.commerce_guest_sessions (id, token_hash, expires_at)
  values (v_id, v_hash, v_exp);

  return jsonb_build_object(
    'ok', true,
    'guest_session_id', v_id,
    'guest_token', v_token,
    'expires_at', v_exp
  );
end;
$$;

revoke all on function public.batata_commerce_guest_session_create(integer) from public;
grant execute on function public.batata_commerce_guest_session_create(integer)
  to anon, authenticated, service_role;

create or replace function public.batata_commerce_guest_session_resolve(
  p_guest_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tok text := trim(coalesce(p_guest_token, ''));
  v_hash text;
  v_row public.commerce_guest_sessions%rowtype;
begin
  if length(v_tok) < 32 then
    return jsonb_build_object('ok', false, 'error', 'invalid_guest_token');
  end if;
  v_hash := encode(extensions.digest(v_tok, 'sha256'), 'hex');
  select * into v_row
  from public.commerce_guest_sessions
  where token_hash = v_hash
  for update;
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'guest_not_found');
  end if;
  if v_row.revoked_at is not null then
    return jsonb_build_object('ok', false, 'error', 'guest_revoked');
  end if;
  if v_row.expires_at <= timezone('utc', now()) then
    return jsonb_build_object('ok', false, 'error', 'guest_expired');
  end if;
  update public.commerce_guest_sessions
  set last_seen_at = timezone('utc', now())
  where id = v_row.id;
  return jsonb_build_object(
    'ok', true,
    'guest_session_id', v_row.id,
    'expires_at', v_row.expires_at
  );
end;
$$;

revoke all on function public.batata_commerce_guest_session_resolve(text) from public;
grant execute on function public.batata_commerce_guest_session_resolve(text)
  to anon, authenticated, service_role;

-- Actor resolver: authenticated XOR guest token
create or replace function public.batata_commerce_resolve_checkout_actor(
  p_guest_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_guest jsonb;
  v_gs uuid;
begin
  if v_uid is not null and v_role = 'authenticated' then
    if coalesce(trim(p_guest_token), '') <> '' then
      return jsonb_build_object('ok', false, 'error', 'authenticated_cannot_use_guest_token');
    end if;
    return jsonb_build_object(
      'ok', true,
      'mode', 'authenticated',
      'buyer_id', v_uid,
      'guest_session_id', null
    );
  end if;

  if coalesce(trim(p_guest_token), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'identity_required');
  end if;

  v_guest := public.batata_commerce_guest_session_resolve(p_guest_token);
  if coalesce((v_guest->>'ok')::boolean, false) is not true then
    return v_guest;
  end if;
  v_gs := (v_guest->>'guest_session_id')::uuid;
  return jsonb_build_object(
    'ok', true,
    'mode', 'guest',
    'buyer_id', null,
    'guest_session_id', v_gs
  );
end;
$$;

revoke all on function public.batata_commerce_resolve_checkout_actor(text) from public;
grant execute on function public.batata_commerce_resolve_checkout_actor(text)
  to anon, authenticated, service_role;

-- Authorize attempt access (buyer JWT or matching guest token)
create or replace function public.batata_commerce_actor_owns_attempt(
  p_attempt public.commerce_checkout_attempts,
  p_guest_token text default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_actor jsonb;
begin
  if coalesce(auth.role(), '') = 'service_role' then
    return true;
  end if;
  v_actor := public.batata_commerce_resolve_checkout_actor(p_guest_token);
  if coalesce((v_actor->>'ok')::boolean, false) is not true then
    return false;
  end if;
  if v_actor->>'mode' = 'authenticated' then
    return p_attempt.buyer_id is not null
      and p_attempt.buyer_id = (v_actor->>'buyer_id')::uuid;
  end if;
  return p_attempt.guest_session_id is not null
    and p_attempt.guest_session_id = (v_actor->>'guest_session_id')::uuid;
end;
$$;

revoke all on function public.batata_commerce_actor_owns_attempt(public.commerce_checkout_attempts, text)
  from public;
grant execute on function public.batata_commerce_actor_owns_attempt(public.commerce_checkout_attempts, text)
  to anon, authenticated, service_role;

notify pgrst, 'reload schema';
