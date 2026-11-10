-- Staging only: reset / restore FleaHub state for UX screenshot «Criar FleaHub».
-- Aplicar uma vez em staging (service_role). Não usar em produção.
create or replace function public.batata_staging_set_fleahub_test_state(
  p_profile_id uuid,
  p_handle text default null,
  p_hub_published boolean default false,
  p_handle_suggested text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null then
    return jsonb_build_object('ok', false, 'error', 'profile_required');
  end if;

  perform set_config('batata.handle_rpc', '1', true);

  update public.profiles p
  set
    handle = nullif(btrim(coalesce(p_handle, '')), ''),
    hub_published = coalesce(p_hub_published, false),
    handle_suggested = coalesce(
      nullif(btrim(coalesce(p_handle_suggested, '')), ''),
      p.handle_suggested
    )
  where p.id = p_profile_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'profile_id', p_profile_id,
    'handle', (select handle from public.profiles where id = p_profile_id),
    'hub_published', (select hub_published from public.profiles where id = p_profile_id),
    'handle_suggested', (select handle_suggested from public.profiles where id = p_profile_id)
  );
end;
$$;

revoke all on function public.batata_staging_set_fleahub_test_state(uuid, text, boolean, text) from public;
grant execute on function public.batata_staging_set_fleahub_test_state(uuid, text, boolean, text) to service_role;
