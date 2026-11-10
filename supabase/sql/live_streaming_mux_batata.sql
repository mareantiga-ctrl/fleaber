-- Fleaber BATATA: Mux LL-HLS live streaming.
-- Executar no SQL Editor do Supabase antes de usar a Edge Function create-mux-live.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.lives (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text,
  status text not null default 'scheduled',
  seller_id uuid,
  vendedor_id uuid,
  mux_live_id text,
  mux_stream_key text,
  stream_key text,
  mux_playback_id text,
  playback_id text,
  is_active boolean not null default false
);

alter table public.lives
  add column if not exists title text,
  add column if not exists status text not null default 'scheduled',
  add column if not exists seller_id uuid,
  add column if not exists vendedor_id uuid,
  add column if not exists mux_live_id text,
  add column if not exists mux_stream_key text,
  add column if not exists stream_key text,
  add column if not exists mux_playback_id text,
  add column if not exists playback_id text,
  add column if not exists is_active boolean not null default false;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.lives'::regclass
      and conname = 'lives_status_check'
  ) then
    alter table public.lives drop constraint lives_status_check;
  end if;
end;
$$;

alter table public.lives
  add constraint lives_status_check
  check (status in ('scheduled', 'live', 'ended', 'error'));

create index if not exists lives_status_created_idx
  on public.lives (status, created_at desc);

create index if not exists lives_seller_idx
  on public.lives (seller_id);

alter table public.lives enable row level security;

drop policy if exists "lives_select_public_live" on public.lives;
create policy "lives_select_public_live"
  on public.lives
  for select
  using (status = 'live' or is_active = true or auth.uid() = seller_id or auth.uid() = vendedor_id);

drop policy if exists "lives_insert_own" on public.lives;
create policy "lives_insert_own"
  on public.lives
  for insert
  with check (auth.uid() = seller_id or auth.uid() = vendedor_id);

drop policy if exists "lives_update_own" on public.lives;
create policy "lives_update_own"
  on public.lives
  for update
  using (auth.uid() = seller_id or auth.uid() = vendedor_id)
  with check (auth.uid() = seller_id or auth.uid() = vendedor_id);
