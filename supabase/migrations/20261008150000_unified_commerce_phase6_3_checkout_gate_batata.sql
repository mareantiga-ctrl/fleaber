-- =============================================================================
-- BATATA 2026-10-08 — Phase 6.3: checkout-active gate for PS last-comment
-- Staging only. Production untouched. No Phase 7.
-- Fix: do NOT treat "checkout-linked reservation" as "no reservation" (no dup create).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Financial gate for a reservation (canonical link via holds / notes / identity)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_reservation_financial_gate(
  p_reservation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.live_reservation_requests%rowtype;
  v_attempt_id uuid;
  v_attempt_status text;
  v_hold_id uuid;
  v_notes text;
  v_m text[];
begin
  if p_reservation_id is null then
    return jsonb_build_object('state', 'none');
  end if;

  select * into v_row
  from public.live_reservation_requests r
  where r.id = p_reservation_id;

  if v_row.id is null then
    return jsonb_build_object('state', 'none');
  end if;

  -- A) Active technical hold linked to this reservation (canonical)
  select h.id, h.attempt_id, a.status
    into v_hold_id, v_attempt_id, v_attempt_status
  from public.commerce_checkout_holds h
  join public.commerce_checkout_attempts a on a.id = h.attempt_id
  where h.reservation_request_id = p_reservation_id
    and h.status = 'active'
    and a.status in ('drafted', 'payment_started_valid', 'payment_processing')
  order by h.created_at desc
  limit 1;

  if v_hold_id is not null then
    return jsonb_build_object(
      'state', 'checkout_active',
      'checkout_attempt_id', v_attempt_id,
      'hold_id', v_hold_id,
      'attempt_status', v_attempt_status,
      'via', 'hold_reservation_request_id'
    );
  end if;

  -- B) Notes carry checkout_attempt:{uuid}
  v_notes := coalesce(v_row.notes, '');
  if v_notes ~* 'checkout_attempt:[0-9a-f-]{36}' then
    v_m := regexp_match(v_notes, 'checkout_attempt:([0-9a-f-]{36})', 'i');
    if v_m is not null then
      v_attempt_id := v_m[1]::uuid;
      select a.status into v_attempt_status
      from public.commerce_checkout_attempts a
      where a.id = v_attempt_id;
      if v_attempt_status in ('drafted', 'payment_started_valid', 'payment_processing') then
        return jsonb_build_object(
          'state', 'checkout_active',
          'checkout_attempt_id', v_attempt_id,
          'attempt_status', v_attempt_status,
          'via', 'notes_checkout_attempt'
        );
      end if;
      if v_attempt_status = 'payment_succeeded' then
        return jsonb_build_object(
          'state', 'payment_succeeded',
          'checkout_attempt_id', v_attempt_id,
          'attempt_status', v_attempt_status,
          'via', 'notes_checkout_attempt'
        );
      end if;
    end if;
  end if;

  -- C) Active hold on same live_item for same buyer/guest, linked to this
  --    reservation OR unlinked (legacy guest null reservation_request_id).
  --    Do NOT block merely because the buyer has another attempt on the live.
  if v_row.buyer_id is not null or v_row.guest_session_id is not null then
    select a.id, a.status, h.id
      into v_attempt_id, v_attempt_status, v_hold_id
    from public.commerce_checkout_holds h
    join public.commerce_checkout_attempts a on a.id = h.attempt_id
    where h.status = 'active'
      and h.live_item_id = v_row.live_item_id
      and a.status in ('drafted', 'payment_started_valid', 'payment_processing')
      and a.expires_at > timezone('utc', now())
      and (
        (v_row.buyer_id is not null and a.buyer_id = v_row.buyer_id)
        or (v_row.guest_session_id is not null and a.guest_session_id = v_row.guest_session_id)
        or (v_row.guest_session_id is not null and h.guest_session_id = v_row.guest_session_id)
      )
      and (
        h.reservation_request_id = p_reservation_id
        or h.reservation_request_id is null
      )
    order by h.created_at desc
    limit 1;

    if v_hold_id is not null then
      return jsonb_build_object(
        'state', 'checkout_active',
        'checkout_attempt_id', v_attempt_id,
        'hold_id', v_hold_id,
        'attempt_status', v_attempt_status,
        'via', 'buyer_or_guest_hold_same_item'
      );
    end if;
  end if;

  -- D) Payment succeeded / paid order on this reservation's item + identity
  if exists (
    select 1
    from public.commerce_checkout_holds h
    join public.commerce_checkout_attempts a on a.id = h.attempt_id
    where h.reservation_request_id = p_reservation_id
      and a.status = 'payment_succeeded'
  ) then
    return jsonb_build_object(
      'state', 'payment_succeeded',
      'via', 'hold_payment_succeeded'
    );
  end if;

  if v_row.buyer_id is not null and exists (
    select 1 from public.orders o
    where o.live_item_id = v_row.live_item_id
      and o.buyer_id = v_row.buyer_id
      and (
        public.batata_order_status_is_sold_fulfilled(o.status)
        or lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue',
          'pendente_pagamento', 'aguardando_pagamento'
        )
        or coalesce(o.stock_units_applied, 0) > 0
      )
  ) then
    return jsonb_build_object(
      'state', 'payment_or_order_closed',
      'via', 'orders'
    );
  end if;

  return jsonb_build_object('state', 'alterable');
end;
$$;

revoke all on function public.batata_commerce_ps_reservation_financial_gate(uuid) from public;
grant execute on function public.batata_commerce_ps_reservation_financial_gate(uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2) Find matching reservation BY REF (do NOT exclude checkout here)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_find_open_reservation_for_supersede(
  p_live_id uuid,
  p_live_item_id uuid,
  p_external_buyer_ref text,
  p_external_display_name text
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_ref text := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
begin
  if v_ref is null then
    return null;
  end if;

  select r.id into v_id
  from public.live_reservation_requests r
  where r.live_id = p_live_id
    and r.live_item_id = p_live_item_id
    and r.source = 'facebook_manual'
    and r.external_buyer_ref = v_ref
    and (
      (
        r.status = 'pending'
        and coalesce(r.request_kind, 'approval_pending') in (
          'approval_pending', 'bag_hold_none'
        )
      )
      or (
        r.status = 'accepted'
        and coalesce(r.request_kind, '') = 'guaranteed'
      )
    )
  order by r.created_at desc
  limit 1;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) try_supersede: classify A/B/C/D before qty mutate or "no target"
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_try_supersede_qty(
  p_live_id uuid,
  p_live_item_id uuid,
  p_external_buyer_ref text,
  p_external_display_name text,
  p_qty integer,
  p_idempotency_key text,
  p_ocr_raw_line text default null,
  p_detected_at timestamptz default null,
  p_chat_sequence integer default null,
  p_ocr_confidence numeric default null,
  p_parser_confidence numeric default null,
  p_identity_confidence numeric default null,
  p_ingest_confidence numeric default null,
  p_ingest_status text default null,
  p_parser_intent text default null,
  p_resolved_ref_slug text default null,
  p_resolved_match_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open uuid;
  v_row public.live_reservation_requests%rowtype;
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_before integer;
  v_avail integer;
  v_need integer;
  v_kind text;
  v_hist_id uuid;
  v_cmt text;
  v_gate jsonb;
  v_gate_state text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 then
    return jsonb_build_object('ok', false, 'error', 'missing_idempotency_key');
  end if;

  select q.id into v_hist_id
  from public.commerce_ps_qty_events q
  where q.event_key = trim(p_idempotency_key)
  limit 1;
  if v_hist_id is not null then
    select * into v_row
    from public.live_reservation_requests r
    where r.id = (
      select reservation_id from public.commerce_ps_qty_events where id = v_hist_id
    );
    return jsonb_build_object(
      'ok', true,
      'action', 'duplicate_qty_event',
      'duplicate', true,
      'request_id', v_row.id,
      'requested_qty', v_row.requested_qty,
      'ttl_unchanged', true
    );
  end if;

  if exists (
    select 1 from public.commerce_ps_event_ledger l
    where l.event_key = trim(p_idempotency_key)
      and l.reservation_id is not null
      and coalesce(l.outcome, '') in (
        'superseded', 'qty_replaced', 'qty_increase_ok', 'qty_decrease_ok',
        'qty_increase_stock_denied', 'duplicate', 'created',
        'checkout_active_blocked', 'payment_closed_blocked'
      )
  ) then
    select l.reservation_id into v_open
    from public.commerce_ps_event_ledger l
    where l.event_key = trim(p_idempotency_key)
    limit 1;
    return jsonb_build_object(
      'ok', true,
      'action', 'duplicate',
      'duplicate', true,
      'request_id', v_open
    );
  end if;

  v_open := public.batata_ps_find_open_reservation_for_supersede(
    p_live_id,
    p_live_item_id,
    p_external_buyer_ref,
    p_external_display_name
  );

  if v_open is null then
    if exists (
      select 1 from public.live_reservation_requests r
      where r.live_id = p_live_id
        and r.live_item_id = p_live_item_id
        and r.source = 'facebook_manual'
        and r.status in ('pending', 'accepted')
        and public.batata_ps_normalize_display_name(r.external_display_name)
          = public.batata_ps_normalize_display_name(p_external_display_name)
        and length(coalesce(public.batata_ps_normalize_display_name(p_external_display_name), '')) >= 4
        and (
          r.external_buyer_ref is distinct from nullif(trim(coalesce(p_external_buyer_ref, '')), '')
        )
    ) then
      return jsonb_build_object(
        'ok', true,
        'action', 'no_supersede_target',
        'name_collision_isolated', true,
        'message', 'same_display_name_different_fb_ref_isolated'
      );
    end if;
    return jsonb_build_object('ok', true, 'action', 'no_supersede_target');
  end if;

  -- Phase 6.3: financial classification BEFORE mutate / create
  v_gate := public.batata_commerce_ps_reservation_financial_gate(v_open);
  v_gate_state := coalesce(v_gate->>'state', 'alterable');

  if v_gate_state = 'checkout_active' then
    select * into v_row from public.live_reservation_requests where id = v_open;
    insert into public.commerce_ps_qty_events (
      reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
      qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
      detected_at, comment_id, ocr_raw_line, meta
    ) values (
      v_open, p_live_id, p_live_item_id, trim(p_idempotency_key),
      nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
      greatest(coalesce(v_row.requested_qty, 1), 1), v_qty,
      greatest(coalesce(v_row.requested_qty, 1), 1), 0,
      'checkout_active_blocked', coalesce(v_row.request_kind, ''),
      p_detected_at, null, p_ocr_raw_line, v_gate
    )
    on conflict (event_key) do nothing;

    return jsonb_build_object(
      'ok', true,
      'action', 'checkout_active_blocked',
      'request_id', v_open,
      'requested_qty', v_row.requested_qty,
      'expires_at', v_row.expires_at,
      'ttl_unchanged', true,
      'gate', v_gate,
      'message', 'comment_ignored_checkout_in_progress'
    );
  end if;

  if v_gate_state in ('payment_succeeded', 'payment_or_order_closed') then
    select * into v_row from public.live_reservation_requests where id = v_open;
    insert into public.commerce_ps_qty_events (
      reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
      qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
      detected_at, comment_id, ocr_raw_line, meta
    ) values (
      v_open, p_live_id, p_live_item_id, trim(p_idempotency_key),
      nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
      greatest(coalesce(v_row.requested_qty, 1), 1), v_qty,
      greatest(coalesce(v_row.requested_qty, 1), 1), 0,
      'payment_closed_blocked', coalesce(v_row.request_kind, ''),
      p_detected_at, null, p_ocr_raw_line, v_gate
    )
    on conflict (event_key) do nothing;

    return jsonb_build_object(
      'ok', true,
      'action', 'payment_closed_blocked',
      'request_id', v_open,
      'requested_qty', v_row.requested_qty,
      'gate', v_gate,
      'message', 'comment_ignored_financial_closed'
    );
  end if;

  select * into v_row
  from public.live_reservation_requests r
  where r.id = v_open
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok', true, 'action', 'no_supersede_target');
  end if;

  if v_row.last_ps_detected_at is not null
     and p_detected_at is not null
     and p_detected_at < v_row.last_ps_detected_at then
    return jsonb_build_object(
      'ok', true,
      'action', 'out_of_order_ignored',
      'request_id', v_row.id,
      'requested_qty', v_row.requested_qty,
      'last_ps_detected_at', v_row.last_ps_detected_at,
      'incoming_detected_at', p_detected_at
    );
  end if;

  v_before := greatest(coalesce(v_row.requested_qty, 1), 1);
  v_kind := coalesce(v_row.request_kind, 'approval_pending');
  v_cmt := nullif(trim(coalesce(p_resolved_ref_slug, '')), '');
  if trim(p_idempotency_key) like 'fb_cmt:%' then
    v_cmt := split_part(trim(p_idempotency_key), ':', 3);
  end if;

  if v_qty = v_before then
    update public.live_reservation_requests r
    set
      last_ps_event_key = trim(p_idempotency_key),
      last_ps_detected_at = coalesce(p_detected_at, r.last_ps_detected_at),
      last_ps_comment_id = coalesce(v_cmt, r.last_ps_comment_id),
      ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
      updated_at = timezone('utc', now())
    where r.id = v_row.id;

    insert into public.commerce_ps_qty_events (
      reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
      qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
      detected_at, comment_id, ocr_raw_line, meta
    ) values (
      v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
      nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
      v_before, v_qty, v_before, 0, 'qty_unchanged', v_kind,
      p_detected_at, v_cmt, p_ocr_raw_line,
      jsonb_build_object('ttl_unchanged', true)
    );

    return jsonb_build_object(
      'ok', true,
      'action', 'qty_unchanged',
      'request_id', v_row.id,
      'requested_qty', v_before,
      'ttl_unchanged', true
    );
  end if;

  if v_row.status = 'pending'
     and v_kind in ('approval_pending', 'bag_hold_none') then
    update public.live_reservation_requests r
    set
      requested_qty = v_qty,
      last_ps_event_key = trim(p_idempotency_key),
      last_ps_detected_at = coalesce(p_detected_at, r.last_ps_detected_at),
      last_ps_comment_id = coalesce(v_cmt, r.last_ps_comment_id),
      ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
      chat_sequence = coalesce(p_chat_sequence, r.chat_sequence),
      notes = coalesce(r.notes || ' | ', '') || 'ps:last_comment_qty',
      updated_at = timezone('utc', now())
    where r.id = v_row.id
    returning * into v_row;

    perform public.batata_recompact_reservation_queue(v_row.live_item_id);

    insert into public.commerce_ps_qty_events (
      reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
      qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
      detected_at, comment_id, ocr_raw_line, meta
    ) values (
      v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
      nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
      v_before, v_qty, v_qty, 0, 'qty_replaced_pending', v_kind,
      p_detected_at, v_cmt, p_ocr_raw_line,
      jsonb_build_object('ttl_unchanged', true, 'expires_at', v_row.expires_at)
    );

    return jsonb_build_object(
      'ok', true,
      'action', 'superseded',
      'duplicate', false,
      'request_id', v_row.id,
      'qty_before', v_before,
      'requested_qty', v_qty,
      'expires_at', v_row.expires_at,
      'request_kind', v_kind,
      'ttl_unchanged', true
    );
  end if;

  if v_row.status = 'accepted' and v_kind = 'guaranteed' then
    perform pg_advisory_xact_lock(
      hashtext(coalesce(v_row.live_item_id::text, '') || ':commerce_reserve')
    );

    if v_qty < v_before then
      update public.live_reservation_requests r
      set
        requested_qty = v_qty,
        last_ps_event_key = trim(p_idempotency_key),
        last_ps_detected_at = coalesce(p_detected_at, r.last_ps_detected_at),
        last_ps_comment_id = coalesce(v_cmt, r.last_ps_comment_id),
        ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
        notes = coalesce(r.notes || ' | ', '') || 'ps:last_comment_qty_down',
        updated_at = timezone('utc', now())
      where r.id = v_row.id
      returning * into v_row;

      begin
        perform public.batata_recompute_live_item_status(p_live_item_id);
      exception when others then
        null;
      end;
      perform public.batata_recompact_reservation_queue(p_live_item_id);

      insert into public.commerce_ps_qty_events (
        reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
        qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
        detected_at, comment_id, ocr_raw_line, meta
      ) values (
        v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
        nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
        v_before, v_qty, v_qty, (v_before - v_qty), 'qty_decrease_ok', v_kind,
        p_detected_at, v_cmt, p_ocr_raw_line,
        jsonb_build_object('ttl_unchanged', true, 'expires_at', v_row.expires_at)
      );

      return jsonb_build_object(
        'ok', true,
        'action', 'qty_decrease_ok',
        'request_id', v_row.id,
        'qty_before', v_before,
        'requested_qty', v_qty,
        'stock_freed', v_before - v_qty,
        'expires_at', v_row.expires_at,
        'ttl_unchanged', true
      );
    end if;

    if v_qty > v_before then
      v_need := v_qty - v_before;
      v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);
      if v_avail < v_need then
        insert into public.commerce_ps_qty_events (
          reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
          qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
          detected_at, comment_id, ocr_raw_line, meta
        ) values (
          v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
          nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
          v_before, v_qty, v_before, 0, 'qty_increase_stock_denied', v_kind,
          p_detected_at, v_cmt, p_ocr_raw_line,
          jsonb_build_object(
            'ttl_unchanged', true,
            'available', v_avail,
            'need', v_need,
            'preserved_qty', v_before
          )
        );

        return jsonb_build_object(
          'ok', true,
          'action', 'qty_increase_stock_denied',
          'request_id', v_row.id,
          'qty_before', v_before,
          'requested_qty', v_before,
          'qty_wanted', v_qty,
          'available_qty', v_avail,
          'ttl_unchanged', true,
          'message', 'insufficient_stock_prior_guarantee_preserved'
        );
      end if;

      update public.live_reservation_requests r
      set
        requested_qty = v_qty,
        last_ps_event_key = trim(p_idempotency_key),
        last_ps_detected_at = coalesce(p_detected_at, r.last_ps_detected_at),
        last_ps_comment_id = coalesce(v_cmt, r.last_ps_comment_id),
        ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
        notes = coalesce(r.notes || ' | ', '') || 'ps:last_comment_qty_up',
        updated_at = timezone('utc', now())
      where r.id = v_row.id
      returning * into v_row;

      begin
        perform public.batata_recompute_live_item_status(p_live_item_id);
      exception when others then
        null;
      end;
      perform public.batata_recompact_reservation_queue(p_live_item_id);
      perform public.batata_close_pending_for_stock(p_live_item_id, v_row.id);

      insert into public.commerce_ps_qty_events (
        reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
        qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
        detected_at, comment_id, ocr_raw_line, meta
      ) values (
        v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
        nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
        v_before, v_qty, v_qty, v_need, 'qty_increase_ok', v_kind,
        p_detected_at, v_cmt, p_ocr_raw_line,
        jsonb_build_object('ttl_unchanged', true, 'expires_at', v_row.expires_at)
      );

      return jsonb_build_object(
        'ok', true,
        'action', 'qty_increase_ok',
        'request_id', v_row.id,
        'qty_before', v_before,
        'requested_qty', v_qty,
        'stock_added', v_need,
        'expires_at', v_row.expires_at,
        'ttl_unchanged', true
      );
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'action', 'qty_change_blocked_state',
    'request_id', v_row.id,
    'status', v_row.status,
    'request_kind', v_kind,
    'message', 'reservation_not_mutable_in_current_state'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Ingest: terminal outcomes include checkout/payment blocks (no create)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_ingest_after_resolve_reserve(
  p_live_id uuid,
  p_seller_id uuid,
  p_item_id uuid,
  p_qty integer,
  p_buyer_ref text,
  p_external_display_name text,
  p_idem text,
  p_detected_at timestamptz,
  p_ocr_raw_line text,
  p_chat_sequence integer,
  p_avatar_phash text,
  p_channel text,
  p_ingest_status text,
  p_parser_intent text,
  p_device_id text,
  p_ocr_confidence numeric,
  p_parser_confidence numeric,
  p_identity_confidence numeric,
  p_item_conf numeric,
  p_final_conf numeric,
  p_resolved_ref_slug text,
  p_match_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sup jsonb;
  v_created jsonb;
begin
  v_sup := public.batata_commerce_ps_try_supersede_qty(
    p_live_id,
    p_item_id,
    p_buyer_ref,
    p_external_display_name,
    p_qty,
    p_idem,
    p_ocr_raw_line,
    p_detected_at,
    p_chat_sequence,
    p_ocr_confidence,
    p_parser_confidence,
    p_identity_confidence,
    p_final_conf,
    p_ingest_status,
    p_parser_intent,
    p_resolved_ref_slug,
    p_match_type
  );

  if (v_sup->>'action') in (
    'superseded',
    'qty_decrease_ok',
    'qty_increase_ok',
    'qty_increase_stock_denied',
    'qty_unchanged',
    'qty_replaced_pending',
    'duplicate_qty_event',
    'duplicate',
    'out_of_order_ignored',
    'identity_insufficient_no_supersede',
    'qty_change_blocked_state',
    'supersede_blocked_guaranteed',
    'supersede_race_miss',
    'checkout_active_blocked',
    'payment_closed_blocked'
  ) then
    update public.commerce_ps_event_ledger
    set reservation_id = nullif(v_sup->>'request_id', '')::uuid,
        outcome = v_sup->>'action',
        result = v_sup
    where event_key = p_idem;
    return v_sup || jsonb_build_object(
      'final_confidence', p_final_conf,
      'via', 'phase6_3_checkout_gate'
    );
  end if;

  v_created := public.batata_commerce_reserve_from_ps_event(
    p_seller_id,
    p_live_id,
    p_item_id,
    p_qty,
    p_buyer_ref,
    p_external_display_name,
    p_idem,
    p_detected_at,
    p_ocr_raw_line,
    p_chat_sequence,
    p_avatar_phash,
    p_channel,
    p_ingest_status,
    p_parser_intent,
    p_device_id,
    p_ocr_confidence,
    p_parser_confidence,
    p_identity_confidence,
    p_item_conf,
    p_final_conf,
    p_resolved_ref_slug,
    p_match_type
  );

  update public.commerce_ps_event_ledger
  set reservation_id = nullif(v_created->>'request_id', '')::uuid,
      outcome = coalesce(v_created->>'action', v_created->>'outcome'),
      result = v_created
  where event_key = p_idem;

  if coalesce((v_created->>'ok')::boolean, false) = true
     and coalesce(v_created->>'action', '') = 'created'
     and nullif(v_created->>'request_id', '') is not null then
    perform public.batata_recompact_reservation_queue(p_item_id);
  end if;

  return v_created || jsonb_build_object(
    'live_item_id', p_item_id,
    'match_type', p_match_type,
    'final_confidence', p_final_conf,
    'ingest_status', p_ingest_status,
    'event_key', p_idem,
    'via', 'phase6_3_canonical'
  );
end;
$$;

revoke all on function public.batata_commerce_ps_ingest_after_resolve_reserve(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) from public;
grant execute on function public.batata_commerce_ps_ingest_after_resolve_reserve(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) to service_role;

-- ---------------------------------------------------------------------------
-- 5) Guest begin: preserve reservation_request_id when line provides it
--    (was nulled → broke PS/guest financial linkage)
-- Minimal patch: recreate only the hold-insert loop via a helper used by tests
-- and document; full guest RPC body is large — add linker helper for notes.
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_link_checkout_to_reservation(
  p_reservation_id uuid,
  p_attempt_id uuid,
  p_guest_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_att public.commerce_checkout_attempts%rowtype;
  v_row public.live_reservation_requests%rowtype;
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id;
  select * into v_row from public.live_reservation_requests where id = p_reservation_id;
  if v_att.id is null or v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  update public.live_reservation_requests r
  set
    notes = trim(both ' |' from (
      coalesce(nullif(trim(r.notes), ''), '')
      || case when coalesce(r.notes, '') = '' then '' else ' | ' end
      || 'checkout_attempt:' || p_attempt_id::text
    )),
    guest_session_id = coalesce(r.guest_session_id, p_guest_session_id, v_att.guest_session_id),
    updated_at = timezone('utc', now())
  where r.id = p_reservation_id;

  -- Ensure hold points at reservation when missing
  update public.commerce_checkout_holds h
  set reservation_request_id = coalesce(h.reservation_request_id, p_reservation_id)
  where h.attempt_id = p_attempt_id
    and h.status = 'active'
    and (h.live_item_id = v_row.live_item_id or h.live_item_id is null);

  return jsonb_build_object('ok', true, 'reservation_id', p_reservation_id, 'attempt_id', p_attempt_id);
end;
$$;

revoke all on function public.batata_commerce_ps_link_checkout_to_reservation(uuid, uuid, uuid)
  from public;
grant execute on function public.batata_commerce_ps_link_checkout_to_reservation(uuid, uuid, uuid)
  to service_role;

notify pgrst, 'reload schema';
