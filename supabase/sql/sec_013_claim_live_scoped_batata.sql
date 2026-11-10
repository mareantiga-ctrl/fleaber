-- SEC-013 parcial (cuidado extremo / BATATA)
-- NÃO muda o matching por nome FB (one-tap Hub mantém-se).
-- Só: exige live_id (a app já envia sempre) + rate-limit 20/h/user.
-- Residual: nome igual ainda pode claimar nessa live — prova FB fica para lote futuro.

create table if not exists public.batata_rpc_rate_limits (
  uid uuid not null,
  rpc text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (uid, rpc, window_start)
);

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
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- App HubPsClaim.claimForLive sempre passa live_id — bloquear claim global.
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_id_required');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_claim_external_reservations', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 20 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
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

  -- Mesma lógica de matching de sempre (BATATA) — só no live pedido.
  update public.live_reservation_requests r
  set
    buyer_id = v_uid,
    updated_at = now()
  where r.buyer_id is null
    and r.source = 'facebook_manual'
    and r.external_display_name is not null
    and lower(trim(r.external_display_name)) = lower(trim(v_fb_name))
    and r.live_id = p_live_id;

  get diagnostics v_claimed = row_count;

  return jsonb_build_object(
    'ok', true,
    'claimed', v_claimed,
    'display_name', v_fb_name
  );
end;
$$;

revoke all on function public.batata_claim_external_reservations(uuid)
  from public, anon;
grant execute on function public.batata_claim_external_reservations(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
