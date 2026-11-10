-- =============================================================================
-- BATATA 2026-09-13 — accept chat: nome Face estável (não trocar para handle Fleaber)
-- =============================================================================
-- Causa: após claim Face→Fleaber, accept_broadcast usava profiles.full_name/handle
--        (Joao84) enquanto o «reservou» usava external_display_name (Mariana Soares).
-- Fix: preferir sempre external_display_name quando existir; perfil só como fallback.
-- Hardening: sem mudanças de RLS; só o texto do anúncio social.

create or replace function public.batata_live_reservation_accept_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid,
  p_requested_qty integer default 1
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_name text;
  v_label text;
  v_body text;
  v_qty integer;
  v_has_accept boolean := false;
  v_ext text;
  v_profile text;
begin
  if p_live_id is null or p_live_item_id is null then
    return false;
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller from public.lives where id = p_live_id;
  if v_seller is null then
    return false;
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null or v_role is distinct from 'authenticated' then
      return false;
    end if;
    if v_uid is distinct from v_seller
       and not public.batata_staff_has_permission(v_seller, 'can_manage_chat')
       and not public.batata_staff_has_permission(v_seller, 'can_manage_reservations') then
      return false;
    end if;
  end if;

  select exists(
    select 1 from public.live_reservation_requests r
    where r.live_id = p_live_id
      and r.live_item_id = p_live_item_id
      and r.status = 'accepted'
      and (
        (p_buyer_id is not null and r.buyer_id = p_buyer_id)
        or (p_buyer_id is null and r.buyer_id is null)
      )
  ) into v_has_accept;
  if not coalesce(v_has_accept, false) then
    return false;
  end if;

  -- Nome público da reserva: Face/OCR primeiro (mesmo fio que «reservou»).
  select nullif(trim(r.external_display_name), '')
  into v_ext
  from public.live_reservation_requests r
  where r.live_id = p_live_id
    and r.live_item_id = p_live_item_id
    and r.status = 'accepted'
    and (
      (p_buyer_id is not null and r.buyer_id = p_buyer_id)
      or (p_buyer_id is null and r.buyer_id is null)
    )
  order by r.updated_at desc nulls last, r.created_at desc
  limit 1;

  if p_buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(handle), ''))
    into v_profile
    from public.profiles
    where id = p_buyer_id;
  end if;

  v_name := coalesce(
    nullif(trim(v_ext), ''),
    nullif(trim(v_profile), ''),
    'Comprador'
  );

  v_label := public.batata_live_item_chat_label(p_live_item_id);
  v_qty := greatest(coalesce(p_requested_qty, 1), 1);

  if v_qty > 1 then
    v_body := '🔒 Reserva aceite — ' || v_qty || ' un. · ' || v_label
      || ' · ' || v_name || ' tem 5 dias para pagar';
  else
    v_body := '🔒 Reserva aceite — ' || v_label || ' · ' || v_name
      || ' tem 5 dias para pagar';
  end if;

  if exists (
    select 1 from public.live_messages m
    where m.live_id = p_live_id and m.body = v_body
      and m.created_at > now() - interval '2 minutes'
  ) then
    return true;
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label, channel)
  values (
    p_live_id,
    coalesce(p_buyer_id, v_seller),
    'system',
    v_body,
    'Sistema',
    'fleaber'
  );
  return true;
end;
$$;

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer)
  to authenticated, service_role;

comment on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) is
  'Reserva aceite → chat social. Nome: external_display_name (Face) se existir; senão perfil Fleaber.';

notify pgrst, 'reload schema';
