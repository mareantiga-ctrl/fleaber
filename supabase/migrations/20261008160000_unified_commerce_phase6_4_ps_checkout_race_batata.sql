-- =============================================================================
-- BATATA 2026-10-08 — Phase 6.4: PS qty change ↔ checkout begin race
-- Staging only. Production untouched. No Phase 7.
--
-- Root cause (6.3): financial_gate ran BEFORE reservation lock; checkout begin
-- locked products only and snapshotted client qty without locking the reservation.
-- =============================================================================

-- Canonical lock key shared by PS supersede and checkout begin
create or replace function public.batata_commerce_ps_checkout_lock_key(p_reservation_id uuid)
returns integer
language sql
immutable
as $$
  select hashtext(coalesce(p_reservation_id::text, '') || ':commerce_ps_checkout');
$$;

revoke all on function public.batata_commerce_ps_checkout_lock_key(uuid) from public;
grant execute on function public.batata_commerce_ps_checkout_lock_key(uuid) to service_role;

-- Lock one reservation (advisory + row). Call only inside a transaction.
create or replace function public.batata_commerce_lock_reservation_ps_checkout(
  p_reservation_id uuid
)
returns public.live_reservation_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_reservation_requests%rowtype;
begin
  if p_reservation_id is null then
    return null;
  end if;
  perform pg_advisory_xact_lock(
    public.batata_commerce_ps_checkout_lock_key(p_reservation_id)
  );
  select * into v_row
  from public.live_reservation_requests r
  where r.id = p_reservation_id
  for update;
  return v_row;
end;
$$;

revoke all on function public.batata_commerce_lock_reservation_ps_checkout(uuid) from public;
grant execute on function public.batata_commerce_lock_reservation_ps_checkout(uuid)
  to service_role;

-- Lock many reservations in sorted UUID order (deadlock-safe)
create or replace function public.batata_commerce_lock_reservations_ps_checkout(
  p_reservation_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_reservation_ids is null or cardinality(p_reservation_ids) = 0 then
    return;
  end if;
  for v_id in
    select distinct x
    from unnest(p_reservation_ids) as t(x)
    where x is not null
    order by 1
  loop
    perform public.batata_commerce_lock_reservation_ps_checkout(v_id);
  end loop;
end;
$$;

revoke all on function public.batata_commerce_lock_reservations_ps_checkout(uuid[]) from public;
grant execute on function public.batata_commerce_lock_reservations_ps_checkout(uuid[])
  to service_role;

-- Sync checkout lines to locked reservation qty; return adjusted lines + quote delta
create or replace function public.batata_commerce_checkout_sync_lines_under_locks(
  p_lines jsonb
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
  v_client_qty int;
begin
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    if v_req_id is not null and not (v_req_id = any (v_ids)) then
      v_ids := array_append(v_ids, v_req_id);
    end if;
  end loop;

  -- Lock order: reservations first (shared with PS supersede)
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

    v_line_cents := coalesce((v_line->>'line_cents')::int, v_unit * v_qty);
    if v_unit > 0 then
      v_line_cents := v_unit * v_qty;
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

  return jsonb_build_object(
    'ok', true,
    'lines', v_out,
    'items_cents', v_items,
    'qty_changed', v_changed,
    'locked_reservation_ids', to_jsonb(v_ids)
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb) from public;
grant execute on function public.batata_commerce_checkout_sync_lines_under_locks(jsonb)
  to service_role;

-- Staging helper: begin-like checkout under the same reservation lock as PS qty
-- Uses live reservation qty after lock (Result A/B), never trusts stale client qty alone.
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
  p_payment_rail text default 'stripe'
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
  v_guest uuid := p_guest_session_id;
begin
  if p_reservation_id is null or p_seller_id is null or p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if p_buyer_id is null and v_guest is null then
    insert into public.commerce_guest_sessions (token_hash, expires_at)
    values (
      'p64_' || replace(gen_random_uuid()::text, '-', ''),
      timezone('utc', now()) + interval '6 hours'
    )
    returning id into v_guest;
  end if;
  if (p_buyer_id is not null and v_guest is not null)
     or (p_buyer_id is null and v_guest is null) then
    return jsonb_build_object('ok', false, 'error', 'identity_xor');
  end if;

  -- Same lock as try_supersede
  v_row := public.batata_commerce_lock_reservation_ps_checkout(p_reservation_id);
  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'reservation_not_found');
  end if;

  -- If checkout already active under lock → refuse second checkout
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

  insert into public.commerce_checkout_attempts (
    buyer_id, guest_session_id, seller_id, payment_rail, status,
    shipping_method, items_cents, shipping_cents, protection_fee_cents, total_cents,
    currency, live_id, expires_at, client_idempotency_key
  ) values (
    p_buyer_id, case when p_buyer_id is null then v_guest else null end,
    p_seller_id, p_payment_rail, p_status,
    'ctt', v_items, 0, 0, v_items,
    'eur', p_live_id, v_expires,
    'p64_locked_' || replace(gen_random_uuid()::text, '-', '')
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
    'items_cents', v_items,
    'total_cents', v_items,
    'unit_cents', p_unit_cents,
    'status', v_attempt.status,
    'guest_session_id', v_guest,
    'expires_at_reservation', v_row.expires_at,
    'lock', 'commerce_ps_checkout'
  );
end;
$$;

revoke all on function public.batata_commerce_ps_locked_checkout_snapshot(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, integer, integer, text, text
) from public;
grant execute on function public.batata_commerce_ps_locked_checkout_snapshot(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, integer, integer, text, text
) to service_role;

notify pgrst, 'reload schema';
