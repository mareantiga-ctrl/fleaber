-- =============================================================================
-- BATATA 2026-10-06 — Phase 4: proof_url harden + payment_in_progress knows attempts
-- =============================================================================

-- Reject fleaber.app / fleaber.pt static URLs as payment proof (RT-F-001 / F4-20)
create or replace function public.batata_orders_guard_proof_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_url text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and NEW.proof_url is not distinct from OLD.proof_url then
    return NEW;
  end if;

  v_url := lower(trim(coalesce(NEW.proof_url, '')));
  if v_url = '' then
    return NEW;
  end if;

  if v_url ~ '[\n\r]' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;
  if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;
  if v_url ~ '[?&][^#]*https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;
  if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  -- Phase 4: only private storage proofs — not marketing/static site URLs
  if v_url like '%fleaber.app/static%'
     or v_url like '%fleaber.pt/static%'
     or v_url like 'https://fleaber.app/%'
     or v_url like 'https://www.fleaber.app/%'
     or v_url like 'https://fleaber.pt/%'
     or v_url like 'https://www.fleaber.pt/%' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  if not (
    v_url like 'https://%.supabase.co/storage/%'
    and v_url like '%/order_proofs/%'
  ) then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE'
     and lower(trim(coalesce(OLD.status, ''))) in (
       'pago', 'enviado', 'entregue', 'concluido'
     )
     and coalesce(OLD.proof_url, '') <> ''
     and NEW.proof_url is distinct from OLD.proof_url then
    raise exception 'order_proof_url_immutable_after_payment' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- Extend payment_in_progress: active commerce_checkout_attempt protects guaranteed
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
  v_att public.commerce_checkout_attempts%rowtype;
begin
  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'in_progress', false, 'error', 'not_found');
  end if;

  -- Phase 4: active technical attempt linked to this LRR
  select a.* into v_att
  from public.commerce_checkout_holds h
  join public.commerce_checkout_attempts a on a.id = h.attempt_id
  where h.reservation_request_id = p_request_id
    and h.status = 'active'
    and a.status in ('payment_started_valid', 'payment_processing')
    and a.expires_at > p_now
  order by a.created_at desc
  limit 1;

  if v_att.id is not null then
    return jsonb_build_object(
      'ok', true,
      'in_progress', true,
      'reason', 'commerce_checkout_attempt_active',
      'checkout_attempt_id', v_att.id,
      'protect', true,
      'no_trust_failure', true,
      'hold_until', v_att.expires_at
    );
  end if;

  -- Also match notes tag
  begin
    if v_req.notes ilike '%checkout_attempt:%' then
      select a.* into v_att
      from public.commerce_checkout_attempts a
      where v_req.notes ilike ('%checkout_attempt:' || a.id::text || '%')
        and a.buyer_id = v_req.buyer_id
        and a.status in ('payment_started_valid', 'payment_processing', 'payment_succeeded')
      order by a.created_at desc
      limit 1;
      if v_att.id is not null and v_att.status = 'payment_succeeded' then
        return jsonb_build_object(
          'ok', true,
          'in_progress', true,
          'reason', 'already_paid_or_fulfilled',
          'checkout_attempt_id', v_att.id,
          'protect', true,
          'no_trust_failure', true
        );
      end if;
      if v_att.id is not null and v_att.expires_at > p_now
         and v_att.status in ('payment_started_valid', 'payment_processing') then
        return jsonb_build_object(
          'ok', true,
          'in_progress', true,
          'reason', 'commerce_checkout_attempt_active',
          'checkout_attempt_id', v_att.id,
          'protect', true,
          'no_trust_failure', true,
          'hold_until', v_att.expires_at
        );
      end if;
    end if;
  exception when others then
    null;
  end;

  begin
    v_order_id := substring(coalesce(v_req.notes, '') from 'stripe_checkout:([0-9a-fA-F-]{36})')::uuid;
  exception when others then
    v_order_id := null;
  end;

  if v_order_id is not null then
    select * into v_ord from public.orders where id = v_order_id;
  end if;

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
    v_ceiling := v_stripe_ceiling;
  end if;

  -- Prefer attempt expiry when present
  if v_ord.checkout_attempt_id is not null then
    select * into v_att from public.commerce_checkout_attempts where id = v_ord.checkout_attempt_id;
    if v_att.id is not null then
      if v_att.status = 'payment_succeeded' then
        return jsonb_build_object(
          'ok', true, 'in_progress', true, 'reason', 'already_paid_or_fulfilled',
          'order_id', v_ord.id, 'checkout_attempt_id', v_att.id,
          'protect', true, 'no_trust_failure', true
        );
      end if;
      if v_att.expires_at is not null then
        v_hold_until := v_att.expires_at;
        v_started := v_att.created_at;
        if p_now > v_hold_until then
          return jsonb_build_object(
            'ok', true,
            'in_progress', false,
            'reason', 'payment_stale_beyond_ceiling',
            'order_id', v_ord.id,
            'checkout_attempt_id', v_att.id,
            'hold_until', v_hold_until
          );
        end if;
        return jsonb_build_object(
          'ok', true,
          'in_progress', true,
          'reason', 'legitimate_payment_processing',
          'order_id', v_ord.id,
          'checkout_attempt_id', v_att.id,
          'started_at', v_started,
          'hold_until', v_hold_until,
          'protect', true,
          'no_trust_failure', true
        );
      end if;
    end if;
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
  'Phase4: payment-in-progress via commerce_checkout_attempts + legacy order ceilings (30m/15m).';

notify pgrst, 'reload schema';
