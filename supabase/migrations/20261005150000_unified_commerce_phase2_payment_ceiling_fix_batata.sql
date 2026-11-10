-- =============================================================================
-- BATATA 2026-10-05 — Phase 2 correction: payment-in-progress respects ceilings
-- Stripe technical protection max = 30 minutes.
-- MB WAY / Ifthenpay technical protection max = 15 minutes.
-- PI / session / stripe_checkout tag MUST NOT protect beyond the ceiling.
-- Paid/fulfilled orders remain protected (never buyer-abandonment).
-- Additive. Does NOT edit prior migrations. No PSP changes.
-- =============================================================================

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
  v_hold_until timestamptz;
  v_status text;
begin
  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'in_progress', false, 'error', 'not_found');
  end if;

  begin
    v_order_id := substring(coalesce(v_req.notes, '') from 'stripe_checkout:([0-9a-fA-F-]{36})')::uuid;
  exception when others then
    v_order_id := null;
  end;

  if v_order_id is not null then
    select * into v_ord from public.orders where id = v_order_id;
  end if;

  -- Fallback: open/prepay or paid order for same buyer+item (prefer newest)
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
        'reserva_pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'pendente',
        'pago', 'enviado', 'entregue', 'concluido',
        'reservado'
      )
    order by o.created_at desc nulls last
    limit 1;
  end if;

  if v_ord.id is null then
    -- Stale tag alone never protects indefinitely
    if v_req.notes ilike '%stripe_checkout:%' then
      return jsonb_build_object(
        'ok', true,
        'in_progress', false,
        'reason', 'checkout_tag_without_open_order'
      );
    end if;
    return jsonb_build_object('ok', true, 'in_progress', false, 'reason', 'no_payment_signal');
  end if;

  v_status := lower(trim(coalesce(v_ord.status, '')));

  -- Paid / fulfilled: always protect (never buyer abandonment)
  if public.batata_order_status_is_sold_fulfilled(v_ord.status)
     or v_status in ('pago', 'enviado', 'entregue', 'concluido') then
    return jsonb_build_object(
      'ok', true,
      'in_progress', true,
      'reason', 'already_paid_or_fulfilled',
      'order_id', v_ord.id,
      'protect', true,
      'no_trust_failure', true
    );
  end if;

  if v_status in ('cancelado', 'cancelled', 'rejected', 'expired') then
    return jsonb_build_object(
      'ok', true,
      'in_progress', false,
      'reason', 'order_terminal_cancelled',
      'order_id', v_ord.id
    );
  end if;

  -- Only open prepay-like statuses can claim processing protection
  if v_status not in (
    'reserva_pendente', 'aguarda_pagamento', 'aguarda_confirmacao', 'pendente', 'reservado'
  ) then
    return jsonb_build_object(
      'ok', true,
      'in_progress', false,
      'reason', 'no_active_processing',
      'order_id', v_ord.id
    );
  end if;

  v_method := lower(trim(coalesce(v_ord.payment_method, '')));
  if v_method like '%mb%way%' or v_method like '%ifthen%' or v_method = 'mbway' then
    v_ceiling := v_mbway_ceiling;
  else
    -- Default Stripe / card / unknown PSP → 30 minute technical ceiling
    v_ceiling := v_stripe_ceiling;
  end if;

  v_started := coalesce(v_ord.created_at, v_req.updated_at);
  if v_started is null then
    return jsonb_build_object(
      'ok', true,
      'in_progress', false,
      'reason', 'missing_payment_start',
      'order_id', v_ord.id
    );
  end if;

  v_hold_until := v_started + v_ceiling;

  -- HARD CEILING: PI / session / stripe_checkout tag do NOT extend beyond hold_until.
  if p_now > v_hold_until then
    return jsonb_build_object(
      'ok', true,
      'in_progress', false,
      'reason', 'payment_stale_beyond_ceiling',
      'order_id', v_ord.id,
      'started_at', v_started,
      'hold_until', v_hold_until,
      'ceiling_seconds', extract(epoch from v_ceiling)::int,
      'had_payment_intent', coalesce(nullif(trim(v_ord.stripe_payment_intent_id), ''), '') <> '',
      'had_checkout_session', coalesce(nullif(trim(v_ord.stripe_checkout_session_id), ''), '') <> '',
      'had_checkout_tag', v_req.notes ilike '%stripe_checkout:%'
    );
  end if;

  -- Within ceiling and unpaid prepay → legitimate processing protection
  return jsonb_build_object(
    'ok', true,
    'in_progress', true,
    'reason', 'legitimate_payment_processing',
    'order_id', v_ord.id,
    'started_at', v_started,
    'hold_until', v_hold_until,
    'ceiling_seconds', extract(epoch from v_ceiling)::int,
    'protect', true,
    'no_trust_failure', true
  );
end;
$$;

comment on function public.batata_lrr_payment_in_progress(uuid, timestamptz) is
  'Payment-processing detector. Stripe ceiling 30m; MB WAY/Ifthenpay 15m. PI/session/tag never protect past ceiling. Paid/fulfilled always protected.';

revoke all on function public.batata_lrr_payment_in_progress(uuid, timestamptz) from public;
grant execute on function public.batata_lrr_payment_in_progress(uuid, timestamptz)
  to service_role;

notify pgrst, 'reload schema';
