-- =============================================================================
-- BATATA 2026-10-05 — Phase 2 correction: zero stock → UNAVAILABLE for NEW rows
-- PENDING never blocks stock (unchanged).
-- BUT: do not CREATE new approval_pending or bag_hold_none when available < qty.
-- Existing pending may still close via batata_close_pending_for_stock.
-- Additive. Does NOT edit prior migrations.
-- =============================================================================

create or replace function public.batata_commerce_decide_reservation_outcome(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_available_qty integer,
  p_requested_qty integer default 1,
  p_identity_linked boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_settings public.seller_reservation_settings%rowtype;
  v_trust jsonb;
  v_has_benefit boolean := false;
  v_decision text;
  v_qty integer := greatest(coalesce(p_requested_qty, 1), 1);
  v_avail integer := greatest(coalesce(p_available_qty, 0), 0);
  v_outcome text;
  v_request_kind text;
  v_ttl integer;
  v_status text;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_seller');
  end if;

  select * into v_settings
  from public.seller_reservation_settings
  where seller_id = p_seller_id;

  if v_settings.seller_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'policy_not_configured',
      'outcome', 'UNAVAILABLE'
    );
  end if;

  if coalesce(p_identity_linked, true) = false or p_buyer_id is null then
    v_trust := jsonb_build_object(
      'ok', true,
      'decision', 'IDENTITY_INSUFFICIENT',
      'has_benefit', false
    );
  else
    v_trust := public.batata_buyer_trust_decision(p_seller_id, p_buyer_id);
  end if;

  v_has_benefit := coalesce((v_trust->>'has_benefit')::boolean, false);
  v_decision := coalesce(v_trust->>'decision', 'IDENTITY_INSUFFICIENT');

  -- HARD RULE: no stock at action time → UNAVAILABLE for ALL commercial paths.
  -- Pending does not block; that does NOT mean invent a new pending/bag on zero stock.
  if v_avail < v_qty then
    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'request_kind', null,
      'status', null,
      'ttl_seconds', null,
      'trust', v_trust,
      'policy_mode', v_settings.policy_mode,
      'untrusted_mode', v_settings.untrusted_mode,
      'policy_version', v_settings.policy_version,
      'normal_ttl_seconds', v_settings.normal_ttl_seconds,
      'trusted_ttl_seconds', v_settings.trusted_ttl_seconds,
      'available_qty', v_avail,
      'requested_qty', v_qty,
      'reason', 'insufficient_stock'
    );
  end if;

  if v_settings.policy_mode = 'auto'
     or (v_settings.policy_mode = 'trust' and v_has_benefit) then
    v_outcome := 'GUARANTEED';
    v_request_kind := 'guaranteed';
    v_status := 'accepted';
    v_ttl := case
      when v_has_benefit then v_settings.trusted_ttl_seconds
      else v_settings.normal_ttl_seconds
    end;
  elsif v_settings.policy_mode = 'trust' and not v_has_benefit then
    if v_settings.untrusted_mode = 'approval' then
      v_outcome := 'PENDING_APPROVAL';
      v_request_kind := 'approval_pending';
      v_status := 'pending';
      v_ttl := 2700;
    else
      v_outcome := 'BAG_UNGUARANTEED';
      v_request_kind := 'bag_hold_none';
      v_status := 'pending';
      v_ttl := null;
    end if;
  elsif v_settings.policy_mode = 'manual' then
    v_outcome := 'PENDING_APPROVAL';
    v_request_kind := 'approval_pending';
    v_status := 'pending';
    v_ttl := 2700;
  elsif v_settings.policy_mode = 'pay_only' then
    v_outcome := 'BAG_UNGUARANTEED';
    v_request_kind := 'bag_hold_none';
    v_status := 'pending';
    v_ttl := null;
  else
    return jsonb_build_object('ok', false, 'error', 'unsupported_policy_mode');
  end if;

  return jsonb_build_object(
    'ok', true,
    'outcome', v_outcome,
    'request_kind', v_request_kind,
    'status', v_status,
    'ttl_seconds', v_ttl,
    'trust', v_trust,
    'policy_mode', v_settings.policy_mode,
    'untrusted_mode', v_settings.untrusted_mode,
    'policy_version', v_settings.policy_version,
    'normal_ttl_seconds', v_settings.normal_ttl_seconds,
    'trusted_ttl_seconds', v_settings.trusted_ttl_seconds,
    'available_qty', v_avail,
    'requested_qty', v_qty
  );
end;
$$;

comment on function public.batata_commerce_decide_reservation_outcome(uuid, uuid, integer, integer, boolean) is
  'Canonical outcome. available < qty → UNAVAILABLE for guaranteed/pending/bag. Pending never blocks; new rows not created on zero stock.';

revoke all on function public.batata_commerce_decide_reservation_outcome(uuid, uuid, integer, integer, boolean)
  from public;
grant execute on function public.batata_commerce_decide_reservation_outcome(uuid, uuid, integer, integer, boolean)
  to authenticated, service_role;

-- Harden write path: under lock, refuse insert for ANY outcome if stock raced to zero
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

  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
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

  -- Re-check under lock for ALL outcomes (including pending/bag)
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

revoke all on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  from public;
grant execute on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
