-- =============================================================================
-- BATATA — AUDIT 1442 T1651 residual P2 S7-01 (pairing TTL / live activa)
-- P0/P1 do freeze 1442: já fechados (T1651 LIVE confirma).
-- production_touched: false · fase4: false
-- =============================================================================

-- Código de emparelhamento: janela curta (2 min) + 1 código aberto por live.
-- Helper com can_manage_reservations continua a poder criar (produto) —
-- o P2 era janela longa + código roubável; não é "tirar permissão ao staff".

create or replace function public.batata_ps_create_pairing(
  p_live_id uuid,
  p_device_id_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_code text;
  v_token text;
  v_hash text;
  v_device text := coalesce(nullif(trim(p_device_id_hint), ''), 'ps-reader-pc');
  v_attempt int := 0;
  v_is_helper boolean := false;
  v_ttl interval := interval '2 minutes';
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  v_seller_id := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_seller_id is distinct from v_uid
     and not public.batata_staff_has_permission(v_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_is_helper := v_seller_id is distinct from v_uid;

  -- Helper: só com live activa (evita pair órfão pós-live)
  if v_is_helper and coalesce(v_live.is_active, false) is not true
     and lower(trim(coalesce(v_live.status, ''))) not in ('live', 'active', 'ao_vivo') then
    return jsonb_build_object('ok', false, 'error', 'live_not_active');
  end if;

  -- Invalida códigos abertos da mesma live (1 código vivo de cada vez)
  update public.ps_pairing_sessions
  set expires_at = least(expires_at, now() - interval '1 second')
  where live_id = p_live_id
    and claimed_at is null
    and expires_at > now();

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.ps_pairing_sessions s
      where s.code = v_code and s.claimed_at is null and s.expires_at > now()
    );
    exit when v_attempt > 20;
  end loop;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (
    seller_id, device_id, token_hash, label, created_by
  ) values (
    v_seller_id,
    v_device,
    v_hash,
    'PS Reader ' || to_char(now(), 'YYYY-MM-DD HH24:MI'),
    v_uid
  )
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    created_by = excluded.created_by,
    revoked_at = null,
    created_at = now();

  insert into public.ps_pairing_sessions (
    seller_id, live_id, code, device_token_plain, device_id_hint, expires_at
  ) values (
    v_seller_id,
    p_live_id,
    v_code,
    v_token,
    v_device,
    now() + v_ttl
  );

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expires_at', (now() + v_ttl),
    'ttl_seconds', 120,
    'live_id', p_live_id,
    'live_title', coalesce(v_live.title, 'Live'),
    'device_id', v_device,
    'created_by_helper', v_is_helper
  );
end;
$$;

revoke all on function public.batata_ps_create_pairing(uuid, text) from public, anon;
grant execute on function public.batata_ps_create_pairing(uuid, text)
  to authenticated, service_role;

comment on function public.batata_ps_create_pairing(uuid, text) is
  'T1651-P2 S7-01: TTL 2min; 1 código/live; helper só live activa; kick ainda revoga tokens.';

-- Claim: rate limit mais apertado (40 → 12 / hora / device)
create or replace function public.batata_ps_claim_pairing(
  p_code text,
  p_device_id text,
  p_app_version text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ps_pairing_sessions%rowtype;
  v_ctx jsonb;
  v_device text := coalesce(nullif(trim(coalesce(p_device_id, '')), ''), 'ps-reader-pc');
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_rate_key text := 'ps_claim:' || lower(v_device);
begin
  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 12 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
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

revoke all on function public.batata_ps_claim_pairing(text, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_ps_claim_pairing(text, text, text)
  to service_role;

notify pgrst, 'reload schema';
