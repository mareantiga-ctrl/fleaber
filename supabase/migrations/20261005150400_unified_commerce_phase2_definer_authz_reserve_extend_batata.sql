-- =============================================================================
-- BATATA 2026-10-05 — Phase 2: DEFINER-safe authz on reserve + extend
-- Same class as actor spoof: `current_user = postgres` is always true inside
-- SECURITY DEFINER owned by postgres, so seller/buyer checks were skipped.
-- Fix: gate on auth.role() = 'service_role' only. No processed_by on these RPCs.
-- =============================================================================

create or replace function public.batata_reserve_with_policy(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_live_id uuid,
  p_live_item_id uuid,
  p_qty integer default 1,
  p_source text default 'fleaber_live',
  p_guest_session_id uuid default null,
  p_identity_linked boolean default true,
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
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_lock_key text;
  v_avail integer;
  v_decision jsonb;
  v_outcome text;
  v_request_kind text;
  v_status text;
  v_ttl integer;
  v_expires timestamptz;
  v_row public.live_reservation_requests%rowtype;
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_product uuid;
  v_event jsonb;
begin
  if p_live_item_id is null or p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  -- DEFINER-safe: never use current_user (owner is postgres)
  if v_role is distinct from 'service_role' then
    if v_uid is null then
      return jsonb_build_object('ok', false, 'error', 'not_authenticated');
    end if;
    if p_buyer_id is null or p_buyer_id is distinct from v_uid then
      return jsonb_build_object('ok', false, 'error', 'buyer_self_only');
    end if;
  end if;

  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = coalesce(p_live_id, v_li.live_id);
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is distinct from p_seller_id then
    return jsonb_build_object('ok', false, 'error', 'seller_mismatch');
  end if;

  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  v_lock_key := coalesce(v_product::text, p_live_item_id::text) || ':commerce_reserve';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);

  v_decision := public.batata_commerce_decide_reservation_outcome(
    p_seller_id,
    p_buyer_id,
    v_avail,
    v_qty,
    coalesce(p_identity_linked, true)
  );

  if coalesce((v_decision->>'ok')::boolean, false) = false then
    return v_decision;
  end if;

  v_outcome := v_decision->>'outcome';
  if v_outcome = 'UNAVAILABLE' then
    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'decision', v_decision,
      'request_id', null
    );
  end if;

  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);
  if v_avail < v_qty then
    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'decision', v_decision,
      'request_id', null,
      'reason', 'stock_race'
    );
  end if;

  v_request_kind := v_decision->>'request_kind';
  v_status := v_decision->>'status';
  v_ttl := nullif(v_decision->>'ttl_seconds', '')::integer;

  if v_outcome = 'GUARANTEED' then
    v_expires := timezone('utc', now()) + make_interval(secs => v_ttl);
  elsif v_outcome = 'PENDING_APPROVAL' then
    v_expires := timezone('utc', now()) + interval '45 minutes';
  else
    v_expires := null;
  end if;

  insert into public.live_reservation_requests (
    live_id,
    live_item_id,
    seller_id,
    buyer_id,
    requested_qty,
    status,
    source,
    notes,
    expires_at,
    request_kind,
    policy_mode_snapshot,
    untrusted_mode_snapshot,
    trust_decision_snapshot,
    ttl_seconds_snapshot,
    policy_version_snapshot,
    guest_session_id
  ) values (
    coalesce(p_live_id, v_li.live_id),
    p_live_item_id,
    p_seller_id,
    p_buyer_id,
    v_qty,
    v_status,
    coalesce(nullif(trim(p_source), ''), 'fleaber_live'),
    p_notes,
    v_expires,
    v_request_kind,
    v_decision->>'policy_mode',
    v_decision->>'untrusted_mode',
    v_decision->'trust'->>'decision',
    v_ttl,
    nullif(v_decision->>'policy_version', '')::integer,
    p_guest_session_id
  )
  returning * into v_row;

  if v_outcome = 'GUARANTEED' then
    begin
      perform public.batata_recompute_live_item_status(p_live_item_id);
    exception when others then
      null;
    end;
    v_event := public.batata_commerce_emit_reservation_event(
      v_row.id,
      'reservation_guaranteed',
      jsonb_build_object(
        'expires_at', v_row.expires_at,
        'ttl_seconds', v_ttl,
        'source', 'reserve_with_policy',
        'live_item_id', p_live_item_id,
        'buyer_id', p_buyer_id,
        'seller_id', p_seller_id
      )
    );
    perform public.batata_close_pending_for_stock(p_live_item_id, v_row.id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'outcome', v_outcome,
    'request_id', v_row.id,
    'status', v_row.status,
    'request_kind', v_row.request_kind,
    'expires_at', v_row.expires_at,
    'ttl_seconds_snapshot', v_row.ttl_seconds_snapshot,
    'policy_version_snapshot', v_row.policy_version_snapshot,
    'trust_decision_snapshot', v_row.trust_decision_snapshot,
    'decision', v_decision,
    'd19_event', coalesce(v_event, '{}'::jsonb),
    'available_qty_after', public.batata_live_item_available_qty_engine(p_live_item_id)
  );
end;
$$;

create or replace function public.batata_commerce_extend_guaranteed_once(
  p_request_id uuid,
  p_ttl_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_req public.live_reservation_requests%rowtype;
  v_ttl integer := p_ttl_seconds;
begin
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_request_id');
  end if;
  if v_ttl is null or v_ttl < 900 or v_ttl > 432000 then
    return jsonb_build_object('ok', false, 'error', 'ttl_out_of_range');
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- DEFINER-safe seller gate
  if v_role is distinct from 'service_role' then
    if v_uid is null or v_uid is distinct from v_req.seller_id then
      return jsonb_build_object('ok', false, 'error', 'seller_only');
    end if;
  end if;

  if v_req.status is distinct from 'accepted' then
    return jsonb_build_object('ok', false, 'error', 'not_guaranteed');
  end if;

  if coalesce(v_req.extended_once, false) then
    return jsonb_build_object('ok', false, 'error', 'already_extended');
  end if;

  update public.live_reservation_requests
  set
    extended_once = true,
    extended_at = timezone('utc', now()),
    extension_ttl_seconds = v_ttl,
    expires_at = timezone('utc', now()) + make_interval(secs => v_ttl),
    updated_at = timezone('utc', now())
  where id = v_req.id
  returning * into v_req;

  perform public.batata_commerce_emit_reservation_event(
    v_req.id,
    'extension_applied',
    jsonb_build_object(
      'extension_ttl_seconds', v_ttl,
      'new_expires_at', v_req.expires_at
    )
  );

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'expires_at', v_req.expires_at,
    'extended_once', true,
    'extension_ttl_seconds', v_ttl
  );
end;
$$;

revoke all on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  from public;
grant execute on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  to authenticated, service_role;

revoke all on function public.batata_commerce_extend_guaranteed_once(uuid, integer) from public;
grant execute on function public.batata_commerce_extend_guaranteed_once(uuid, integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';
