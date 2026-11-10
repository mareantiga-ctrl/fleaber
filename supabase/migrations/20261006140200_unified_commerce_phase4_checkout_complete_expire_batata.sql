-- =============================================================================
-- BATATA 2026-10-06 — Phase 4 complete / release / expire / off-platform confirm
-- =============================================================================

create or replace function public.batata_commerce_checkout_release(
  p_attempt_id uuid,
  p_reason text default 'released'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_att public.commerce_checkout_attempts%rowtype;
  v_status text;
  v_n int := 0;
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null or v_uid is distinct from v_att.buyer_id then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;

  if v_att.status = 'payment_succeeded' then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_succeeded');
  end if;

  update public.commerce_checkout_holds
  set status = 'released', released_at = timezone('utc', now())
  where attempt_id = p_attempt_id and status = 'active';
  get diagnostics v_n = row_count;

  v_status := case
    when lower(trim(coalesce(p_reason, ''))) in ('timed_out', 'timeout', 'abandoned', 'payment_abandoned')
      then 'timed_out'
    when lower(trim(coalesce(p_reason, ''))) like '%fail%'
      then 'payment_failed_technical'
    when lower(trim(coalesce(p_reason, ''))) like '%abandon%'
      then 'payment_abandoned'
    else 'payment_abandoned'
  end;

  if lower(trim(coalesce(p_reason, ''))) in ('timed_out', 'timeout') then
    v_status := 'timed_out';
  elsif lower(trim(coalesce(p_reason, ''))) like '%technical%'
     or lower(trim(coalesce(p_reason, ''))) like '%fail%' then
    v_status := 'payment_failed_technical';
  end if;

  update public.commerce_checkout_attempts
  set status = v_status, updated_at = timezone('utc', now())
  where id = p_attempt_id
    and status is distinct from 'payment_succeeded';

  -- Cancel unpaid attempt orders (do not touch paid)
  update public.orders o
  set status = 'cancelado',
      expiry_reason = case
        when v_status = 'timed_out' then 'payment_processing'
        when v_status = 'payment_failed_technical' then 'payment_provider_technical_failure'
        else 'buyer_abandonment'
      end
  where o.checkout_attempt_id = p_attempt_id
    and lower(trim(coalesce(o.status, ''))) in (
      'reserva_pendente', 'pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'reservado'
    );

  return jsonb_build_object(
    'ok', true,
    'holds_released', v_n,
    'status', v_status,
    'no_trust_failure', true
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_release(uuid, text) from public;
grant execute on function public.batata_commerce_checkout_release(uuid, text)
  to authenticated, service_role;

-- Expire stale attempts (service cron / service_role)
create or replace function public.batata_commerce_checkout_expire_stale(
  p_now timestamptz default timezone('utc', now())
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_n int := 0;
  v_res jsonb;
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  for r in
    select id from public.commerce_checkout_attempts
    where status in ('drafted', 'payment_started_valid', 'payment_processing')
      and expires_at <= p_now
  loop
    v_res := public.batata_commerce_checkout_release(r.id, 'timed_out');
    if coalesce((v_res->>'ok')::boolean, false) then
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'expired', v_n);
end;
$$;

revoke all on function public.batata_commerce_checkout_expire_stale(timestamptz) from public;
grant execute on function public.batata_commerce_checkout_expire_stale(timestamptz)
  to service_role;

-- Complete success: consume holds, ensure checkout_attempt_id, 1 fulfillment
create or replace function public.batata_commerce_checkout_complete(
  p_attempt_id uuid,
  p_stripe_checkout_session_id text default null,
  p_stripe_payment_intent_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_att public.commerce_checkout_attempts%rowtype;
  v_n int := 0;
  v_fulfill jsonb;
  v_already boolean := false;
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id for update;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_att.status = 'payment_succeeded' then
    v_already := true;
  end if;

  update public.commerce_checkout_holds
  set status = 'consumed', consumed_at = timezone('utc', now())
  where attempt_id = p_attempt_id and status = 'active';
  get diagnostics v_n = row_count;

  update public.commerce_checkout_attempts
  set status = 'payment_succeeded',
      stripe_checkout_session_id = coalesce(
        nullif(trim(p_stripe_checkout_session_id), ''),
        stripe_checkout_session_id
      ),
      stripe_payment_intent_id = coalesce(
        nullif(trim(p_stripe_payment_intent_id), ''),
        stripe_payment_intent_id
      ),
      updated_at = timezone('utc', now())
  where id = p_attempt_id;

  -- Convert accepted LRRs linked to this attempt → converted (no second stock)
  update public.live_reservation_requests r
  set status = 'converted',
      updated_at = timezone('utc', now())
  where r.status = 'accepted'
    and r.buyer_id = v_att.buyer_id
    and (
      r.notes ilike ('%checkout_attempt:' || p_attempt_id::text || '%')
      or exists (
        select 1 from public.commerce_checkout_holds h
        where h.attempt_id = p_attempt_id
          and h.reservation_request_id = r.id
      )
    );

  -- One positive completion per attempt (D25)
  if v_att.fulfillment_recorded_at is null then
    v_fulfill := public.batata_buyer_trust_record_fulfillment(
      v_att.buyer_id,
      'checkout_attempt',
      p_attempt_id::text,
      jsonb_build_object('seller_id', v_att.seller_id)
    );
    update public.commerce_checkout_attempts
    set fulfillment_recorded_at = timezone('utc', now())
    where id = p_attempt_id and fulfillment_recorded_at is null;
  else
    v_fulfill := jsonb_build_object('ok', true, 'inserted', false, 'already', true);
  end if;

  return jsonb_build_object(
    'ok', true,
    'already', v_already,
    'holds_consumed', v_n,
    'fulfillment', v_fulfill
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_complete(uuid, text, text) from public;
grant execute on function public.batata_commerce_checkout_complete(uuid, text, text)
  to service_role;

-- Off-platform confirm (MB WAY / direct) — idempotent by attempt
create or replace function public.batata_commerce_checkout_confirm_off_platform(
  p_attempt_id uuid,
  p_proof_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_att public.commerce_checkout_attempts%rowtype;
  v_proof text := trim(coalesce(p_proof_url, ''));
  v_ord record;
  v_complete jsonb;
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id for update;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_att.payment_rail is distinct from 'off_platform' then
    return jsonb_build_object('ok', false, 'error', 'not_off_platform');
  end if;

  -- Seller of attempt OR service_role may confirm
  if v_role is distinct from 'service_role' then
    if v_uid is null or v_uid is distinct from v_att.seller_id then
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  end if;

  if v_att.status = 'payment_succeeded' then
    return jsonb_build_object('ok', true, 'already', true, 'checkout_attempt_id', p_attempt_id);
  end if;

  if v_att.status in ('timed_out', 'payment_abandoned', 'payment_failed_technical')
     or v_att.expires_at <= timezone('utc', now()) then
    return jsonb_build_object('ok', false, 'error', 'attempt_expired');
  end if;

  -- Proof must be private storage order_proofs (no fleaber.app static)
  if v_proof = '' or v_proof !~* 'order_proofs/' then
    return jsonb_build_object('ok', false, 'error', 'proof_required_storage');
  end if;
  if v_proof ~* 'fleaber\.(app|pt)/static' then
    return jsonb_build_object('ok', false, 'error', 'proof_static_denied');
  end if;

  -- Consume holds BEFORE marking pago (stock trigger + hold must not double-debit)
  update public.commerce_checkout_holds
  set status = 'consumed', consumed_at = timezone('utc', now())
  where attempt_id = p_attempt_id and status = 'active';

  for v_ord in
    select id from public.orders
    where checkout_attempt_id = p_attempt_id
      and lower(trim(coalesce(status, ''))) in (
        'reserva_pendente', 'pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'reservado'
      )
  loop
    update public.orders
    set status = 'pago',
        proof_url = v_proof
    where id = v_ord.id;
  end loop;

  update public.commerce_checkout_attempts
  set status = 'payment_succeeded',
      provider_reference = left(v_proof, 500),
      updated_at = timezone('utc', now())
  where id = p_attempt_id;

  update public.live_reservation_requests r
  set status = 'converted', updated_at = timezone('utc', now())
  where r.status = 'accepted'
    and r.buyer_id = v_att.buyer_id
    and (
      r.notes ilike ('%checkout_attempt:' || p_attempt_id::text || '%')
      or exists (
        select 1 from public.commerce_checkout_holds h
        where h.attempt_id = p_attempt_id and h.reservation_request_id = r.id
      )
    );

  if v_att.fulfillment_recorded_at is null and v_role = 'service_role' then
    perform public.batata_buyer_trust_record_fulfillment(
      v_att.buyer_id, 'checkout_attempt', p_attempt_id::text,
      jsonb_build_object('rail', 'off_platform')
    );
    update public.commerce_checkout_attempts
    set fulfillment_recorded_at = timezone('utc', now())
    where id = p_attempt_id and fulfillment_recorded_at is null;
  elsif v_att.fulfillment_recorded_at is null then
    update public.commerce_checkout_attempts
    set updated_at = timezone('utc', now())
    where id = p_attempt_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'already', false,
    'checkout_attempt_id', p_attempt_id,
    'fulfillment_pending_service', (v_role is distinct from 'service_role')
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_confirm_off_platform(uuid, text) from public;
grant execute on function public.batata_commerce_checkout_confirm_off_platform(uuid, text)
  to authenticated, service_role;

-- Service helper: record fulfillment if seller confirmed off-platform
create or replace function public.batata_commerce_checkout_ensure_fulfillment(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_att public.commerce_checkout_attempts%rowtype;
  v_f jsonb;
begin
  if coalesce(auth.role(), '') is distinct from 'service_role' then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_att.status is distinct from 'payment_succeeded' then
    return jsonb_build_object('ok', false, 'error', 'not_succeeded');
  end if;
  if v_att.fulfillment_recorded_at is not null then
    return jsonb_build_object('ok', true, 'inserted', false, 'already', true);
  end if;
  v_f := public.batata_buyer_trust_record_fulfillment(
    v_att.buyer_id, 'checkout_attempt', p_attempt_id::text, '{}'::jsonb
  );
  update public.commerce_checkout_attempts
  set fulfillment_recorded_at = timezone('utc', now())
  where id = p_attempt_id and fulfillment_recorded_at is null;
  return v_f;
end;
$$;

revoke all on function public.batata_commerce_checkout_ensure_fulfillment(uuid) from public;
grant execute on function public.batata_commerce_checkout_ensure_fulfillment(uuid)
  to service_role;

notify pgrst, 'reload schema';
