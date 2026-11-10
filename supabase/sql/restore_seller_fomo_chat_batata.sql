-- =============================================================================
-- BATATA 2026-09-13 — FOMO chat só seller/staff (produto planeado)
-- Hardening continua a bloquear compradores/atacantes a forjar 🔥/🛒.
-- =============================================================================

create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_stem text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_allowed boolean := false;
  v_is_ops boolean := false;
  v_participant boolean := false;
  v_seller_fomo boolean := false;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;
  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;
  if v_uid is null and v_role is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller from public.lives where id = p_live_id;
  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_role = 'service_role' then
    v_is_ops := true;
  else
    v_is_ops := v_uid = v_seller
      or public.batata_staff_has_permission(v_seller, 'can_manage_chat');
  end if;

  v_norm := lower(normalize(v_body, NFKC));
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff\u2800-\u28ff\u00ad\u2060]', '', 'g');
  v_norm := regexp_replace(v_norm, '[0-9]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüçоОаАсСſօოäöüßѕ'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucoaassoaoousss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  v_stem := regexp_replace(v_norm, '[^a-z\s]', '', 'g');
  v_stem := regexp_replace(v_stem, '\s+', ' ', 'g');
  v_stem := trim(v_stem);

  -- FOMO planeado: só seller/staff (última unidade / esgotado)
  if v_is_ops and (
       v_stem ~ 'ultima unidade'
    or v_stem ~ 'esgotado'
  ) then
    v_allowed := true;
    v_seller_fomo := true;
  end if;

  if v_stem ~ 'bem ?vindos'
     or v_stem ~ 'directo esta a comecar'
     or v_stem ~ 'o directo esta a comecar'
     or v_stem ~ 'recusaste o pedido'
     or v_stem ~ 'pedido de .+ aguarda'
     or v_stem ~ 'reservou( para o saco| )'
     or v_stem ~ 'reserva cancelada'
     or v_stem = 'sistema'
  then
    v_allowed := true;
  end if;

  if not v_allowed then
    return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
  end if;

  -- Compradores/atacantes: nunca FOMO com emoji scarcity
  if not v_seller_fomo then
    if v_body like '%🔥%' or v_body like '%🛒%' or v_body like '%💨%'
       or v_body like '%⚡%' or v_body like '%🧨%' then
      return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
    end if;
  end if;

  if v_role is distinct from 'service_role' then
    if not v_is_ops then
      select exists(
        select 1
        from public.live_reservation_requests r
        where r.live_id = p_live_id
          and r.buyer_id = v_uid
          and r.status in ('pending', 'accepted', 'rejected', 'converted')
      ) into v_participant;
      if not coalesce(v_participant, false) then
        return jsonb_build_object('ok', false, 'error', 'not_allowed');
      end if;
    end if;

    insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
    values (v_uid, 'batata_live_system_message', v_window, 1)
    on conflict (uid, rpc, window_start) do update
    set hits = public.batata_rpc_rate_limits.hits + 1
    returning hits into v_hits;
    if v_hits > 60 then
      return jsonb_build_object('ok', false, 'error', 'rate_limited');
    end if;
  end if;

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label)
  values (
    p_live_id,
    coalesce(v_uid, v_seller),
    'system',
    v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text) from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

comment on function public.batata_live_system_message(uuid, text, text) is
  'Ops allowlist + FOMO seller/staff. Buyer participante só reservou/cancel. Sem FOMO forjado.';

notify pgrst, 'reload schema';
