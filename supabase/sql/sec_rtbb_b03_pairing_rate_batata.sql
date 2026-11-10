-- RTBB-B-03 (staging BATATA)
-- Bug de controlo: rate-limit do claim pairing chaveado só por device_id do body.
-- Atacante rodava device_id e contornava 40/h.
-- Fecho: IP (passado pela Edge) + tecto global de projecto + device (defesa em profundidade).
-- NÃO alongar código 6 dígitos (quebrava PS reader) — residual de produto documentado.
-- production_touched: false · fase4: false

create or replace function public.batata_ps_claim_pairing(
  p_code text,
  p_device_id text,
  p_app_version text default null,
  p_client_ip text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ps_pairing_sessions%rowtype;
  v_ctx jsonb;
  v_device text := coalesce(nullif(trim(coalesce(p_device_id, '')), ''), 'ps-reader-pc');
  v_ip text := left(lower(trim(coalesce(p_client_ip, ''))), 64);
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_rate_key text;
begin
  -- 1) Tecto global do projecto (não rodável pelo cliente) — 200/h
  v_rate_key := 'ps_claim:global';
  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > 200 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'scope', 'global');
  end if;

  -- 2) Por IP (quando a Edge envia) — 40/h; rodár device_id não ajuda
  if v_ip <> '' and v_ip not in ('unknown', 'null', 'undefined') then
    v_rate_key := 'ps_claim:ip:' || v_ip;
    insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
    values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
    on conflict (rate_key, rpc, window_start) do update
    set hits = public.batata_anon_rate_limits.hits + 1
    returning hits into v_hits;
    if v_hits > 40 then
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'scope', 'ip');
    end if;
  end if;

  -- 3) Por device (defesa em profundidade) — 40/h
  v_rate_key := 'ps_claim:dev:' || lower(left(v_device, 120));
  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > 40 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'scope', 'device');
  end if;

  select * into v_row
  from public.ps_pairing_sessions s
  where s.code = trim(coalesce(p_code, ''))
    and s.claimed_at is null
    and s.expires_at > now()
  for update skip locked
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_or_expired_code');
  end if;

  update public.ps_pairing_sessions
  set
    claimed_at = now(),
    claimed_device_id = nullif(trim(coalesce(p_device_id, '')), '')
  where id = v_row.id;

  v_ctx := public.batata_ps_live_context(v_row.live_id);

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, paired_at, last_seen_at
  ) values (
    v_row.seller_id,
    v_row.live_id,
    coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint, 'ps-reader-pc'),
    'paired',
    nullif(trim(coalesce(p_app_version, '')), ''),
    now(),
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = excluded.live_id,
    status = 'paired',
    app_version = excluded.app_version,
    paired_at = now(),
    last_seen_at = now();

  return jsonb_build_object(
    'ok', true,
    'live_id', v_row.live_id,
    'device_token', v_row.device_token_plain,
    'device_id', coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint),
    'seller_id', v_row.seller_id,
    'live_context', v_ctx
  );
end;
$$;

revoke all on function public.batata_ps_claim_pairing(text, text, text, text) from public, anon, authenticated;
grant execute on function public.batata_ps_claim_pairing(text, text, text, text) to service_role;

-- Remover overload de 3 args (só device) para não haver bypass sem IP.
drop function if exists public.batata_ps_claim_pairing(text, text, text);

comment on function public.batata_ps_claim_pairing(text, text, text, text) is
  'RTBB-B-03: claim pairing rate-limit global + IP + device (service_role / Edge only).';

notify pgrst, 'reload schema';
