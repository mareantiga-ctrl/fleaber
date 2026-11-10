-- ZIP 169-C1: ops health snapshot table + hourly tick via edge (pg_net).
-- Does NOT enable commercial crons (DPD tracking / B2C release / Stripe LIVE).

create table if not exists public.ops_health_snapshots (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  status text not null check (status in ('ok','warn','critical')),
  payload jsonb not null default '{}'::jsonb
);

create index if not exists ops_health_snapshots_created_at_idx
  on public.ops_health_snapshots (created_at desc);

alter table public.ops_health_snapshots enable row level security;

revoke all on table public.ops_health_snapshots from public, anon, authenticated;
grant select, insert on table public.ops_health_snapshots to service_role;
grant usage, select on sequence public.ops_health_snapshots_id_seq to service_role;

comment on table public.ops_health_snapshots is
  'ZIP169: snapshots ops-health (sem PII). Só service_role.';

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create or replace function public.batata_invoke_ops_health()
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_secret text;
  v_request_id bigint;
  v_url text := 'https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/ops-health';
begin
  select decrypted_secret
  into v_secret
  from vault.decrypted_secrets
  where name = 'ops_health_secret'
  limit 1;

  if v_secret is null or v_secret = '' then
    raise warning 'batata_invoke_ops_health: vault secret ops_health_secret em falta';
    return null;
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-ops-health-secret', v_secret
    ),
    body := '{}'::jsonb
  )
  into v_request_id;

  return v_request_id;
end;
$fn$;

revoke all on function public.batata_invoke_ops_health() from public, anon, authenticated;
grant execute on function public.batata_invoke_ops_health() to service_role;

do $u$
begin
  perform cron.unschedule('batata-ops-health');
exception when others then null;
end;
$u$;

-- A cada hora, minuto 15 (offset vs LiveKit :00) — evita pico simultâneo.
select cron.schedule(
  'batata-ops-health',
  '15 * * * *',
  $$ select public.batata_invoke_ops_health(); $$
);
