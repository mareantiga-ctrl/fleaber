-- =============================================================================
-- BATATA 2026-10-06 — Phase 4: commerce confirm bypass for quantity authority
-- Stripe settle uses service_role (skips JWT quantity guard). Off-platform
-- confirm is SECURITY DEFINER but auth.uid() remains seller → same guard fires
-- while stock_units_applied is written. Scoped GUC bypass for confirm only.
-- =============================================================================

create or replace function public.batata_products_guard_quantity_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_held int := 0;
  v_hold_units int := 0;
begin
  if coalesce(current_setting('batata.commerce_confirm', true), '') = '1' then
    return NEW;
  end if;

  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.quantity is not distinct from OLD.quantity then
    return NEW;
  end if;

  if NEW.seller_id is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations') then
    NEW.quantity := OLD.quantity;
    return NEW;
  end if;

  select coalesce(sum(coalesce(o.stock_units_applied, o.quantity, 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = NEW.id
    and coalesce(o.stock_units_applied, 0) > 0
    and lower(trim(coalesce(o.status, ''))) not in (
      'cancelado', 'cancelada', 'cancelled', 'canceled',
      'devolvida', 'concluido'
    );

  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_hold_units
  from public.orders o
  where o.product_id = NEW.id
    and public.batata_order_status_holds_product_qty(o.status);

  if (v_held > 0 or v_hold_units > 0) and NEW.quantity > OLD.quantity then
    raise exception 'product_quantity_increase_blocked_active_order'
      using errcode = '42501';
  end if;

  if NEW.quantity > OLD.quantity
     and exists (
       select 1 from public.live_items li where li.product_id = NEW.id
     ) then
    raise exception 'product_quantity_increase_blocked_live_catalog'
      using errcode = '42501';
  end if;

  if NEW.quantity < 0 then
    raise exception 'product_quantity_invalid' using errcode = '23514';
  end if;

  if v_held > 0 and coalesce(NEW.quantity, 0) < coalesce(OLD.quantity, 0)
     and NEW.quantity < v_held then
    raise exception 'product_quantity_below_applied_stock'
      using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

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
begin
  select * into v_att from public.commerce_checkout_attempts where id = p_attempt_id for update;
  if v_att.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_att.payment_rail is distinct from 'off_platform' then
    return jsonb_build_object('ok', false, 'error', 'not_off_platform');
  end if;

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

  if v_proof = '' or v_proof !~* 'order_proofs/' then
    return jsonb_build_object('ok', false, 'error', 'proof_required_storage');
  end if;
  if v_proof ~* 'fleaber\.(app|pt)/static' then
    return jsonb_build_object('ok', false, 'error', 'proof_static_denied');
  end if;

  update public.commerce_checkout_holds
  set status = 'consumed', consumed_at = timezone('utc', now())
  where attempt_id = p_attempt_id and status = 'active';

  perform set_config('batata.commerce_confirm', '1', true);

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

  perform set_config('batata.commerce_confirm', '', true);

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
  end if;

  return jsonb_build_object(
    'ok', true,
    'already', false,
    'checkout_attempt_id', p_attempt_id,
    'fulfillment_pending_service', (v_role is distinct from 'service_role')
  );
end;
$$;

notify pgrst, 'reload schema';
