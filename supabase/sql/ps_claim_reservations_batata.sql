-- Liga reservas PS/Facebook (buyer_id NULL) ao utilizador autenticado pelo nome FB.
-- Correr em staging antes do teste Hub.

create or replace function public.batata_claim_external_reservations(
  p_live_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fb_name text;
  v_claimed int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select coalesce(
    nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(u.raw_user_meta_data->>'name'), ''),
    nullif(trim(p.full_name), '')
  )
  into v_fb_name
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = v_uid;

  if v_fb_name is null or length(trim(v_fb_name)) < 2 then
    return jsonb_build_object('ok', false, 'error', 'no_display_name');
  end if;

  update public.live_reservation_requests r
  set
    buyer_id = v_uid,
    updated_at = now()
  where r.buyer_id is null
    and r.source = 'facebook_manual'
    and r.external_display_name is not null
    and lower(trim(r.external_display_name)) = lower(trim(v_fb_name))
    and (p_live_id is null or r.live_id = p_live_id);

  get diagnostics v_claimed = row_count;

  return jsonb_build_object(
    'ok', true,
    'claimed', v_claimed,
    'display_name', v_fb_name
  );
end;
$$;

revoke all on function public.batata_claim_external_reservations(uuid) from public;
grant execute on function public.batata_claim_external_reservations(uuid) to authenticated;
