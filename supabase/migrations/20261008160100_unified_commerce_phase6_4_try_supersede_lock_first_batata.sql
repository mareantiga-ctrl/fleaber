-- Phase 6.4: try_supersede locks reservation before financial gate

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

  -- Phase 6.4: lock reservation BEFORE financial gate (shared with checkout begin)
  v_row := public.batata_commerce_lock_reservation_ps_checkout(v_open);
  if v_row.id is null then
    return jsonb_build_object('ok', true, 'action', 'no_supersede_target');
  end if;

  v_gate := public.batata_commerce_ps_reservation_financial_gate(v_open);
  v_gate_state := coalesce(v_gate->>'state', 'alterable');

  if v_gate_state = 'checkout_active' then
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

  -- already locked above (6.4)
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


notify pgrst, 'reload schema';
