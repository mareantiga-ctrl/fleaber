-- =============================================================================
-- BATATA 2026-10-06 — Guest-aware release/complete + no D25 for guests
-- =============================================================================

create or replace function public.batata_commerce_checkout_release(
  p_attempt_id uuid,
  p_reason text default 'released',
  p_guest_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_att public.commerce_checkout_attempts%rowtype;
  v_status text;
  v_n int := 0;
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if not public.batata_commerce_actor_owns_attempt(v_att, p_guest_token) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if v_att.status = 'payment_succeeded' then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_succeeded');
  end if;

  update public.commerce_checkout_holds
  set status = 'released', released_at = timezone('utc', now())
  where attempt_id = p_attempt_id and status = 'active';
  get diagnostics v_n = row_count;

  if lower(trim(coalesce(p_reason, ''))) in ('timed_out', 'timeout') then
    v_status := 'timed_out';
  elsif lower(trim(coalesce(p_reason, ''))) like '%technical%'
     or lower(trim(coalesce(p_reason, ''))) like '%fail%' then
    v_status := 'payment_failed_technical';
  else
    v_status := 'payment_abandoned';
  end if;

  update public.commerce_checkout_attempts
  set status = v_status, updated_at = timezone('utc', now())
  where id = p_attempt_id
    and status is distinct from 'payment_succeeded';

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

  -- Guests: never D25 failure
  return jsonb_build_object(
    'ok', true,
    'holds_released', v_n,
    'status', v_status,
    'no_trust_failure', true,
    'guest_trust_skipped', (v_att.buyer_id is null)
  );
end;
$$;

-- Single release signature (p_guest_token default null). No 2-arg overload.
drop function if exists public.batata_commerce_checkout_release(uuid, text);

revoke all on function public.batata_commerce_checkout_release(uuid, text, text) from public;
grant execute on function public.batata_commerce_checkout_release(uuid, text, text)
  to anon, authenticated, service_role;

create or replace function public.batata_commerce_checkout_complete(
  p_attempt_id uuid,
  p_stripe_checkout_session_id text default null,
  p_stripe_payment_intent_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
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

  if v_att.buyer_id is not null then
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

    -- D25 only for Fleaber identity
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
  else
    v_fulfill := jsonb_build_object(
      'ok', true,
      'inserted', false,
      'skipped', true,
      'reason', 'guest_no_trust_ledger'
    );
    update public.commerce_checkout_attempts
    set fulfillment_recorded_at = timezone('utc', now())
    where id = p_attempt_id and fulfillment_recorded_at is null;
  end if;

  return jsonb_build_object(
    'ok', true,
    'already', v_already,
    'holds_consumed', v_n,
    'fulfillment', v_fulfill,
    'guest', (v_att.buyer_id is null)
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_complete(uuid, text, text) from public;
grant execute on function public.batata_commerce_checkout_complete(uuid, text, text)
  to service_role;

-- Guest read own attempt via token (not PostgREST table policy)
create or replace function public.batata_commerce_checkout_get_attempt(
  p_attempt_id uuid,
  p_guest_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_att public.commerce_checkout_attempts%rowtype;
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if not public.batata_commerce_actor_owns_attempt(v_att, p_guest_token) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  return jsonb_build_object(
    'ok', true,
    'attempt', jsonb_build_object(
      'id', v_att.id,
      'buyer_id', v_att.buyer_id,
      'guest_session_id', v_att.guest_session_id,
      'status', v_att.status,
      'total_cents', v_att.total_cents,
      'delivery_line1', v_att.delivery_line1,
      'delivery_snapshot_at', v_att.delivery_snapshot_at,
      'expires_at', v_att.expires_at
    )
  );
end;
$$;

revoke all on function public.batata_commerce_checkout_get_attempt(uuid, text) from public;
grant execute on function public.batata_commerce_checkout_get_attempt(uuid, text)
  to anon, authenticated, service_role;

notify pgrst, 'reload schema';
