-- =============================================================================
-- BATATA 2026-10-08 — Phase 6.2: last-comment-wins qty + FB identity isolation
-- Staging only. Production untouched. No Phase 7.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) History + tracking columns
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_ps_qty_events (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.live_reservation_requests(id),
  live_id uuid not null,
  live_item_id uuid not null,
  event_key text not null,
  external_buyer_ref text null,
  qty_before integer not null,
  qty_requested integer not null,
  qty_after integer not null,
  stock_delta integer not null default 0,
  outcome text not null,
  request_kind text null,
  detected_at timestamptz null,
  comment_id text null,
  ocr_raw_line text null,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists commerce_ps_qty_events_event_key_uidx
  on public.commerce_ps_qty_events (event_key);

create index if not exists commerce_ps_qty_events_reservation_idx
  on public.commerce_ps_qty_events (reservation_id, created_at desc);

alter table public.commerce_ps_qty_events enable row level security;
revoke all on table public.commerce_ps_qty_events from public, anon, authenticated;
grant select, insert on table public.commerce_ps_qty_events to service_role;

alter table public.live_reservation_requests
  add column if not exists last_ps_event_key text,
  add column if not exists last_ps_detected_at timestamptz,
  add column if not exists last_ps_comment_id text;

comment on column public.live_reservation_requests.last_ps_event_key is
  'Phase 6.2: last applied PS comment event_key (idempotency of that comment stays in ledger).';

-- ---------------------------------------------------------------------------
-- 2) Stable buyer match — NEVER by display name alone when fb: refs exist
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_same_buyer(
  p_row_ref text,
  p_row_name text,
  p_event_ref text,
  p_event_name text
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_row_ref text := nullif(trim(coalesce(p_row_ref, '')), '');
  v_evt_ref text := nullif(trim(coalesce(p_event_ref, '')), '');
begin
  -- Prefer stable Face/OCR refs. Name alone never proves identity across two fb: ids.
  if v_row_ref is not null and v_evt_ref is not null then
    return v_row_ref = v_evt_ref;
  end if;

  -- Both missing stable ref (legacy OCR sess / anonymous): refuse cross-person
  -- association by name — return false so we do not supersede.
  -- (Creating a new pending row is safer than mutating someone else's.)
  if v_row_ref is null and v_evt_ref is null then
    return false;
  end if;

  -- One side has ref, other does not → not the same verified buyer
  return false;
end;
$$;

revoke all on function public.batata_commerce_ps_same_buyer(text, text, text, text) from public;
grant execute on function public.batata_commerce_ps_same_buyer(text, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 3) Find open reservation for last-comment qty replace (pending OR guaranteed)
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
  -- Phase 6.2: require stable external_buyer_ref. No name fallback.
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
    -- Checkout / payment safety
    and not exists (
      select 1 from public.commerce_checkout_attempts a
      where a.live_id = r.live_id
        and (
          (r.buyer_id is not null and a.buyer_id = r.buyer_id)
          or (a.guest_session_id is not null and a.guest_session_id = r.guest_session_id)
        )
        and coalesce(lower(trim(a.status)), '') in (
          'open', 'pending', 'processing', 'requires_action', 'awaiting_payment'
        )
        and a.created_at > now() - interval '2 hours'
    )
    and not exists (
      select 1 from public.orders o
      where o.live_item_id = r.live_item_id
        and r.buyer_id is not null
        and o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or lower(trim(coalesce(o.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue',
            'pendente_pagamento', 'aguardando_pagamento'
          )
          or coalesce(o.stock_units_applied, 0) > 0
        )
    )
  order by r.created_at desc
  limit 1;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Canonical qty replace (last comment wins) — pending + guaranteed
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
  v_delta integer;
  v_kind text;
  v_hist_id uuid;
  v_cmt text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 then
    return jsonb_build_object('ok', false, 'error', 'missing_idempotency_key');
  end if;

  -- Already applied this exact comment/event?
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

  -- Also: if ledger already completed this event onto a reservation
  if exists (
    select 1 from public.commerce_ps_event_ledger l
    where l.event_key = trim(p_idempotency_key)
      and l.reservation_id is not null
      and coalesce(l.outcome, '') in (
        'superseded', 'qty_replaced', 'qty_increase_ok', 'qty_decrease_ok',
        'qty_increase_stock_denied', 'duplicate', 'created'
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
    -- Name collision is informational only: NEVER mutate the other buyer's row.
    -- Still return no_supersede_target so THIS buyer can create their own reservation.
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

  select * into v_row
  from public.live_reservation_requests r
  where r.id = v_open
  for update;

  if v_row.id is null then
    return jsonb_build_object('ok', true, 'action', 'no_supersede_target');
  end if;

  -- Out-of-order: older comment must not override newer applied intent
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

  -- Extract comment id from event key when fb_cmt:
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

  -- PENDING / bag_hold_none: qty replace, no stock lock, TTL untouched
  if v_row.status = 'pending'
     and v_kind in ('approval_pending', 'bag_hold_none') then
    update public.live_reservation_requests r
    set
      requested_qty = v_qty,
      -- NEVER touch expires_at / policy snapshots / idempotency_key (history via qty_events)
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

  -- GUARANTEED accepted: transactional qty change without TTL reset
  if v_row.status = 'accepted' and v_kind = 'guaranteed' then
    perform pg_advisory_xact_lock(
      hashtext(coalesce(v_row.live_item_id::text, '') || ':commerce_reserve')
    );

    if v_qty < v_before then
      -- Reduce: free stock immediately
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

      v_delta := v_qty - v_before; -- negative
      insert into public.commerce_ps_qty_events (
        reservation_id, live_id, live_item_id, event_key, external_buyer_ref,
        qty_before, qty_requested, qty_after, stock_delta, outcome, request_kind,
        detected_at, comment_id, ocr_raw_line, meta
      ) values (
        v_row.id, p_live_id, p_live_item_id, trim(p_idempotency_key),
        nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
        v_before, v_qty, v_qty, v_delta, 'qty_decrease_ok', v_kind,
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

    -- Increase: need extra free stock (engine avail already excludes this hold)
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
          'needed', v_need,
          'preserved_qty', v_before
        )
      );

      -- Still stamp last event so retries of THIS comment are duplicates,
      -- but do not mark older comments blocked.
      update public.live_reservation_requests r
      set
        last_ps_event_key = trim(p_idempotency_key),
        last_ps_detected_at = coalesce(p_detected_at, r.last_ps_detected_at),
        last_ps_comment_id = coalesce(v_cmt, r.last_ps_comment_id),
        updated_at = timezone('utc', now())
      where r.id = v_row.id;

      return jsonb_build_object(
        'ok', true,
        'action', 'qty_increase_stock_denied',
        'request_id', v_row.id,
        'qty_before', v_before,
        'qty_requested', v_qty,
        'requested_qty', v_before,
        'available_extra', v_avail,
        'needed_extra', v_need,
        'preserved', true,
        'ttl_unchanged', true,
        'expires_at', v_row.expires_at
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
-- 5) Ingest after-resolve: treat all qty/identity terminal actions as final
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

  -- Terminal last-comment outcomes — never create a second reservation row
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
    'supersede_race_miss'
  ) then
    update public.commerce_ps_event_ledger
    set reservation_id = nullif(v_sup->>'request_id', '')::uuid,
        outcome = v_sup->>'action',
        result = v_sup
    where event_key = p_idem;
    return v_sup || jsonb_build_object(
      'final_confidence', p_final_conf,
      'via', 'phase6_2_last_comment'
    );
  end if;

  -- no supersede target → create via canonical engine
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
    'via', 'phase6_2_canonical'
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

notify pgrst, 'reload schema';
