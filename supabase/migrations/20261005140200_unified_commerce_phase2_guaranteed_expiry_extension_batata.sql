-- =============================================================================
-- BATATA 2026-10-05 — Fase 2: guaranteed expiry + payment grace + extension + promote
-- Sem alterar Stripe / Ifthenpay / MB WAY. Usa sinais já existentes (notes + orders).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) Payment-in-progress detector (no PSP schema changes)
-- -----------------------------------------------------------------------------
create or replace function public.batata_lrr_payment_in_progress(
  p_request_id uuid,
  p_now timestamptz default timezone('utc', now())
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_order_id uuid;
  v_ord public.orders%rowtype;
  v_stripe_ceiling interval := interval '30 minutes';
  v_mbway_ceiling interval := interval '15 minutes';
  v_ceiling interval;
  v_method text;
  v_started timestamptz;
begin
  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'in_progress', false, 'error', 'not_found');
  end if;

  -- Parse stripe_checkout:<order_uuid> from notes
  begin
    v_order_id := substring(coalesce(v_req.notes, '') from 'stripe_checkout:([0-9a-fA-F-]{36})')::uuid;
  exception when others then
    v_order_id := null;
  end;

  if v_order_id is not null then
    select * into v_ord from public.orders where id = v_order_id;
  end if;

  -- Fallback: open prepay order for same buyer+item
  if v_ord.id is null and v_req.buyer_id is not null then
    select * into v_ord
    from public.orders o
    where o.buyer_id = v_req.buyer_id
      and (
        o.live_item_id = v_req.live_item_id
        or (
          o.live_id = v_req.live_id
          and o.product_id is not null
          and exists (
            select 1 from public.live_items li
            where li.id = v_req.live_item_id
              and coalesce(li.product_id, li.checkout_product_id) = o.product_id
          )
        )
      )
      and lower(trim(coalesce(o.status, ''))) in (
        'reserva_pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'pendente'
      )
    order by o.created_at desc nulls last
    limit 1;
  end if;

  if v_ord.id is null then
    -- Tag present but order gone / not linked → treat as not in progress
    if v_req.notes ilike '%stripe_checkout:%' then
      return jsonb_build_object(
        'ok', true,
        'in_progress', false,
        'reason', 'checkout_tag_without_open_order'
      );
    end if;
    return jsonb_build_object('ok', true, 'in_progress', false, 'reason', 'no_payment_signal');
  end if;

  -- Already paid / fulfilled → not "unpaid expiry" path (caller should not fail trust)
  if public.batata_order_status_is_sold_fulfilled(v_ord.status)
     or lower(trim(coalesce(v_ord.status, ''))) in ('pago', 'enviado', 'entregue', 'concluido') then
    return jsonb_build_object(
      'ok', true,
      'in_progress', true,
      'reason', 'already_paid_or_fulfilled',
      'order_id', v_ord.id,
      'protect', true,
      'no_trust_failure', true
    );
  end if;

  if lower(trim(coalesce(v_ord.status, ''))) in ('cancelado', 'cancelled', 'rejected', 'expired') then
    return jsonb_build_object(
      'ok', true,
      'in_progress', false,
      'reason', 'order_terminal_cancelled',
      'order_id', v_ord.id
    );
  end if;

  v_method := lower(trim(coalesce(v_ord.payment_method, '')));
  if v_method like '%mb%way%' or v_method like '%ifthen%' or v_method = 'mbway' then
    v_ceiling := v_mbway_ceiling;
  else
    v_ceiling := v_stripe_ceiling;
  end if;

  -- orders has created_at (no updated_at); fall back to LRR updated_at
  v_started := coalesce(v_ord.created_at, v_req.updated_at);

  -- Legitimate processing: open prepay status + (PI/session id OR within ceiling)
  if lower(trim(coalesce(v_ord.status, ''))) in (
       'reserva_pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'pendente'
     )
     and (
       coalesce(nullif(trim(v_ord.stripe_payment_intent_id), ''), '') <> ''
       or coalesce(nullif(trim(v_ord.stripe_checkout_session_id), ''), '') <> ''
       or (v_started is not null and v_started > p_now - v_ceiling)
       or v_req.notes ilike '%stripe_checkout:%'
     )
  then
    -- Still within ceiling from start
    if v_started is not null and v_started <= p_now - v_ceiling
       and coalesce(nullif(trim(v_ord.stripe_payment_intent_id), ''), '') = ''
       and coalesce(nullif(trim(v_ord.stripe_checkout_session_id), ''), '') = ''
       and v_req.notes not ilike '%stripe_checkout:%'
    then
      return jsonb_build_object(
        'ok', true,
        'in_progress', false,
        'reason', 'prepay_stale_beyond_ceiling',
        'order_id', v_ord.id
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'in_progress', true,
      'reason', 'legitimate_payment_processing',
      'order_id', v_ord.id,
      'hold_until', v_started + v_ceiling,
      'protect', true,
      'no_trust_failure', true
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'in_progress', false,
    'reason', 'no_active_processing',
    'order_id', v_ord.id
  );
end;
$$;

revoke all on function public.batata_lrr_payment_in_progress(uuid, timestamptz) from public;
grant execute on function public.batata_lrr_payment_in_progress(uuid, timestamptz)
  to service_role;

-- -----------------------------------------------------------------------------
-- B) Expire guaranteed holds safely
-- -----------------------------------------------------------------------------
create or replace function public.batata_expire_guaranteed_reservations(
  p_now timestamptz default timezone('utc', now())
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_pay jsonb;
  v_expired integer := 0;
  v_deferred integer := 0;
  v_failures integer := 0;
  v_hold_until timestamptz;
  v_fail jsonb;
begin
  perform set_config('batata.allow_internal_live_ops', '1', true);

  for r in
    select *
    from public.live_reservation_requests
    where status = 'accepted'
      and expires_at is not null
      and expires_at < p_now
    for update skip locked
  loop
    v_pay := public.batata_lrr_payment_in_progress(r.id, p_now);

    if coalesce((v_pay->>'in_progress')::boolean, false) then
      v_hold_until := nullif(v_pay->>'hold_until', '')::timestamptz;
      if v_hold_until is not null and v_hold_until > r.expires_at then
        update public.live_reservation_requests
        set
          expires_at = v_hold_until,
          notes = trim(both ' |' from coalesce(notes, '') || ' | payment_grace'),
          updated_at = p_now
        where id = r.id;
      end if;
      -- Do NOT release stock; do NOT emit trust failure
      v_deferred := v_deferred + 1;
      continue;
    end if;

    update public.live_reservation_requests
    set
      status = 'expired',
      expiry_reason = 'guaranteed_hold_expired_unpaid',
      notes = trim(both ' |' from coalesce(notes, '') || ' | guaranteed_auto_expired'),
      updated_at = p_now
    where id = r.id
      and status = 'accepted';

    if found then
      v_expired := v_expired + 1;
      perform public.batata_commerce_emit_reservation_event(
        r.id,
        'guaranteed_expired',
        jsonb_build_object('expiry_reason', 'guaranteed_hold_expired_unpaid')
      );

      -- Buyer-responsible failure only when they had a real guarantee and abandoned
      if r.buyer_id is not null then
        v_fail := public.batata_buyer_trust_record_failure(
          r.buyer_id,
          'live_reservation_request',
          r.id::text,
          'guaranteed_hold_expired_unpaid',
          jsonb_build_object('live_item_id', r.live_item_id, 'seller_id', r.seller_id)
        );
        if coalesce((v_fail->>'inserted')::boolean, false) then
          v_failures := v_failures + 1;
        end if;
      end if;

      begin
        perform public.batata_recompute_live_item_status(r.live_item_id);
      exception when others then
        null;
      end;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'expired', v_expired,
    'payment_deferred', v_deferred,
    'failures_recorded', v_failures
  );
end;
$$;

revoke all on function public.batata_expire_guaranteed_reservations(timestamptz) from public;
grant execute on function public.batata_expire_guaranteed_reservations(timestamptz)
  to service_role;

-- Schedule cron if available (same pattern as pending expire)
do $cron_guaranteed$
begin
  perform cron.unschedule('batata-guaranteed-reservations-expire');
exception when others then
  null;
end;
$cron_guaranteed$;

do $cron_guaranteed_sched$
begin
  perform cron.schedule(
    'batata-guaranteed-reservations-expire',
    '*/15 * * * *',
    $$ select public.batata_expire_guaranteed_reservations(); $$
  );
exception when others then
  -- pg_cron may be unavailable in some local envs; function remains callable
  raise notice 'guaranteed expire cron not scheduled: %', sqlerrm;
end;
$cron_guaranteed_sched$;

-- -----------------------------------------------------------------------------
-- C) One-time extension (seller only)
-- -----------------------------------------------------------------------------
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

  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
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
    -- Keep original policy snapshot; do not rewrite ttl_seconds_snapshot
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

revoke all on function public.batata_commerce_extend_guaranteed_once(uuid, integer) from public;
grant execute on function public.batata_commerce_extend_guaranteed_once(uuid, integer)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- D) Manual trust + promote eligible non-guaranteed lines (backend for Phase 5 UX)
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_trust_and_promote(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_live_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_set jsonb;
  r record;
  v_promoted integer := 0;
  v_skipped integer := 0;
  v_accept jsonb;
  v_settings public.seller_reservation_settings%rowtype;
  v_ttl integer;
  v_avail integer;
  v_lock_key text;
  v_product uuid;
  v_li public.live_items%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if v_uid is distinct from p_seller_id then
    return jsonb_build_object('ok', false, 'error', 'seller_only');
  end if;
  if p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'buyer_required');
  end if;

  v_set := public.batata_seller_buyer_trust_set(p_seller_id, p_buyer_id, 'trusted');
  if coalesce((v_set->>'ok')::boolean, false) = false then
    return v_set;
  end if;

  select * into v_settings
  from public.seller_reservation_settings
  where seller_id = p_seller_id;

  v_ttl := coalesce(v_settings.trusted_ttl_seconds, 432000);

  for r in
    select *
    from public.live_reservation_requests
    where seller_id = p_seller_id
      and buyer_id = p_buyer_id
      and status = 'pending'
      and coalesce(request_kind, 'approval_pending') in ('approval_pending', 'bag_hold_none')
      and (p_live_id is null or live_id = p_live_id)
    for update skip locked
  loop
    select * into v_li from public.live_items where id = r.live_item_id;
    v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
    v_lock_key := coalesce(v_product::text, r.live_item_id::text) || ':commerce_reserve';
    perform pg_advisory_xact_lock(hashtext(v_lock_key));

    v_avail := public.batata_live_item_available_qty_engine(r.live_item_id);
    if v_avail < greatest(coalesce(r.requested_qty, 1), 1) then
      v_skipped := v_skipped + 1;
      perform public.batata_commerce_emit_reservation_event(
        r.id,
        'promotion_skipped_no_stock',
        jsonb_build_object('available_qty', v_avail)
      );
      continue;
    end if;

    update public.live_reservation_requests
    set
      status = 'accepted',
      request_kind = 'guaranteed',
      expires_at = timezone('utc', now()) + make_interval(secs => v_ttl),
      ttl_seconds_snapshot = v_ttl,
      policy_mode_snapshot = coalesce(v_settings.policy_mode, policy_mode_snapshot),
      untrusted_mode_snapshot = coalesce(v_settings.untrusted_mode, untrusted_mode_snapshot),
      trust_decision_snapshot = 'SELLER_TRUST',
      policy_version_snapshot = coalesce(v_settings.policy_version, policy_version_snapshot),
      trust_promoted_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
    where id = r.id
      and status = 'pending';

    if found then
      v_promoted := v_promoted + 1;
      perform public.batata_commerce_emit_reservation_event(
        r.id,
        'reservation_guaranteed',
        jsonb_build_object(
          'source', 'trust_promote',
          'expires_at', timezone('utc', now()) + make_interval(secs => v_ttl)
        )
      );
      perform public.batata_commerce_emit_reservation_event(
        r.id,
        'promotion_applied',
        jsonb_build_object('ttl_seconds', v_ttl)
      );
      begin
        perform public.batata_recompute_live_item_status(r.live_item_id);
      exception when others then
        null;
      end;
      perform public.batata_close_pending_for_stock(r.live_item_id, r.id);
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'trust_set', v_set,
    'promoted', v_promoted,
    'skipped_no_stock', v_skipped,
    'note', 'UX Live button may land in Phase 5; backend ready'
  );
end;
$$;

revoke all on function public.batata_commerce_trust_and_promote(uuid, uuid, uuid) from public;
grant execute on function public.batata_commerce_trust_and_promote(uuid, uuid, uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
