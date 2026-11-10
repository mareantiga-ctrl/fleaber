-- =============================================================================
-- E74 — Guest session resolve: grants + FOR UPDATE seguro para anon
-- Causa E73: resolve só tinha EXECUTE para service_role (anon → 401).
-- create/revoke já concedidos na E73; resolve ficou inconsistente.
-- =============================================================================

create or replace function public.batata_commerce_guest_session_resolve(
  p_guest_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tok text := trim(coalesce(p_guest_token, ''));
  v_hash text;
  v_row public.commerce_guest_sessions%rowtype;
begin
  -- SECURITY DEFINER: bypass RLS for hash lookup
  perform set_config('row_security', 'off', true);

  if length(v_tok) < 32 then
    return jsonb_build_object('ok', false, 'error', 'invalid_guest_token');
  end if;
  v_hash := encode(extensions.digest(v_tok, 'sha256'), 'hex');

  select * into v_row
  from public.commerce_guest_sessions
  where token_hash = v_hash
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'guest_not_found');
  end if;
  if v_row.revoked_at is not null then
    return jsonb_build_object('ok', false, 'error', 'guest_revoked');
  end if;
  if v_row.expires_at <= timezone('utc', now()) then
    return jsonb_build_object('ok', false, 'error', 'guest_expired');
  end if;

  update public.commerce_guest_sessions
  set last_seen_at = timezone('utc', now())
  where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'guest_session_id', v_row.id,
    'expires_at', v_row.expires_at
  );
end;
$$;

revoke all on function public.batata_commerce_guest_session_resolve(text) from public;
grant execute on function public.batata_commerce_guest_session_resolve(text)
  to anon, authenticated, service_role;

-- Reafirmar create/revoke grants (idempotente)
do $$
begin
  if to_regprocedure('public.batata_commerce_guest_session_create(integer)') is not null then
    revoke all on function public.batata_commerce_guest_session_create(integer) from public;
    grant execute on function public.batata_commerce_guest_session_create(integer)
      to anon, authenticated, service_role;
  end if;
  if to_regprocedure('public.batata_commerce_guest_session_revoke(text)') is not null then
    revoke all on function public.batata_commerce_guest_session_revoke(text) from public;
    grant execute on function public.batata_commerce_guest_session_revoke(text)
      to anon, authenticated, service_role;
  end if;
end $$;

notify pgrst, 'reload schema';
