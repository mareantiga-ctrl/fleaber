-- Permite resolver handle com hub_published=false (acesso live/gravado na descoberta).
-- Vitrine completa (perfil/loja/opiniões) continua a exigir hub_published na app.

create or replace function public.batata_resolve_handle(p_handle text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_in text := public.batata_normalize_handle(p_handle);
  v_profile_id uuid;
  v_handle text;
  v_published boolean;
  v_redirect text;
begin
  if v_in = '' then
    return jsonb_build_object(
      'found', false,
      'error', 'not_found',
      'http_status', 404
    );
  end if;

  select p.id, p.handle, p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where p.handle = v_in
  limit 1;

  if v_profile_id is not null and v_published is true then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', true,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  -- Handle claimado mas vitrine ainda não publicada — OK para /live (descoberta).
  if v_profile_id is not null then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', false,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  -- Slug de descoberta (ex. full_name "Joao84" → joao84 sem handle claimado).
  select
    p.id,
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name),
    p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name) = v_in
  limit 1;

  if v_profile_id is not null then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', coalesce(v_published, false),
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  select r.new_handle into v_redirect
  from public.profile_handle_redirects r
  where r.old_handle = v_in
    and (r.redirect_until is null or r.redirect_until > now())
  limit 1;

  if v_redirect is not null then
    return jsonb_build_object(
      'found', true,
      'profile_id', (
        select p.id from public.profiles p where p.handle = v_redirect limit 1
      ),
      'handle', v_redirect,
      'redirect_to', v_redirect,
      'hub_published', (
        select p.hub_published from public.profiles p where p.handle = v_redirect limit 1
      ),
      'http_status', 301
    );
  end if;

  return jsonb_build_object(
    'found', false,
    'error', 'not_found',
    'http_status', 404
  );
end;
$$;

notify pgrst, 'reload schema';
