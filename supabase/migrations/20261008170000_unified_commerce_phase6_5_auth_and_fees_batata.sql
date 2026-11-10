-- =============================================================================
-- BATATA 2026-10-08 — Phase 6.5: reservation ownership + fee recompute after qty sync
-- Staging only. Production untouched. No Phase 7.
-- =============================================================================

-- Ownership: knowing reservation_id is NOT enough.
-- Orphan facebook_manual (null buyer + null guest) must be claimed/bound first.
create or replace function public.batata_commerce_reservation_usable_by_actor(
  p_reservation_id uuid,
  p_buyer_id uuid,
  p_guest_session_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.live_reservation_requests%rowtype;
begin
  if p_reservation_id is null then
    return false;
  end if;
  if p_buyer_id is null and p_guest_session_id is null then
    return false;
  end if;

  select * into v_row
  from public.live_reservation_requests r
  where r.id = p_reservation_id;

  if v_row.id is null then
    return false;
  end if;

  -- Authenticated owner
  if p_buyer_id is not null and v_row.buyer_id is not distinct from p_buyer_id then
    return true;
  end if;

  -- Guest owner (bound session)
  if p_guest_session_id is not null
     and v_row.guest_session_id is not null
     and v_row.guest_session_id is not distinct from p_guest_session_id then
    return true;
  end if;

  -- Explicit deny: orphan FB / foreign buyer / foreign guest
  return false;
end;
$$;

revoke all on function public.batata_commerce_reservation_usable_by_actor(uuid, uuid, uuid)
  from public;
grant execute on function public.batata_commerce_reservation_usable_by_actor(uuid, uuid, uuid)
  to authenticated, service_role;

-- Sync under locks + ownership filter (unauthorized req ids stripped, never locked)
create or replace function public.batata_commerce_checkout_sync_lines_under_locks(
  p_lines jsonb,
  p_buyer_id uuid default null,
  p_guest_session_id uuid default null,
  p_shipping_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[] := array[]::uuid[];
  v_line jsonb;
  v_req_id uuid;
  v_row public.live_reservation_requests%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_qty int;
  v_unit int;
  v_line_cents int;
  v_items int := 0;
  v_changed boolean := false;
  v_stripped boolean := false;
  v_denied uuid[] := array[]::uuid[];
  v_client_qty int;
  v_ship int := 0;
  v_prot int := 0;
begin
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    if v_req_id is null then
      continue;
    end if;
    if public.batata_commerce_reservation_usable_by_actor(
         v_req_id, p_buyer_id, p_guest_session_id
       ) then
      if not (v_req_id = any (v_ids)) then
        v_ids := array_append(v_ids, v_req_id);
      end if;
    else
      v_denied := array_append(v_denied, v_req_id);
      v_stripped := true;
    end if;
  end loop;

  -- Hard deny if client tried to use a foreign/orphan reservation id
  if cardinality(v_denied) > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'reservation_not_authorized',
      'denied_reservation_ids', to_jsonb(v_denied),
      'message', 'reservation_id_alone_does_not_authorize_checkout'
    );
  end if;

  perform public.batata_commerce_lock_reservations_ps_checkout(v_ids);

  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    v_client_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    v_qty := v_client_qty;
    v_unit := coalesce((v_line->>'unit_cents')::int, 0);

    if v_req_id is not null then
      select * into v_row
      from public.live_reservation_requests r
      where r.id = v_req_id;
      if v_row.id is not null
         and v_row.status in ('pending', 'accepted')
         and coalesce(v_row.requested_qty, 1) is distinct from v_client_qty then
        v_qty := greatest(coalesce(v_row.requested_qty, 1), 1);
        v_changed := true;
      elsif v_row.id is not null then
        v_qty := greatest(coalesce(v_row.requested_qty, v_client_qty), 1);
      end if;
    end if;

    if v_unit > 0 then
      v_line_cents := v_unit * v_qty;
    else
      v_line_cents := coalesce((v_line->>'line_cents')::int, v_unit * v_qty);
    end if;
    v_items := v_items + v_line_cents;

    v_out := v_out || jsonb_build_array(
      v_line || jsonb_build_object(
        'quantity', v_qty,
        'line_cents', v_line_cents,
        'qty_synced_from_reservation', (v_req_id is not null)
      )
    );
  end loop;

  -- Recompute fees from final items (protection depends on items+shipping)
  if p_shipping_method is not null and length(trim(p_shipping_method)) > 0 then
    begin
      v_ship := public.batata_commerce_shipping_cents(p_shipping_method);
    exception when others then
      v_ship := 0;
    end;
  end if;
  v_prot := public.batata_commerce_protection_fee_cents(v_items, v_ship);

  return jsonb_build_object(
    'ok', true,
    'lines', v_out,
    'items_cents', v_items,
    'shipping_cents', v_ship,
    'protection_fee_cents', v_prot,
    'total_cents', v_items + v_ship + v_prot,
    'qty_changed', v_changed,
    'stripped_unauthorized', v_stripped,
    'locked_reservation_ids', to_jsonb(v_ids)
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb, uuid, uuid, text)
  from public;
grant execute on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb, uuid, uuid, text)
  to service_role;

-- Keep 1-arg overload forwarding for compatibility (no actor → deny any reservation ids)
create or replace function public.batata_commerce_checkout_sync_lines_under_locks(
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.batata_commerce_checkout_sync_lines_under_locks(
    p_lines, null, null, null
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb) from public;
grant execute on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb)
  to service_role;

-- Harden locked checkout snapshot (staging helper) with ownership
create or replace function public.batata_commerce_ps_locked_checkout_snapshot(
  p_reservation_id uuid,
  p_seller_id uuid,
  p_product_id uuid,
  p_live_item_id uuid,
  p_live_id uuid,
  p_buyer_id uuid default null,
  p_guest_session_id uuid default null,
  p_client_qty integer default null,
  p_unit_cents integer default 1000,
  p_status text default 'payment_processing',
  p_payment_rail text default 'stripe',
  p_shipping_method text default 'ctt'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_reservation_requests%rowtype;
  v_qty int;
  v_attempt public.commerce_checkout_attempts%rowtype;
  v_hold_id uuid;
  v_expires timestamptz := timezone('utc', now()) + interval '30 minutes';
  v_items int;
  v_ship int;
  v_prot int;
  v_guest uuid := p_guest_session_id;
begin
  if p_reservation_id is null or p_seller_id is null or p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if p_buyer_id is null and v_guest is null then
    return jsonb_build_object('ok', false, 'error', 'identity_required');
  end if;
  if p_buyer_id is not null and v_guest is not null then
    return jsonb_build_object('ok', false, 'error', 'identity_xor');
  end if;

  if not public.batata_commerce_reservation_usable_by_actor(
       p_reservation_id, p_buyer_id, v_guest
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'reservation_not_authorized',
      'message', 'reservation_id_alone_does_not_authorize_checkout'
    );
  end if;

  v_row := public.batata_commerce_lock_reservation_ps_checkout(p_reservation_id);
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  end if;

  if (public.batata_commerce_ps_reservation_financial_gate(p_reservation_id)->>'state')
       = 'checkout_active' then
    return jsonb_build_object(
      'ok', false,
      'error', 'checkout_already_active',
      'request_id', p_reservation_id,
      'requested_qty', v_row.requested_qty
    );
  end if;

  v_qty := greatest(coalesce(v_row.requested_qty, p_client_qty, 1), 1);
  v_items := greatest(coalesce(p_unit_cents, 1000), 0) * v_qty;
  begin
    v_ship := public.batata_commerce_shipping_cents(coalesce(p_shipping_method, 'ctt'));
  exception when others then
    v_ship := 350;
  end;
  v_prot := public.batata_commerce_protection_fee_cents(v_items, v_ship);

  insert into public.commerce_checkout_attempts (
    buyer_id, guest_session_id, seller_id, payment_rail, status,
    shipping_method, items_cents, shipping_cents, protection_fee_cents, total_cents,
    currency, live_id, expires_at, client_idempotency_key
  ) values (
    p_buyer_id, case when p_buyer_id is null then v_guest else null end,
    p_seller_id, p_payment_rail, p_status,
    coalesce(p_shipping_method, 'ctt'), v_items, v_ship, v_prot, v_items + v_ship + v_prot,
    'eur', p_live_id, v_expires,
    'p65_locked_' || replace(gen_random_uuid()::text, '-', '')
  ) returning * into v_attempt;

  insert into public.commerce_checkout_holds (
    attempt_id, buyer_id, guest_session_id, seller_id, product_id, live_item_id,
    reservation_request_id, quantity, covers_guaranteed, status, expires_at
  ) values (
    v_attempt.id, p_buyer_id,
    case when p_buyer_id is null then v_guest else null end,
    p_seller_id, p_product_id, coalesce(p_live_item_id, v_row.live_item_id),
    p_reservation_id, v_qty, true, 'active', v_expires
  ) returning id into v_hold_id;

  perform public.batata_commerce_ps_link_checkout_to_reservation(
    p_reservation_id, v_attempt.id, v_guest
  );

  return jsonb_build_object(
    'ok', true,
    'checkout_attempt_id', v_attempt.id,
    'hold_id', v_hold_id,
    'reservation_id', p_reservation_id,
    'client_qty', p_client_qty,
    'snapshot_qty', v_qty,
    'unit_cents', p_unit_cents,
    'items_cents', v_items,
    'shipping_cents', v_ship,
    'protection_fee_cents', v_prot,
    'total_cents', v_items + v_ship + v_prot,
    'status', v_attempt.status,
    'guest_session_id', v_guest,
    'expires_at_reservation', v_row.expires_at,
    'lock', 'commerce_ps_checkout'
  );
end;
$$;

-- Drop old 11-arg overload if signature changed — recreate grants for new 12-arg
revoke all on function public.batata_commerce_ps_locked_checkout_snapshot(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, integer, integer, text, text
) from public;
revoke all on function public.batata_commerce_ps_locked_checkout_snapshot(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, integer, integer, text, text, text
) from public;
grant execute on function public.batata_commerce_ps_locked_checkout_snapshot(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, integer, integer, text, text, text
) to service_role;

notify pgrst, 'reload schema';
