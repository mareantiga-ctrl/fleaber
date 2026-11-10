-- =============================================================================
-- BATATA 2026-10-06 — Phase 4 revalidate + atomic begin
-- =============================================================================

-- Line availability helper (same product lock as checkout_available)
create or replace function public.batata_commerce_line_availability(
  p_product_id uuid,
  p_need_qty integer,
  p_buyer_id uuid,
  p_reservation_request_id uuid default null,
  p_exclude_order_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_need int := greatest(coalesce(p_need_qty, 1), 1);
  v_check jsonb;
  v_req public.live_reservation_requests%rowtype;
  v_guaranteed boolean := false;
begin
  if p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_product', 'available', false);
  end if;

  if p_reservation_request_id is not null then
    select * into v_req from public.live_reservation_requests where id = p_reservation_request_id;
    if v_req.id is not null
       and v_req.buyer_id is not distinct from p_buyer_id
       and lower(trim(coalesce(v_req.status, ''))) = 'accepted'
       and (
         v_req.expires_at is null
         or v_req.expires_at > timezone('utc', now())
       ) then
      v_guaranteed := true;
    end if;
  end if;

  if v_guaranteed then
    -- Guaranteed already blocks stock for this buyer — line remains payable.
    return jsonb_build_object(
      'ok', true,
      'available', true,
      'guaranteed', true,
      'need', v_need,
      'reason', 'guaranteed_hold'
    );
  end if;

  v_check := public.batata_product_checkout_available(
    p_product_id,
    null,
    v_need,
    p_exclude_order_ids
  );

  return jsonb_build_object(
    'ok', coalesce((v_check->>'ok')::boolean, false),
    'available', coalesce((v_check->>'ok')::boolean, false),
    'guaranteed', false,
    'need', v_need,
    'stock', v_check->'stock',
    'held', v_check->'held',
    'available_qty', v_check->'available',
    'reason', case
      when coalesce((v_check->>'ok')::boolean, false) then 'stock_ok'
      else coalesce(v_check->>'error', 'stock_insufficient')
    end
  );
end;
$$;

revoke all on function public.batata_commerce_line_availability(uuid, integer, uuid, uuid, uuid[])
  from public;
grant execute on function public.batata_commerce_line_availability(uuid, integer, uuid, uuid, uuid[])
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- REVALIDATE (read-only for buyer) — no charge, no holds
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_checkout_revalidate(
  p_lines jsonb,
  p_shipping_method text,
  p_seller_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_line jsonb;
  v_avail jsonb := '[]'::jsonb;
  v_unavail jsonb := '[]'::jsonb;
  v_items_cents int := 0;
  v_ship_cents int;
  v_prot_cents int;
  v_total_cents int;
  v_seller uuid := p_seller_id;
  v_product_id uuid;
  v_live_item_id uuid;
  v_req_id uuid;
  v_qty int;
  v_unit_cents int;
  v_line_cents int;
  v_check jsonb;
  v_price numeric;
  v_bag_changed boolean := false;
  v_idx int := 0;
  v_pseller uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    if v_role is distinct from 'service_role' then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;
  if v_role = 'service_role' and v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'buyer_required');
  end if;

  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) < 1 then
    return jsonb_build_object('ok', false, 'error', 'empty_lines');
  end if;

  begin
    v_ship_cents := public.batata_commerce_shipping_cents(p_shipping_method);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'invalid_shipping_method');
  end;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_idx := v_idx + 1;
    v_product_id := nullif(trim(coalesce(v_line->>'product_id', '')), '')::uuid;
    v_live_item_id := nullif(trim(coalesce(v_line->>'live_item_id', '')), '')::uuid;
    v_req_id := nullif(trim(coalesce(v_line->>'reservation_request_id', '')), '')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);

    if v_product_id is null and v_live_item_id is not null then
      select coalesce(product_id, checkout_product_id) into v_product_id
      from public.live_items where id = v_live_item_id;
    end if;

    if v_product_id is null then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'reason', 'missing_product',
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id
      ));
      continue;
    end if;

    -- Seller boundary
    select seller_id into v_pseller from public.products where id = v_product_id;
    if v_seller is null then
      v_seller := v_pseller;
    elsif v_pseller is distinct from v_seller then
      return jsonb_build_object('ok', false, 'error', 'multi_seller_bag');
    end if;

    select price into v_price from public.products where id = v_product_id;
    if v_price is null or v_price <= 0 then
      -- live_item price fallback
      if v_live_item_id is not null then
        select price into v_price from public.live_items where id = v_live_item_id;
      end if;
    end if;
    if v_price is null or v_price <= 0 then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'reason', 'missing_price'
      ));
      continue;
    end if;

    v_unit_cents := round(v_price * 100)::int;
    v_line_cents := v_unit_cents * v_qty;

    v_check := public.batata_commerce_line_availability(
      v_product_id, v_qty, v_uid, v_req_id, null
    );

    if coalesce((v_check->>'available')::boolean, false) then
      v_items_cents := v_items_cents + v_line_cents;
      v_avail := v_avail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'unit_cents', v_unit_cents,
        'line_cents', v_line_cents,
        'guaranteed', coalesce((v_check->>'guaranteed')::boolean, false)
      ));
    else
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'reason', coalesce(v_check->>'reason', 'unavailable')
      ));
    end if;
  end loop;

  if jsonb_array_length(v_avail) = 0 then
    return jsonb_build_object(
      'ok', true,
      'bag_changed', true,
      'all_unavailable', true,
      'available_lines', v_avail,
      'unavailable_lines', v_unavail,
      'seller_id', v_seller,
      'quote', jsonb_build_object(
        'items_cents', 0,
        'shipping_cents', 0,
        'protection_fee_cents', 0,
        'total_cents', 0
      )
    );
  end if;

  -- Shipping only if at least one available line remains
  v_prot_cents := public.batata_commerce_protection_fee_cents(v_items_cents, v_ship_cents);
  v_total_cents := v_items_cents + v_ship_cents + v_prot_cents;

  return jsonb_build_object(
    'ok', true,
    'bag_changed', v_bag_changed,
    'all_unavailable', false,
    'available_lines', v_avail,
    'unavailable_lines', v_unavail,
    'seller_id', v_seller,
    'shipping_method', p_shipping_method,
    'quote', jsonb_build_object(
      'items_cents', v_items_cents,
      'shipping_cents', v_ship_cents,
      'protection_fee_cents', v_prot_cents,
      'total_cents', v_total_cents
    )
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid) from public;
grant execute on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- BEGIN — atomic holds + orders + attempt (confirmed available lines only)
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_checkout_begin(
  p_lines jsonb,
  p_shipping_method text,
  p_payment_rail text,
  p_delivery jsonb default '{}'::jsonb,
  p_live_id uuid default null,
  p_client_idempotency_key text default null,
  p_confirm_remainder boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_rail text := lower(trim(coalesce(p_payment_rail, '')));
  v_ceiling interval;
  v_attempt public.commerce_checkout_attempts%rowtype;
  v_reval jsonb;
  v_lines jsonb;
  v_line jsonb;
  v_seller uuid;
  v_ship_cents int;
  v_items_cents int := 0;
  v_prot_cents int;
  v_total_cents int;
  v_expires timestamptz;
  v_order_ids uuid[] := array[]::uuid[];
  v_product_ids uuid[] := array[]::uuid[];
  v_pid uuid;
  v_liid uuid;
  v_req_id uuid;
  v_qty int;
  v_unit_cents int;
  v_line_cents int;
  v_check jsonb;
  v_guaranteed boolean;
  v_order_id uuid;
  v_hold_id uuid;
  v_price numeric;
  v_pm text;
  v_existing uuid;
  v_snap_at timestamptz;
  v_lock_row record;
  v_line_live_id uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if v_rail not in ('stripe', 'off_platform') then
    return jsonb_build_object('ok', false, 'error', 'invalid_payment_rail');
  end if;

  v_ceiling := case when v_rail = 'off_platform' then interval '15 minutes'
                    else interval '30 minutes' end;

  -- Idempotent retry: same buyer + key → return existing open attempt
  if coalesce(trim(p_client_idempotency_key), '') <> '' then
    select id into v_existing
    from public.commerce_checkout_attempts
    where buyer_id = v_uid
      and client_idempotency_key = trim(p_client_idempotency_key)
      and status in ('drafted', 'payment_started_valid', 'payment_processing')
      and expires_at > timezone('utc', now())
    order by created_at desc
    limit 1;
    if v_existing is not null then
      select * into v_attempt from public.commerce_checkout_attempts where id = v_existing;
      select coalesce(array_agg(id), array[]::uuid[]) into v_order_ids
      from public.orders where checkout_attempt_id = v_existing;
      return jsonb_build_object(
        'ok', true,
        'reused', true,
        'checkout_attempt_id', v_attempt.id,
        'status', v_attempt.status,
        'order_ids', to_jsonb(v_order_ids),
        'expires_at', v_attempt.expires_at,
        'quote', jsonb_build_object(
          'items_cents', v_attempt.items_cents,
          'shipping_cents', v_attempt.shipping_cents,
          'protection_fee_cents', v_attempt.protection_fee_cents,
          'total_cents', v_attempt.total_cents
        )
      );
    end if;
  end if;

  v_reval := public.batata_commerce_checkout_revalidate(p_lines, p_shipping_method, null);
  if coalesce((v_reval->>'ok')::boolean, false) is not true then
    return v_reval;
  end if;
  if coalesce((v_reval->>'all_unavailable')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'all_unavailable',
      'revalidation', v_reval
    );
  end if;
  if coalesce((v_reval->>'bag_changed')::boolean, false)
     and not coalesce(p_confirm_remainder, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'bag_changed_confirmation_required',
      'revalidation', v_reval
    );
  end if;

  v_lines := v_reval->'available_lines';
  v_seller := nullif(v_reval->>'seller_id', '')::uuid;
  v_ship_cents := coalesce((v_reval->'quote'->>'shipping_cents')::int, 0);
  v_items_cents := coalesce((v_reval->'quote'->>'items_cents')::int, 0);
  v_prot_cents := coalesce((v_reval->'quote'->>'protection_fee_cents')::int, 0);
  v_total_cents := coalesce((v_reval->'quote'->>'total_cents')::int, 0);
  v_expires := timezone('utc', now()) + v_ceiling;
  v_pm := case when v_rail = 'stripe' then 'Pagamento na App'
               else 'Pagamento Direto ao Vendedor (MB WAY/Transf)' end;

  -- Collect product ids and lock in sorted order (deadlock-safe)
  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    if v_pid is not null and not (v_pid = any (v_product_ids)) then
      v_product_ids := array_append(v_product_ids, v_pid);
    end if;
  end loop;

  for v_lock_row in
    select unnest(v_product_ids) as pid order by 1
  loop
    perform pg_advisory_xact_lock(hashtext(v_lock_row.pid::text || ':checkout_stock'));
    perform 1 from public.products p where p.id = v_lock_row.pid for update;
  end loop;

  -- Re-check each line under locks
  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    v_check := public.batata_commerce_line_availability(
      v_pid, v_qty, v_uid, v_req_id, null
    );
    if not coalesce((v_check->>'available')::boolean, false) then
      return jsonb_build_object(
        'ok', false,
        'error', 'stock_race_lost',
        'product_id', v_pid,
        'revalidation', public.batata_commerce_checkout_revalidate(p_lines, p_shipping_method, v_seller)
      );
    end if;
  end loop;

  v_snap_at := case
    when coalesce(nullif(trim(p_delivery->>'line1'), ''), '') <> ''
      or coalesce(nullif(trim(p_delivery->>'recipient_name'), ''), '') <> ''
    then timezone('utc', now())
    else null
  end;

  insert into public.commerce_checkout_attempts (
    buyer_id, seller_id, payment_rail, status,
    shipping_method, items_cents, shipping_cents, protection_fee_cents, total_cents,
    live_id, client_idempotency_key, expires_at,
    delivery_recipient_name, delivery_line1, delivery_line2, delivery_postal_code,
    delivery_city, delivery_country, delivery_phone,
    delivery_point_ref, delivery_point_provider, delivery_point_label,
    delivery_snapshot_at
  ) values (
    v_uid, v_seller, v_rail, 'payment_started_valid',
    p_shipping_method, v_items_cents, v_ship_cents, v_prot_cents, v_total_cents,
    p_live_id, nullif(trim(p_client_idempotency_key), ''), v_expires,
    nullif(trim(p_delivery->>'recipient_name'), ''),
    nullif(trim(p_delivery->>'line1'), ''),
    nullif(trim(p_delivery->>'line2'), ''),
    nullif(trim(p_delivery->>'postal_code'), ''),
    nullif(trim(p_delivery->>'city'), ''),
    nullif(trim(p_delivery->>'country'), ''),
    nullif(trim(p_delivery->>'phone'), ''),
    nullif(trim(p_delivery->>'point_ref'), ''),
    nullif(trim(p_delivery->>'point_provider'), ''),
    nullif(trim(p_delivery->>'point_label'), ''),
    v_snap_at
  ) returning * into v_attempt;

  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    v_liid := nullif(v_line->>'live_item_id', '')::uuid;
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    v_unit_cents := coalesce((v_line->>'unit_cents')::int, 0);
    v_line_cents := coalesce((v_line->>'line_cents')::int, v_unit_cents * v_qty);
    v_guaranteed := coalesce((v_line->>'guaranteed')::boolean, false);
    v_line_live_id := p_live_id;
    if v_liid is not null then
      select live_id into v_line_live_id from public.live_items where id = v_liid;
      v_line_live_id := coalesce(v_line_live_id, p_live_id);
    end if;

    insert into public.orders (
      product_id, buyer_id, seller_id, price_total, shipping_method, payment_method,
      status, is_reservation, quantity, live_id, live_item_id,
      checkout_attempt_id,
      delivery_recipient_name, delivery_line1, delivery_line2, delivery_postal_code,
      delivery_city, delivery_country, delivery_phone,
      delivery_point_ref, delivery_point_provider, delivery_point_label,
      delivery_snapshot_at
    ) values (
      v_pid, v_uid, v_seller,
      (v_line_cents::numeric / 100.0),
      p_shipping_method, v_pm,
      'reserva_pendente', false, v_qty, v_line_live_id, v_liid,
      v_attempt.id,
      v_attempt.delivery_recipient_name, v_attempt.delivery_line1, v_attempt.delivery_line2,
      v_attempt.delivery_postal_code, v_attempt.delivery_city, v_attempt.delivery_country,
      v_attempt.delivery_phone, v_attempt.delivery_point_ref, v_attempt.delivery_point_provider,
      v_attempt.delivery_point_label, v_attempt.delivery_snapshot_at
    ) returning id into v_order_id;

    v_order_ids := array_append(v_order_ids, v_order_id);

    -- Hold AFTER order so capacity trigger does not see hold+order double debit.
    insert into public.commerce_checkout_holds (
      attempt_id, buyer_id, seller_id, product_id, live_item_id,
      reservation_request_id, quantity, covers_guaranteed, status, expires_at
    ) values (
      v_attempt.id, v_uid, v_seller, v_pid, v_liid,
      v_req_id, v_qty, v_guaranteed, 'active', v_expires
    ) returning id into v_hold_id;

    -- Tag LRR with stripe_checkout / attempt for payment_in_progress detector
    if v_req_id is not null then
      update public.live_reservation_requests lrr
      set notes = trim(both ' |' from (
            coalesce(nullif(trim(lrr.notes), ''), '')
            || case when coalesce(lrr.notes, '') = '' then '' else ' | ' end
            || 'stripe_checkout:' || v_order_id::text
            || ' | checkout_attempt:' || v_attempt.id::text
          )),
          updated_at = timezone('utc', now())
      where lrr.id = v_req_id
        and lrr.buyer_id = v_uid;
    end if;
  end loop;

  update public.commerce_checkout_attempts
  set status = 'payment_processing', updated_at = timezone('utc', now())
  where id = v_attempt.id;

  return jsonb_build_object(
    'ok', true,
    'reused', false,
    'checkout_attempt_id', v_attempt.id,
    'status', 'payment_processing',
    'order_ids', to_jsonb(v_order_ids),
    'expires_at', v_expires,
    'payment_rail', v_rail,
    'seller_id', v_seller,
    'quote', jsonb_build_object(
      'items_cents', v_items_cents,
      'shipping_cents', v_ship_cents,
      'protection_fee_cents', v_prot_cents,
      'total_cents', v_total_cents
    ),
    'bag_changed', coalesce((v_reval->>'bag_changed')::boolean, false),
    'unavailable_lines', coalesce(v_reval->'unavailable_lines', '[]'::jsonb)
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_begin(jsonb, text, text, jsonb, uuid, text, boolean)
  from public;
grant execute on function public.batata_commerce_checkout_begin(jsonb, text, text, jsonb, uuid, text, boolean)
  to authenticated, service_role;

notify pgrst, 'reload schema';
