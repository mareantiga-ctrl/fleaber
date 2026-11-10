-- Fleaber PS — journal do painel (extensão / Reader) para auditoria sem prints.
-- Depende de: live_cross_channel_ingest_batata.sql (batata_validate_seller_device_token)

create table if not exists public.ps_panel_events (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  device_id text,
  event_kind text not null default 'info',
  message text not null,
  detail text,
  meta jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ps_panel_events_live_idx
  on public.ps_panel_events (live_id, created_at asc);

create index if not exists ps_panel_events_seller_idx
  on public.ps_panel_events (seller_id, created_at desc);

alter table public.ps_panel_events enable row level security;

drop policy if exists ps_panel_events_seller_select on public.ps_panel_events;
create policy ps_panel_events_seller_select
  on public.ps_panel_events
  for select
  to authenticated
  using (seller_id = auth.uid());

-- Inserção via edge function (service_role).
create or replace function public.batata_ps_panel_log(
  p_device_token text,
  p_live_id uuid,
  p_device_id text default null,
  p_event_kind text default 'info',
  p_message text default '',
  p_detail text default null,
  p_meta jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
  v_live public.lives%rowtype;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if coalesce(v_live.seller_id, v_live.vendedor_id) is distinct from v_seller_id then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if trim(coalesce(p_message, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_message');
  end if;

  insert into public.ps_panel_events (
    seller_id, live_id, device_id, event_kind, message, detail, meta
  ) values (
    v_seller_id,
    p_live_id,
    nullif(trim(coalesce(p_device_id, '')), ''),
    coalesce(nullif(trim(p_event_kind), ''), 'info'),
    trim(p_message),
    nullif(trim(coalesce(p_detail, '')), ''),
    p_meta
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_ps_panel_log(
  text, uuid, text, text, text, text, jsonb
) from public;
grant execute on function public.batata_ps_panel_log(
  text, uuid, text, text, text, text, jsonb
) to service_role;
