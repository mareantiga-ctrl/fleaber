-- =============================================================================
-- BATATA 2026-10-05 — Phase 2 final hardening: block authenticated actor spoof
-- Root cause: processed_by_user_id = coalesce(p_processed_by, auth.uid())
-- allowed an authenticated seller to record another person's UUID as the actor.
-- Fix: authenticated → ALWAYS auth.uid(); ignore p_processed_by.
-- service_role / postgres → may set p_processed_by for legitimate backend ops.
-- Authz (seller/staff only) unchanged. Additive. Staging only.
-- =============================================================================

create or replace function public.batata_commerce_accept_pending(
  p_request_id uuid,
  p_processed_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_backend boolean := (
    v_role = 'service_role' or current_user = 'postgres'
  );
  v_actor uuid;
  v_req public.live_reservation_requests%rowtype;
  v_settings public.seller_reservation_settings%rowtype;
  v_trust jsonb;
  v_has_benefit boolean;
  v_ttl integer;
  v_avail integer;
  v_lock_key text;
  v_product uuid;
  v_li public.live_items%rowtype;
  v_event jsonb;
begin
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_request_id');
  end if;

  -- Audit actor: authenticated clients NEVER choose identity.
  if v_is_backend then
    v_actor := coalesce(p_processed_by, v_uid);
  else
    v_actor := v_uid;
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if not v_is_backend then
    if v_uid is null or v_uid is distinct from v_req.seller_id then
      if not public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations') then
        return jsonb_build_object('ok', false, 'error', 'seller_only');
      end if;
    end if;
  end if;

  if v_req.status is distinct from 'pending'
     or coalesce(v_req.request_kind, 'approval_pending') is distinct from 'approval_pending' then
    return jsonb_build_object(
      'ok', false,
      'error', 'not_approval_pending',
      'status', v_req.status,
      'request_kind', v_req.request_kind
    );
  end if;

  select * into v_li from public.live_items where id = v_req.live_item_id;
  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  v_lock_key := coalesce(v_product::text, v_req.live_item_id::text) || ':commerce_reserve';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_avail := public.batata_live_item_available_qty_engine(v_req.live_item_id);
  if v_avail < greatest(coalesce(v_req.requested_qty, 1), 1) then
    update public.live_reservation_requests
    set
      status = 'expired',
      expiry_reason = 'stock_unavailable',
      unavailable_at = timezone('utc', now()),
      notes = trim(both ' |' from coalesce(notes, '') || ' | accept_no_stock'),
      processed_by_user_id = v_actor,
      updated_at = timezone('utc', now())
    where id = v_req.id;

    perform public.batata_commerce_emit_reservation_event(
      v_req.id,
      'pending_stock_unavailable',
      jsonb_build_object('source', 'accept_no_stock', 'available_qty', v_avail)
    );

    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'request_id', v_req.id,
      'status', 'expired',
      'expiry_reason', 'stock_unavailable',
      'available_qty', v_avail,
      'processed_by_user_id', v_actor
    );
  end if;

  select * into v_settings
  from public.seller_reservation_settings
  where seller_id = v_req.seller_id;

  v_trust := public.batata_buyer_trust_decision(v_req.seller_id, v_req.buyer_id);
  v_has_benefit := coalesce((v_trust->>'has_benefit')::boolean, false);

  if v_settings.seller_id is not null then
    v_ttl := case
      when v_has_benefit then v_settings.trusted_ttl_seconds
      else v_settings.normal_ttl_seconds
    end;
  else
    v_ttl := 432000;
  end if;

  update public.live_reservation_requests
  set
    status = 'accepted',
    request_kind = 'guaranteed',
    expires_at = timezone('utc', now()) + make_interval(secs => v_ttl),
    ttl_seconds_snapshot = v_ttl,
    policy_mode_snapshot = coalesce(v_settings.policy_mode, policy_mode_snapshot),
    untrusted_mode_snapshot = coalesce(v_settings.untrusted_mode, untrusted_mode_snapshot),
    trust_decision_snapshot = coalesce(v_trust->>'decision', trust_decision_snapshot),
    policy_version_snapshot = coalesce(v_settings.policy_version, policy_version_snapshot),
    processed_by_user_id = v_actor,
    updated_at = timezone('utc', now())
  where id = v_req.id
  returning * into v_req;

  begin
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then
    null;
  end;

  v_event := public.batata_commerce_emit_reservation_event(
    v_req.id,
    'reservation_guaranteed',
    jsonb_build_object(
      'expires_at', v_req.expires_at,
      'ttl_seconds', v_ttl,
      'source', 'seller_accept',
      'live_item_id', v_req.live_item_id,
      'processed_by_user_id', v_actor
    )
  );

  perform public.batata_close_pending_for_stock(v_req.live_item_id, v_req.id);

  return jsonb_build_object(
    'ok', true,
    'outcome', 'GUARANTEED',
    'request_id', v_req.id,
    'status', v_req.status,
    'request_kind', v_req.request_kind,
    'expires_at', v_req.expires_at,
    'ttl_seconds_snapshot', v_req.ttl_seconds_snapshot,
    'processed_by_user_id', v_req.processed_by_user_id,
    'd19_event', v_event,
    'available_qty_after', public.batata_live_item_available_qty_engine(v_req.live_item_id)
  );
end;
$$;

create or replace function public.batata_commerce_reject_pending(
  p_request_id uuid,
  p_processed_by uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_backend boolean := (
    v_role = 'service_role' or current_user = 'postgres'
  );
  v_actor uuid;
  v_req public.live_reservation_requests%rowtype;
begin
  if v_is_backend then
    v_actor := coalesce(p_processed_by, v_uid);
  else
    v_actor := v_uid;
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if not v_is_backend then
    if v_uid is null or v_uid is distinct from v_req.seller_id then
      if not public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations') then
        return jsonb_build_object('ok', false, 'error', 'seller_only');
      end if;
    end if;
  end if;

  if v_req.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;

  update public.live_reservation_requests
  set
    status = 'rejected',
    expiry_reason = 'seller_cancelled',
    notes = coalesce(p_notes, notes),
    processed_by_user_id = v_actor,
    updated_at = timezone('utc', now())
  where id = v_req.id
  returning * into v_req;

  begin
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true,
    'outcome', 'REJECTED',
    'request_id', v_req.id,
    'status', v_req.status,
    'processed_by_user_id', v_req.processed_by_user_id
  );
end;
$$;

comment on function public.batata_commerce_accept_pending(uuid, uuid) is
  'Seller/staff accept approval_pending. Authenticated actor = auth.uid() only; p_processed_by ignored for clients. service_role may set actor.';

comment on function public.batata_commerce_reject_pending(uuid, uuid, text) is
  'Seller/staff reject pending. Authenticated actor = auth.uid() only; p_processed_by ignored for clients. service_role may set actor.';

revoke all on function public.batata_commerce_accept_pending(uuid, uuid) from public;
revoke all on function public.batata_commerce_reject_pending(uuid, uuid, text) from public;
grant execute on function public.batata_commerce_accept_pending(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.batata_commerce_reject_pending(uuid, uuid, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
