-- Claim Face: Hub poll esgotava 20/h → saco vazio. Sobe teto para 180/h.

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
  v_fb_provider_id text;
  v_fb_name text;
  v_claimed_fb int := 0;
  v_claimed_map int := 0;
  v_claimed_legacy int := 0;
  v_orphans_fb int := 0;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_id_required');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_claim_external_reservations', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  -- Antes: 20/h (Hub 15s + saco 5s esgotava em minutos).
  if v_hits > 180 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  select nullif(trim(i.provider_id), '')
  into v_fb_provider_id
  from auth.identities i
  where i.user_id = v_uid
    and i.provider = 'facebook'
  order by i.updated_at desc nulls last
  limit 1;

  if v_fb_provider_id is null then
    select coalesce(
      nullif(trim(i.identity_data->>'id'), ''),
      nullif(trim(i.identity_data->>'user_id'), ''),
      nullif(trim(i.identity_data->>'sub'), '')
    )
    into v_fb_provider_id
    from auth.identities i
    where i.user_id = v_uid
      and i.provider = 'facebook'
    order by i.updated_at desc nulls last
    limit 1;
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

  if v_fb_provider_id is not null and length(v_fb_provider_id) >= 5 then
    update public.live_reservation_requests r
    set
      buyer_id = v_uid,
      updated_at = now()
    where r.buyer_id is null
      and r.source = 'facebook_manual'
      and r.live_id = p_live_id
      and r.external_buyer_ref = ('fb:' || v_fb_provider_id);

    get diagnostics v_claimed_fb = row_count;

    update public.live_reservation_requests r
    set
      buyer_id = v_uid,
      updated_at = now()
    where r.buyer_id is null
      and r.source = 'facebook_manual'
      and r.live_id = p_live_id
      and r.external_buyer_ref like 'fb:%'
      and exists (
        select 1
        from public.batata_facebook_id_map m
        where m.user_id = v_uid
          and m.oauth_provider_id = v_fb_provider_id
          and r.external_buyer_ref = ('fb:' || m.comment_fb_id)
      );

    get diagnostics v_claimed_map = row_count;
  end if;

  if v_fb_name is not null and length(trim(v_fb_name)) >= 2 then
    update public.live_reservation_requests r
    set
      buyer_id = v_uid,
      updated_at = now()
    where r.buyer_id is null
      and r.source = 'facebook_manual'
      and r.live_id = p_live_id
      and r.external_display_name is not null
      and lower(trim(r.external_display_name)) = lower(trim(v_fb_name))
      and r.external_buyer_ref like 'sess:%';

    get diagnostics v_claimed_legacy = row_count;
  end if;

  select count(*)::int
  into v_orphans_fb
  from public.live_reservation_requests r
  where r.buyer_id is null
    and r.source = 'facebook_manual'
    and r.live_id = p_live_id
    and (
      r.external_buyer_ref like 'fb:%'
      or r.external_buyer_ref like 'fb:u:%'
    );

  if (v_claimed_fb + v_claimed_map + v_claimed_legacy) = 0
     and v_fb_provider_id is null
     and v_orphans_fb > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'facebook_login_required',
      'claimed', 0,
      'claimed_fb', 0,
      'claimed_map', 0,
      'claimed_legacy', 0,
      'orphans_fb', v_orphans_fb,
      'has_facebook_identity', false,
      'hint', 'Inicia sessão com Facebook na conta Fleaber para reclamar reservas fb:{id}.'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'claimed', v_claimed_fb + v_claimed_map + v_claimed_legacy,
    'claimed_fb', v_claimed_fb,
    'claimed_map', v_claimed_map,
    'claimed_legacy', v_claimed_legacy,
    'display_name', v_fb_name,
    'facebook_provider_id', v_fb_provider_id,
    'has_facebook_identity', v_fb_provider_id is not null,
    'orphans_fb_remaining', greatest(0, v_orphans_fb - v_claimed_fb - v_claimed_map)
  );
end;
$$;

revoke all on function public.batata_claim_external_reservations(uuid)
  from public, anon;
grant execute on function public.batata_claim_external_reservations(uuid)
  to authenticated, service_role;
