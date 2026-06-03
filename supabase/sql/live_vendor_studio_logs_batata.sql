-- Fleaber: logs estruturados do painel vendedor/helper em directo (LiveVendorStudioPanel).
-- Executar no SQL Editor ou: npx supabase db query --linked -f supabase/sql/live_vendor_studio_logs_batata.sql

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.live_vendor_studio_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  live_id uuid,
  seller_id uuid,
  actor_id uuid,
  live_item_id uuid,
  request_id uuid,
  event text not null,
  status text not null default 'ok',
  detail jsonb,
  error_message text
);

create index if not exists live_vendor_studio_logs_live_created_idx
  on public.live_vendor_studio_logs (live_id, created_at desc);

create index if not exists live_vendor_studio_logs_event_created_idx
  on public.live_vendor_studio_logs (event, created_at desc);

create index if not exists live_vendor_studio_logs_seller_created_idx
  on public.live_vendor_studio_logs (seller_id, created_at desc);

alter table public.live_vendor_studio_logs enable row level security;

grant usage on schema public to authenticated, service_role;
grant insert on table public.live_vendor_studio_logs to authenticated;
grant select on table public.live_vendor_studio_logs to authenticated, service_role;

drop policy if exists "live_vendor_studio_logs_insert" on public.live_vendor_studio_logs;
create policy "live_vendor_studio_logs_insert"
  on public.live_vendor_studio_logs
  for insert
  to authenticated
  with check (actor_id is null or actor_id = auth.uid());

drop policy if exists "live_vendor_studio_logs_select" on public.live_vendor_studio_logs;
create policy "live_vendor_studio_logs_select"
  on public.live_vendor_studio_logs
  for select
  to authenticated
  using (
    seller_id = auth.uid()
    or public.batata_is_admin()
    or exists (
      select 1
      from public.seller_helpers sh
      where sh.seller_id = live_vendor_studio_logs.seller_id
        and sh.helper_user_id = auth.uid()
        and sh.active = true
        and coalesce(sh.invitation_status, '') = 'accepted'
    )
  );

-- Consulta rápida após testes:
-- select created_at, event, status, live_id, live_item_id, request_id, detail, error_message
-- from public.live_vendor_studio_logs
-- order by created_at desc
-- limit 50;
