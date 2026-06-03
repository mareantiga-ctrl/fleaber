-- Fleaber: logs centralizados da app (erros + passos do pipeline live).
-- Executar no SQL Editor do Supabase (projeto fxdknzrqjenzqcvnwqqq).

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.app_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  device_info jsonb,
  error_message text not null,
  stack_trace text,
  category text not null
);

create index if not exists app_logs_created_at_idx
  on public.app_logs (created_at desc);

create index if not exists app_logs_category_idx
  on public.app_logs (category, created_at desc);

alter table public.app_logs enable row level security;

-- Permissões explícitas (sem isto o insert via anon key falha em silêncio).
grant usage on schema public to anon, authenticated, service_role;
grant insert on table public.app_logs to anon, authenticated;
grant select on table public.app_logs to authenticated, service_role;

drop policy if exists "app_logs_insert_anon" on public.app_logs;
create policy "app_logs_insert_anon"
  on public.app_logs
  for insert
  to anon
  with check (true);

drop policy if exists "app_logs_insert_authenticated" on public.app_logs;
create policy "app_logs_insert_authenticated"
  on public.app_logs
  for insert
  to authenticated
  with check (true);

-- Leitura: admins (requer admin_batata.sql) ou service_role no painel Supabase.
drop policy if exists "app_logs_insert_all" on public.app_logs;
drop policy if exists "app_logs_select_admin" on public.app_logs;

create policy "app_logs_select_admin"
  on public.app_logs
  for select
  to authenticated
  using (public.batata_is_admin());

-- Ping de teste após deploy:
-- select * from public.app_logs order by created_at desc limit 20;
