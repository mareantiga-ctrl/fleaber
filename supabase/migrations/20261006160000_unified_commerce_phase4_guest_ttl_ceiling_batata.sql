-- =============================================================================
-- BATATA 2026-10-06 — Phase 4 final evidence: guest TTL ceiling + idem race
-- PRODUCTION CHANGED = NO (staging apply only)
-- =============================================================================

-- Guest bearer credential: clamp TTL server-side (min 15m, max 24h).
-- Client-requested TTL is never trusted beyond these bounds.
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
  v_req int := coalesce(p_ttl_seconds, 86400);
  -- SERVER-SIDE BOUNDS (do not trust client):
  v_ttl_min int := 900;      -- 15 minutes
  v_ttl_max int := 86400;    -- 24 hours
  v_ttl int;
  v_exp timestamptz;
begin
  v_ttl := least(greatest(v_req, v_ttl_min), v_ttl_max);
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_exp := timezone('utc', now()) + make_interval(secs => v_ttl);

  insert into public.commerce_guest_sessions (id, token_hash, expires_at)
  values (v_id, v_hash, v_exp);

  return jsonb_build_object(
    'ok', true,
    'guest_session_id', v_id,
    'guest_token', v_token,
    'expires_at', v_exp,
    'ttl_seconds_applied', v_ttl,
    'ttl_seconds_requested', v_req,
    'ttl_min_seconds', v_ttl_min,
    'ttl_max_seconds', v_ttl_max
  );
end;
$$;

revoke all on function public.batata_commerce_guest_session_create(integer) from public;
grant execute on function public.batata_commerce_guest_session_create(integer)
  to anon, authenticated, service_role;

-- Explicit revoke for lifecycle tests / ops (service_role)
create or replace function public.batata_commerce_guest_session_revoke(
  p_guest_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  update public.commerce_guest_sessions
  set revoked_at = timezone('utc', now())
  where id = p_guest_session_id
    and revoked_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found_or_already_revoked');
  end if;
  return jsonb_build_object('ok', true, 'guest_session_id', p_guest_session_id);
end;
$$;

revoke all on function public.batata_commerce_guest_session_revoke(uuid) from public;
grant execute on function public.batata_commerce_guest_session_revoke(uuid)
  to service_role;

notify pgrst, 'reload schema';
