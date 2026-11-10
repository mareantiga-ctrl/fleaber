-- Fleaber BATATA: Live Director Platform — scripts, runs, timeline, audit.
-- Executar no SQL Editor (staging primeiro). Isolado: não afecta lives sem director_run_id.
-- Ver também: live_director_raffle_sim_batata.sql (exclusão sim no draw).

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- profiles: marca contas sim (bots director)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists sim_account_kind text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_sim_account_kind_chk'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_sim_account_kind_chk
      check (
        sim_account_kind is null
        or sim_account_kind in ('director_bot', 'director_seller')
      );
  end if;
end $$;

create or replace function public.batata_is_sim_account(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user_id
      and p.sim_account_kind is not null
  );
$$;

revoke all on function public.batata_is_sim_account(uuid) from public;
grant execute on function public.batata_is_sim_account(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- lives: ligação opcional a run director
-- ---------------------------------------------------------------------------
alter table public.lives
  add column if not exists director_run_id uuid,
  add column if not exists director_sim_mode text,
  add column if not exists director_live_started_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'lives_director_sim_mode_chk'
      and conrelid = 'public.lives'::regclass
  ) then
    alter table public.lives
      add constraint lives_director_sim_mode_chk
      check (
        director_sim_mode is null
        or director_sim_mode in ('qa', 'demo', 'production_controlled')
      );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- live_director_scripts
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_scripts (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null,
  version int not null default 1,
  description text,
  mode text not null default 'demo'
    check (mode in ('qa', 'demo', 'production_controlled')),
  live_id uuid references public.lives (id) on delete set null,
  seller_id uuid references public.profiles (id) on delete set null,
  operator_id uuid references public.profiles (id) on delete set null,
  operator_label text,
  target_products jsonb not null default '[]'::jsonb,
  cast_pool jsonb not null default '[]'::jsonb,
  beats jsonb not null default '[]'::jsonb,
  policy jsonb not null default '{}'::jsonb,
  checksum text,
  status text not null default 'draft'
    check (status in ('draft', 'validated', 'archived')),
  parent_script_id uuid references public.live_director_scripts (id) on delete set null,
  tags text[] not null default '{}'
);

create index if not exists live_director_scripts_seller_idx
  on public.live_director_scripts (seller_id, updated_at desc);

create index if not exists live_director_scripts_live_idx
  on public.live_director_scripts (live_id);

-- ---------------------------------------------------------------------------
-- live_director_runs
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  script_id uuid not null references public.live_director_scripts (id) on delete restrict,
  script_checksum text not null,
  manifest jsonb not null,
  live_id uuid not null references public.lives (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  operator_id uuid references public.profiles (id) on delete set null,
  mode text not null check (mode in ('qa', 'demo', 'production_controlled')),
  status text not null default 'pending'
    check (status in (
      'pending', 'preflight_ok', 'running', 'paused', 'killed',
      'completed', 'failed'
    )),
  kill_reason text,
  live_started_at timestamptz,
  timeline_sealed boolean not null default false,
  stats jsonb not null default '{}'::jsonb,
  report jsonb
);

create index if not exists live_director_runs_live_status_idx
  on public.live_director_runs (live_id, status);

-- ---------------------------------------------------------------------------
-- live_director_timeline_events (replay)
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_timeline_events (
  id bigserial primary key,
  run_id uuid not null references public.live_director_runs (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  manifest_id uuid not null,
  live_offset_ms bigint not null default 0,
  occurred_at timestamptz not null default now(),
  kind text not null,
  origin text not null default 'system'
    check (origin in ('human', 'sim', 'seller', 'system')),
  actor_id uuid references public.profiles (id) on delete set null,
  beat_id text,
  payload jsonb not null default '{}'::jsonb,
  replay_visible boolean not null default true,
  ref_table text,
  ref_id uuid
);

create index if not exists live_director_timeline_live_offset_idx
  on public.live_director_timeline_events (live_id, live_offset_ms);

create index if not exists live_director_timeline_run_idx
  on public.live_director_timeline_events (run_id, id);

-- ---------------------------------------------------------------------------
-- live_director_audit_log
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_audit_log (
  id bigserial primary key,
  run_id uuid not null references public.live_director_runs (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  beat_id text,
  seq bigint not null default 0,
  occurred_at timestamptz not null default now(),
  live_offset_ms bigint,
  event_type text not null,
  actor_id uuid,
  product_id uuid,
  outcome text not null
    check (outcome in (
      'planned', 'executed', 'blocked', 'skipped', 'delayed',
      'manual_override', 'kill', 'payment_guard', 'raffle_guard', 'stock_guard'
    )),
  reason text,
  payload jsonb not null default '{}'::jsonb
);

create index if not exists live_director_audit_run_seq_idx
  on public.live_director_audit_log (run_id, seq);

-- ---------------------------------------------------------------------------
-- live_director_kill_switch
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_kill_switch (
  id uuid primary key default extensions.gen_random_uuid(),
  scope text not null check (scope in ('global', 'environment', 'live', 'run')),
  scope_key text not null default '',
  is_active boolean not null default false,
  activated_at timestamptz,
  activated_by uuid references public.profiles (id) on delete set null,
  reason text,
  unique (scope, scope_key)
);

-- ---------------------------------------------------------------------------
-- live_director_sim_profiles
-- ---------------------------------------------------------------------------
create table if not exists public.live_director_sim_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  internal_tag text not null unique,
  display_name text not null,
  persona text not null default 'observer'
    check (persona in ('curious', 'buyer', 'observer', 'fan', 'negotiator')),
  environment text not null default 'staging'
    check (environment in ('qa', 'demo', 'staging')),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists live_director_sim_profiles_profile_idx
  on public.live_director_sim_profiles (profile_id);

-- ---------------------------------------------------------------------------
-- RLS — admin only (batata_is_admin)
-- ---------------------------------------------------------------------------
alter table public.live_director_scripts enable row level security;
alter table public.live_director_runs enable row level security;
alter table public.live_director_timeline_events enable row level security;
alter table public.live_director_audit_log enable row level security;
alter table public.live_director_kill_switch enable row level security;
alter table public.live_director_sim_profiles enable row level security;

drop policy if exists live_director_scripts_admin on public.live_director_scripts;
create policy live_director_scripts_admin on public.live_director_scripts
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists live_director_runs_admin on public.live_director_runs;
create policy live_director_runs_admin on public.live_director_runs
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists live_director_timeline_admin on public.live_director_timeline_events;
create policy live_director_timeline_admin on public.live_director_timeline_events
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists live_director_audit_admin on public.live_director_audit_log;
create policy live_director_audit_log_admin on public.live_director_audit_log
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists live_director_kill_admin on public.live_director_kill_switch;
create policy live_director_kill_admin on public.live_director_kill_switch
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists live_director_sim_profiles_admin on public.live_director_sim_profiles;
create policy live_director_sim_profiles_admin on public.live_director_sim_profiles
  for all using (public.batata_is_admin())
  with check (public.batata_is_admin());

-- Timeline replay: leitura pública para lives ended (gravado) — só eventos replay_visible
drop policy if exists live_director_timeline_replay_read on public.live_director_timeline_events;
create policy live_director_timeline_replay_read on public.live_director_timeline_events
  for select using (
    replay_visible = true
    and exists (
      select 1 from public.lives l
      where l.id = live_id and l.status = 'ended'
    )
  );

-- ---------------------------------------------------------------------------
-- RPC: kill switch ping (pre-flight)
-- ---------------------------------------------------------------------------
create or replace function public.batata_director_kill_switch_active(
  p_scope text,
  p_scope_key text default ''
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.live_director_kill_switch k
    where k.is_active = true
      and (
        (k.scope = 'global' and k.scope_key = '')
        or (k.scope = p_scope and k.scope_key = coalesce(p_scope_key, ''))
      )
  );
$$;

revoke all on function public.batata_director_kill_switch_active(text, text) from public;
grant execute on function public.batata_director_kill_switch_active(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: activar kill switch
-- ---------------------------------------------------------------------------
create or replace function public.batata_director_activate_kill_switch(
  p_scope text,
  p_scope_key text default '',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_is_admin() then
    raise exception 'admin_required';
  end if;

  insert into public.live_director_kill_switch (
    scope, scope_key, is_active, activated_at, activated_by, reason
  ) values (
    p_scope, coalesce(p_scope_key, ''), true, now(), auth.uid(), p_reason
  )
  on conflict (scope, scope_key) do update
  set is_active = true,
      activated_at = now(),
      activated_by = auth.uid(),
      reason = coalesce(p_reason, live_director_kill_switch.reason);

  return jsonb_build_object('ok', true, 'scope', p_scope, 'scope_key', p_scope_key);
end;
$$;

revoke all on function public.batata_director_activate_kill_switch(text, text, text) from public;
grant execute on function public.batata_director_activate_kill_switch(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: desactivar kill switch
-- ---------------------------------------------------------------------------
create or replace function public.batata_director_deactivate_kill_switch(
  p_scope text,
  p_scope_key text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_is_admin() then
    raise exception 'admin_required';
  end if;

  update public.live_director_kill_switch
  set is_active = false
  where scope = p_scope and scope_key = coalesce(p_scope_key, '');

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_director_deactivate_kill_switch(text, text) from public;
grant execute on function public.batata_director_deactivate_kill_switch(text, text, text) to authenticated;
