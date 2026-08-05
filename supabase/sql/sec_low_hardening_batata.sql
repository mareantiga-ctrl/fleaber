-- SEC low-hardening (risco de regressão Baixo) — Ago 2026
-- Fecha: SEC-012 (email→UUID), SEC-022 (app_logs anon), SEC-023 (studio logs spoof)
-- Executar no SQL Editor do Supabase (staging primeiro).
-- BATATA: não toca pagamentos, lives Mux, admin user_type, nem orders.

-- =============================================================================
-- SEC-012 — batata_find_user_id_by_email: auth obrigatório + rate limit
-- Mantém GRANT authenticated (convites helper na app).
-- =============================================================================

create table if not exists public.batata_rpc_rate_limits (
  uid uuid not null,
  rpc text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (uid, rpc, window_start)
);

create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_found uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    return null;
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_find_user_id_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  -- 30 lookups / hora / utilizador — chega para convites; bloqueia enumeração em massa
  if v_hits > 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id
  into v_found
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  return v_found;
end;
$$;

revoke all on function public.batata_find_user_id_by_email(text) from public;
grant execute on function public.batata_find_user_id_by_email(text) to authenticated;
grant execute on function public.batata_find_user_id_by_email(text) to service_role;

alter table public.batata_rpc_rate_limits enable row level security;
-- Sem policies para authenticated: só SECURITY DEFINER escreve.

-- =============================================================================
-- SEC-022 — app_logs: sem INSERT anon
-- =============================================================================

drop policy if exists "app_logs_insert_anon" on public.app_logs;
revoke insert on table public.app_logs from anon;

drop policy if exists "app_logs_insert_authenticated" on public.app_logs;
create policy "app_logs_insert_authenticated"
  on public.app_logs
  for insert
  to authenticated
  with check (true);

grant insert on table public.app_logs to authenticated;

-- =============================================================================
-- SEC-023 — live_vendor_studio_logs: não spoofar seller_id alheio
-- =============================================================================

drop policy if exists "live_vendor_studio_logs_insert" on public.live_vendor_studio_logs;
create policy "live_vendor_studio_logs_insert"
  on public.live_vendor_studio_logs
  for insert
  to authenticated
  with check (
    actor_id = auth.uid()
    and (
      seller_id is null
      or seller_id = auth.uid()
      or exists (
        select 1
        from public.seller_helpers sh
        where sh.seller_id = live_vendor_studio_logs.seller_id
          and sh.helper_user_id = auth.uid()
          and sh.active = true
          and coalesce(sh.invitation_status, '') = 'accepted'
      )
    )
  );

notify pgrst, 'reload schema';
