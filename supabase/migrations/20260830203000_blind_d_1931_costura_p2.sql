-- =============================================================================
-- BATATA — Blind D Costura 1931 (P2 only; PASS_CEGO_SATURADO)
-- P2-01: JWT participante forja INSERT FLEABER_JSON_V1 sistema
-- P2-02: email→UUID oracle (staff) — convidar sem revelar UUID em probe
-- P2-03: ps-heartbeat grava live_id alheia
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P2-01 — INSERT de cards JSON: papéis + order coerente
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_raw text;
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_chat_a uuid;
  v_chat_b uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  -- sender forçado ao JWT (já comum em RLS; reforço)
  NEW.sender_id := v_uid;

  v_raw := coalesce(NEW.text, '');
  if v_raw not like 'FLEABER_JSON_V1:%' then
    return NEW;
  end if;

  begin
    v_json := substring(v_raw from length('FLEABER_JSON_V1:') + 1)::jsonb;
  exception when others then
    raise exception 'chat_system_card_invalid_json' using errcode = '23514';
  end;

  v_kind := lower(trim(coalesce(v_json->>'kind', '')));
  if v_kind = '' then
    raise exception 'chat_system_card_kind_required' using errcode = '23514';
  end if;

  -- Só Edge / service_role (não JWT)
  if v_kind in (
    'marketplace_bag_paid',
    'auto_feedback_generated',
    'raffle_prize',
    'premio_rifa'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c
  where c.id = NEW.chat_id;

  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;

  if v_uid is distinct from v_chat_a and v_uid is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  -- Kinds com order_id: validar papel
  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;

  if v_oid is not null then
    select o.seller_id, o.buyer_id
      into v_order_seller, v_order_buyer
    from public.orders o
    where o.id = v_oid;

    if not found then
      raise exception 'chat_system_card_order_missing' using errcode = '23514';
    end if;

    -- Order tem de ligar aos dois do chat
    if not (
      (v_order_seller is not distinct from v_chat_a and v_order_buyer is not distinct from v_chat_b)
      or (v_order_seller is not distinct from v_chat_b and v_order_buyer is not distinct from v_chat_a)
    ) then
      raise exception 'chat_system_card_order_chat_mismatch' using errcode = '23514';
    end if;

    -- Seller-only narrative
    if v_kind in (
      'reservation_seller_confirmed_receipt',
      'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller',
      'reservation_order_shipped',
      'reservation_accepted',
      'reservation_request_outcome',
      'price_offer_outcome',
      'cancel_request_outcome',
      'bundle_direct_payment_details',
      'order_direct_payment_details'
    ) then
      if v_uid is distinct from v_order_seller then
        raise exception 'chat_system_card_seller_only' using errcode = '42501';
      end if;
    end if;

    -- Buyer-only narrative
    if v_kind in (
      'bundle_buyer_confirmed_receipt',
      'reservation_payment_submitted',
      'reservation_request',
      'reservation_order_completed',
      'cancel_request',
      'order_review_submitted',
      'seguro_fleaber_paid',
      'price_offer'
    ) then
      if v_uid is distinct from v_order_buyer then
        raise exception 'chat_system_card_buyer_only' using errcode = '42501';
      end if;
    end if;

    -- Ambos (disputa, etc.)
    if v_kind in ('order_dispute_opened') then
      if v_uid is distinct from v_order_buyer and v_uid is distinct from v_order_seller then
        raise exception 'chat_system_card_party_only' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Allowlist residual (UI sem order ou já validado)
  if v_kind not in (
    'chat_image',
    'bundle_proposal',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'price_offer',
    'price_offer_outcome',
    'reservation_accepted',
    'reservation_request',
    'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt',
    'cancel_request',
    'cancel_request_outcome',
    'order_dispute_opened',
    'order_review_submitted',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed',
    'reservation_order_shipped',
    'reservation_payment_submitted',
    'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_insert on public.chat_messages;
create trigger trg_batata_chat_messages_guard_insert
  before insert on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_insert();

comment on function public.batata_chat_messages_guard_insert() is
  'D1931-P2: FLEABER_JSON_V1 INSERT só com kind allowlist + papel order/chat.';

-- ---------------------------------------------------------------------------
-- P2-03 — heartbeat só na própria live
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_reader_heartbeat(
  p_device_token text,
  p_live_id uuid,
  p_device_id text,
  p_status text default 'online',
  p_app_version text default null,
  p_last_error text default null,
  p_roi_ok boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
  v_live_seller uuid;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;

  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_live_seller
  from public.lives l
  where l.id = p_live_id;

  if v_live_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_live_seller is distinct from v_seller_id then
    return jsonb_build_object('ok', false, 'error', 'live_not_owned');
  end if;

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, last_error, roi_ok, last_seen_at
  ) values (
    v_seller_id,
    p_live_id,
    trim(coalesce(p_device_id, '')),
    coalesce(nullif(trim(p_status), ''), 'online'),
    nullif(trim(coalesce(p_app_version, '')), ''),
    nullif(trim(coalesce(p_last_error, '')), ''),
    p_roi_ok,
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = coalesce(excluded.live_id, ps_reader_heartbeats.live_id),
    status = excluded.status,
    app_version = coalesce(excluded.app_version, ps_reader_heartbeats.app_version),
    last_error = excluded.last_error,
    roi_ok = excluded.roi_ok,
    last_seen_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_ps_reader_heartbeat(text, uuid, text, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.batata_ps_reader_heartbeat(text, uuid, text, text, text, text, boolean)
  to service_role;

comment on function public.batata_ps_reader_heartbeat(text, uuid, text, text, text, text, boolean) is
  'D1931-P2: heartbeat só se live.seller_id = seller do device token.';

-- ---------------------------------------------------------------------------
-- P2-02 — convite staff por email (sem oracle UUID em probe solto)
-- ---------------------------------------------------------------------------
create or replace function public.batata_staff_invite_helper_by_email(
  p_email text,
  p_display_name text,
  p_permissions jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_name text := trim(coalesce(p_display_name, ''));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_helper uuid;
  v_ok boolean := false;
  v_link_id uuid;
  v_existing public.seller_helpers%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 120 then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  )
  and exists (
    select 1 from public.products pr where pr.seller_id = v_uid limit 1
  )
  into v_ok;

  if not coalesce(v_ok, false) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_staff_invite_helper_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id into v_helper
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  -- Mensagem genérica: não distinguir «email inexistente» vs outros (anti-oracle)
  if v_helper is null then
    raise exception 'invite_unavailable' using errcode = 'P0001';
  end if;

  if v_helper = v_uid then
    raise exception 'cannot_invite_self' using errcode = '23514';
  end if;

  select * into v_existing
  from public.seller_helpers h
  where h.seller_id = v_uid
    and h.helper_user_id = v_helper
  limit 1;

  if found then
    if coalesce(v_existing.invitation_status, '') = 'accepted' then
      raise exception 'already_member' using errcode = '23505';
    end if;
    if coalesce(v_existing.invitation_status, '') = 'pending' then
      raise exception 'invite_pending' using errcode = '23505';
    end if;
    update public.seller_helpers
    set invitation_status = 'pending',
        display_name = v_name,
        invited_email = v_email,
        permissions = coalesce(p_permissions, '{}'::jsonb),
        invited_by = v_uid,
        updated_at = now(),
        responded_at = null,
        active = false
    where id = v_existing.id
    returning id into v_link_id;
    return v_link_id;
  end if;

  insert into public.seller_helpers (
    seller_id,
    helper_user_id,
    invited_email,
    display_name,
    active,
    invitation_status,
    permissions,
    invited_by,
    updated_at
  ) values (
    v_uid,
    v_helper,
    v_email,
    v_name,
    false,
    'pending',
    coalesce(p_permissions, '{}'::jsonb),
    v_uid,
    now()
  )
  returning id into v_link_id;

  return v_link_id;
end;
$$;

revoke all on function public.batata_staff_invite_helper_by_email(text, text, jsonb)
  from public, anon;
grant execute on function public.batata_staff_invite_helper_by_email(text, text, jsonb)
  to authenticated, service_role;

comment on function public.batata_staff_invite_helper_by_email(text, text, jsonb) is
  'D1931-P2: convite staff por email sem RPC de enumeração solta.';

-- Oracle solto: JWT autenticado deixa de receber UUID (service_role mantém para tooling)
create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_email text := lower(trim(coalesce(p_email, '')));
  v_found uuid;
begin
  if v_role = 'service_role' then
    if v_email = '' or position('@' in v_email) = 0 then
      return null;
    end if;
    select u.id into v_found
    from auth.users u
    where lower(trim(u.email)) = v_email
    limit 1;
    return v_found;
  end if;

  -- JWT: sem oracle. Usar batata_staff_invite_helper_by_email.
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return null;
end;
$$;

comment on function public.batata_find_user_id_by_email(text) is
  'D1931-P2: JWT → null (anti-oracle); service_role tooling OK. Convites: invite_by_email.';

revoke all on function public.batata_find_user_id_by_email(text) from public, anon;
grant execute on function public.batata_find_user_id_by_email(text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
