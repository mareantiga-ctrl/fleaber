-- Y / Z / AA 2026-09-01 — pós refutação VWX
-- Y-P0: conjunto qty=1 por SKU; bundle buyer match; pago capturado não reabre checkout
-- AA-P1: PATCH converted exige order paga (paridade RPC)
-- Z-P1: chat cards alinhados à BD; JSON cru bloqueado; proof_url em cards
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- Y-P0 — conjunto aceite: cada order qty=1; bundle_id só do comprador certo
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_paid boolean;
  v_internal boolean := false;
  v_allow_ttl boolean := false;
  v_bundle_buyer uuid;
  v_bundle_st text;
begin
  v_internal :=
    coalesce(current_setting('batata.allow_internal_order_cols', true), '') = '1'
    or coalesce(current_setting('batata.wallet_internal', true), '') = '1';

  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    NEW.amount_paid_cents := null;
    NEW.wallet_release_processed_at := null;
    NEW.auto_feedback_processed_at := null;
    if NEW.reservation_expires_at is not null then
      NEW.reservation_expires_at := now() + interval '5 days';
    end if;
  end if;

  if NEW.bundle_id is not null
     and (TG_OP = 'INSERT' or NEW.bundle_id is distinct from OLD.bundle_id) then
    select lower(trim(coalesce(b.status, ''))), b.buyer_id
      into v_bundle_st, v_bundle_buyer
    from public.product_bundles b
    where b.id = NEW.bundle_id;
    if not found then
      raise exception 'order_bundle_not_found' using errcode = '23514';
    end if;
    if v_bundle_buyer is distinct from NEW.buyer_id then
      raise exception 'order_bundle_buyer_mismatch' using errcode = '42501';
    end if;
    if v_bundle_st = 'accepted' and coalesce(NEW.quantity, 1) > 1 then
      raise exception 'bundle_order_quantity_must_be_one' using errcode = '23514';
    end if;
  end if;

  if TG_OP = 'INSERT' then
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id
     or NEW.seller_id is distinct from OLD.seller_id
     or NEW.product_id is distinct from OLD.product_id
     or NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id
     or NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id
     or NEW.stripe_refund_id is distinct from OLD.stripe_refund_id
     or NEW.amount_paid_cents is distinct from OLD.amount_paid_cents
     or NEW.price_total is distinct from OLD.price_total
     or NEW.contract_unit_cents is distinct from OLD.contract_unit_cents
     or NEW.contract_qty is distinct from OLD.contract_qty
     or NEW.quantity is distinct from OLD.quantity
     or NEW.payment_method is distinct from OLD.payment_method
  then
    raise exception 'order_money_fields_immutable' using errcode = '42501';
  end if;

  if not v_internal then
    if NEW.wallet_release_processed_at is distinct from OLD.wallet_release_processed_at then
      raise exception 'order_wallet_release_flag_immutable' using errcode = '42501';
    end if;
    if NEW.auto_feedback_processed_at is distinct from OLD.auto_feedback_processed_at then
      raise exception 'order_auto_feedback_flag_immutable' using errcode = '42501';
    end if;
    if NEW.wallet_refund_processed_at is distinct from OLD.wallet_refund_processed_at then
      NEW.wallet_refund_processed_at := OLD.wallet_refund_processed_at;
    end if;
    if NEW.stock_units_applied is distinct from OLD.stock_units_applied then
      NEW.stock_units_applied := OLD.stock_units_applied;
    end if;
  end if;

  if NEW.returned_at is distinct from OLD.returned_at then
    NEW.returned_at := OLD.returned_at;
  end if;

  if NEW.reservation_expires_at is distinct from OLD.reservation_expires_at then
    if NEW.reservation_expires_at is not null
       and NEW.reservation_expires_at > now() + interval '5 days' + interval '1 hour' then
      NEW.reservation_expires_at := now() + interval '5 days';
    end if;

    if OLD.reservation_expires_at is not null
       and OLD.reservation_expires_at < now() then
      NEW.reservation_expires_at := OLD.reservation_expires_at;
    elsif OLD.reservation_expires_at is not null then
      v_allow_ttl :=
        (
          lower(trim(coalesce(OLD.status, ''))) = 'reserva_pendente'
          and lower(trim(coalesce(NEW.status, ''))) = 'reservado'
        )
        or (NEW.product_offer_id is distinct from OLD.product_offer_id);
      if not v_allow_ttl then
        NEW.reservation_expires_at := OLD.reservation_expires_at;
      end if;
    end if;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_paid := v_old_st in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  ) or coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  if v_paid and NEW.bundle_id is distinct from OLD.bundle_id then
    raise exception 'order_bundle_id_frozen_after_payment' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- Y-P1 — pago capturado não regressa a hold (2.ª Checkout Session)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
  v_captured boolean := false;
  v_platform boolean := false;
  v_pm text;
  v_ship text;
  v_stripe_refund text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'entregue', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_pm := coalesce(OLD.payment_method, NEW.payment_method);
  v_ship := coalesce(OLD.shipping_method, NEW.shipping_method);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';
  v_stripe_refund := coalesce(
    nullif(trim(coalesce(NEW.stripe_refund_id, OLD.stripe_refund_id)), ''),
    ''
  );

  if v_new in (
    'reserva_pendente', 'pendente', 'reservado',
    'aguarda_confirmacao', 'aguarda_pagamento'
  ) then
    if coalesce(OLD.shipped_at, NEW.shipped_at) is not null
       or v_old in ('enviado', 'entregue', 'concluido', 'concluído')
       or (v_captured and v_old = 'pago') then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'entregue' and v_old is distinct from 'enviado' then
      raise exception 'order_entregue_requires_enviado' using errcode = '42501';
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'concluido' then
      if v_old = 'pago' then
        if not public.batata_shipping_method_is_hand(v_ship) then
          raise exception 'order_concluido_requires_shipped'
            using errcode = '42501';
        end if;
      elsif v_old not in (
        'enviado', 'entregue', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  if v_is_seller then
    if v_old in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) and v_new in ('enviado', 'entregue', 'pago', 'concluido') then
      raise exception 'order_return_in_progress' using errcode = '42501';
    end if;

    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;

      if v_platform and v_captured and v_stripe_refund = '' then
        raise exception 'order_devolvida_requires_refund' using errcode = '42501';
      end if;
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'concluido' and not v_is_buyer then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AA-P1 — PATCH converted exige order paga (paridade RPC)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean := false;
  v_avail int := 0;
  v_item_qty int := 0;
  v_new_consumes boolean := false;
  v_old_consumes boolean := false;
  v_need_capacity boolean := false;
  v_live_id uuid;
  v_item_live_id uuid;
  v_live_owner uuid;
  v_paid_order uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  if NEW.live_item_id is not null then
    select li.live_id
      into v_item_live_id
    from public.live_items li
    where li.id = NEW.live_item_id
    limit 1;
    if v_item_live_id is null then
      raise exception 'live_item_not_found' using errcode = '23503';
    end if;
    if NEW.live_id is not null and NEW.live_id is distinct from v_item_live_id then
      raise exception 'live_item_live_mismatch' using errcode = '42501';
    end if;
    NEW.live_id := coalesce(NEW.live_id, v_item_live_id);
  end if;

  v_live_id := NEW.live_id;

  select coalesce(l.seller_id, l.vendedor_id)
    into v_live_owner
  from public.lives l
  where l.id = v_live_id
  limit 1;

  if v_live_owner is not null then
    NEW.seller_id := v_live_owner;
  end if;

  if v_live_id is not null
     and public.batata_live_reservation_status_consumes_capacity(NEW.status)
     and (
       TG_OP = 'INSERT'
       or not public.batata_live_reservation_status_consumes_capacity(
         public.batata_live_reservation_status_canonical(OLD.status)
       )
     ) then
    if public.batata_live_is_draft(v_live_id) and not public.batata_is_admin() then
      raise exception 'live_not_public' using errcode = '42501';
    end if;
    if not public.batata_live_is_broadcasting(v_live_id)
       and not (public.batata_live_is_draft(v_live_id) and public.batata_is_admin()) then
      raise exception 'live_ended' using errcode = '42501';
    end if;
  end if;

  v_is_seller :=
    (v_live_owner is not null and v_live_owner = v_uid)
    or (
      v_live_owner is not null
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations')
    );

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
      v_item_qty := coalesce(public.batata_live_item_total_qty(NEW.live_item_id), 0);
      if v_item_qty < 1 then
        v_item_qty := 1;
      end if;
      if NEW.requested_qty > v_item_qty then
        NEW.requested_qty := v_item_qty;
      end if;
      if NEW.requested_qty > 20 then
        NEW.requested_qty := 20;
      end if;
      return NEW;
    end if;

    if NEW.requested_qty > 99 then
      raise exception 'invalid_requested_qty' using errcode = '23514';
    end if;

    if v_new_consumes then
      perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
      v_avail := public.batata_live_reservation_accept_available(
        NEW.live_item_id,
        null
      );
      if NEW.requested_qty > v_avail then
        raise exception 'qty_exceeds_stock' using errcode = '23514';
      end if;
    end if;
    return NEW;
  end if;

  v_old_consumes := public.batata_live_reservation_status_consumes_capacity(OLD.status);

  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from public.batata_live_reservation_status_canonical(OLD.status) then
      NEW.status := public.batata_live_reservation_status_canonical(OLD.status);
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
    NEW.seller_id := OLD.seller_id;
    return NEW;
  end if;

  if v_new_consumes and not v_old_consumes then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  if v_new_consumes
     and not v_old_consumes
     and lower(trim(coalesce(NEW.status, ''))) = 'converted' then
    select o.id into v_paid_order
    from public.orders o
    where o.live_item_id = NEW.live_item_id
      and o.buyer_id = NEW.buyer_id
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'entregue', 'concluido'
      )
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
    order by o.created_at desc
    limit 1;
    if v_paid_order is null then
      raise exception 'convert_requires_paid_order' using errcode = '42501';
    end if;
    NEW.processed_by_user_id := coalesce(NEW.processed_by_user_id, v_uid);
  end if;

  v_need_capacity :=
    v_new_consumes
    and (
      (not v_old_consumes)
      or (NEW.requested_qty > coalesce(OLD.requested_qty, 0))
    );

  if v_need_capacity then
    if NEW.live_item_id is null then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
    v_avail := public.batata_live_reservation_accept_available(
      NEW.live_item_id,
      NEW.id
    );
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
  end if;

  NEW.seller_id := coalesce(v_live_owner, OLD.seller_id);
  return NEW;
end;
$fn$;

create or replace function public.batata_live_reservation_recompute_after_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if NEW.status is distinct from OLD.status
     and lower(trim(coalesce(NEW.status, ''))) = 'converted' then
    perform public.batata_recompute_live_item_status(NEW.live_item_id);
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_recompute_after_update
  on public.live_reservation_requests;
create trigger trg_batata_live_reservation_recompute_after_update
  after update of status on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_recompute_after_update();

-- ---------------------------------------------------------------------------
-- Z-P1/P2 — chat: JSON cru, cards alinhados, proof_url em reservation_payment_submitted
-- (substitui assert_json_card + guards insert/delete do VWX)
-- ---------------------------------------------------------------------------
-- Copiado de sec_vwx com extensões Z; ver função completa abaixo.

create or replace function public.batata_chat_messages_assert_json_card(
  p_chat_id uuid,
  p_sender_id uuid,
  p_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text := coalesce(p_text, '');
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_order_status text;
  v_paid_cents int;
  v_pi text;
  v_refund text;
  v_order_total numeric;
  v_res_exp timestamptz;
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
  v_needs_paid boolean;
  v_captured boolean;
  v_payload_total numeric;
  v_payload_amount numeric;
  v_outcome text;
  v_bundle_id uuid;
  v_bundle_total numeric;
  v_offer_id uuid;
  v_offer_amount numeric;
  v_url text;
  v_has_dispute boolean;
  v_has_review boolean;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
    if btrim(v_raw) like '{%' then
      raise exception 'chat_system_card_prefix_required' using errcode = '42501';
    end if;
    return;
  end if;

  begin
    v_json := substring(v_raw from length('FLEABER_JSON_V1:') + 1)::jsonb;
  exception when others then
    raise exception 'chat_system_card_invalid_json' using errcode = '23514';
  end;

  v_kind := lower(trim(coalesce(v_json->>'kind', '')));
  if v_kind = '' then
    raise exception 'chat_system_card_kind_required' using errcode = '23514';
  end if;

  if v_kind in (
    'marketplace_bag_paid',
    'auto_feedback_generated',
    'raffle_prize',
    'premio_rifa',
    'order_paid'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c
  where c.id = p_chat_id;

  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;

  if p_sender_id is distinct from v_chat_a and p_sender_id is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  v_needs_order := v_kind in (
    'reservation_seller_confirmed_receipt',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_shipped',
    'reservation_accepted',
    'reservation_request_outcome',
    'price_offer_outcome',
    'cancel_request_outcome',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'bundle_buyer_confirmed_receipt',
    'reservation_payment_submitted',
    'reservation_request',
    'reservation_order_completed',
    'cancel_request',
    'order_review_submitted',
    'seguro_fleaber_paid',
    'price_offer',
    'order_dispute_opened'
  );

  v_needs_paid := v_kind in (
    'seguro_fleaber_paid',
    'reservation_order_shipped',
    'reservation_order_completed',
    'reservation_seller_confirmed_receipt',
    'bundle_buyer_confirmed_receipt'
  );

  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;

  if v_needs_order and v_oid is null then
    raise exception 'chat_system_card_order_id_required' using errcode = '23514';
  end if;

  if v_oid is not null then
    select o.seller_id, o.buyer_id, o.status,
           coalesce(o.amount_paid_cents, 0),
           coalesce(o.stripe_payment_intent_id, ''),
           coalesce(o.stripe_refund_id, ''),
           o.price_total,
           o.reservation_expires_at
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi, v_refund,
           v_order_total, v_res_exp
    from public.orders o
    where o.id = v_oid;

    if not found then
      raise exception 'chat_system_card_order_missing' using errcode = '23514';
    end if;

    if not (
      (v_order_seller is not distinct from v_chat_a and v_order_buyer is not distinct from v_chat_b)
      or (v_order_seller is not distinct from v_chat_b and v_order_buyer is not distinct from v_chat_a)
    ) then
      raise exception 'chat_system_card_order_chat_mismatch' using errcode = '23514';
    end if;

    v_captured := v_paid_cents > 0 or nullif(trim(v_pi), '') is not null;

    if v_needs_paid then
      if v_kind = 'seguro_fleaber_paid' then
        if not v_captured then
          raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
        end if;
        begin
          v_payload_total := nullif(trim(coalesce(v_json->>'total', '')), '')::numeric;
        exception when others then
          v_payload_total := null;
        end;
        if v_payload_total is null
           or abs(v_payload_total - round(v_paid_cents::numeric / 100.0, 2)) > 0.02 then
          raise exception 'chat_system_card_total_mismatch' using errcode = '23514';
        end if;
      else
        if not (
          v_captured
          or lower(trim(coalesce(v_order_status, ''))) in (
            'pago', 'enviado', 'entregue', 'concluido',
            'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
            'disputa_devolucao_vendedor', 'devolvida'
          )
        ) then
          raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
        end if;
      end if;
    end if;

    if v_kind in ('order_direct_payment_details', 'bundle_direct_payment_details') then
      begin
        v_payload_amount := nullif(trim(coalesce(v_json->>'amount_eur', '')), '')::numeric;
      exception when others then
        v_payload_amount := null;
      end;
      if v_payload_amount is null
         or abs(v_payload_amount - coalesce(v_order_total, 0)) > 0.02 then
        raise exception 'chat_system_card_amount_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_payment_submitted' then
      v_url := lower(trim(coalesce(v_json->>'proof_url', '')));
      if v_url <> '' then
        if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
           or v_url ~ '[\n\r]' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if not (
          v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'
          or v_url like 'https://fleaber.app/%'
          or v_url like 'https://www.fleaber.app/%'
          or v_url like 'https://fleaber.pt/%'
          or v_url like 'https://www.fleaber.pt/%'
        ) then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
      end if;
    end if;

    if v_kind = 'reservation_order_shipped'
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'enviado', 'entregue', 'concluido', 'pedido_devolucao',
         'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor', 'devolvida'
       ) then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    if v_kind = 'reservation_seller_confirmed_receipt'
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'entregue', 'concluido', 'pedido_devolucao', 'em_devolucao',
         'devolucao_entregue', 'disputa_devolucao_vendedor', 'devolvida'
       ) then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    if v_kind = 'reservation_order_completed'
       and lower(trim(coalesce(v_order_status, ''))) <> 'concluido' then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    if v_kind in (
      'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller'
    ) and lower(trim(coalesce(v_order_status, ''))) not in (
      'cancelado', 'cancelled', 'canceled'
    ) and nullif(trim(v_refund), '') is null then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    if v_kind = 'cancel_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'cancelado', 'cancelled', 'canceled'
      ) and nullif(trim(v_refund), '') is null then
        raise exception 'chat_system_card_cancel_not_refunded' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'order_dispute_opened' then
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = v_oid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not coalesce(v_has_dispute, false) then
        raise exception 'chat_system_card_dispute_missing' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'order_review_submitted' then
      select exists(
        select 1 from public.reviews r
        where r.order_id = v_oid
      ) into v_has_review;
      if not coalesce(v_has_review, false) then
        raise exception 'chat_system_card_review_missing' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_accepted' and v_res_exp is not null then
      begin
        if nullif(trim(coalesce(v_json->>'expires_at', '')), '')::timestamptz
           is distinct from v_res_exp then
          raise exception 'chat_system_card_expires_mismatch' using errcode = '23514';
        end if;
      exception when others then
        raise exception 'chat_system_card_expires_mismatch' using errcode = '23514';
      end;
    end if;

    if v_kind in (
      'reservation_seller_confirmed_receipt',
      'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller',
      'reservation_order_shipped',
      'reservation_accepted',
      'reservation_request_outcome',
      'price_offer_outcome',
      'cancel_request_outcome',
      'bundle_direct_payment_details',
      'order_direct_payment_details'
    ) then
      if p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_seller_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in (
      'bundle_buyer_confirmed_receipt',
      'reservation_payment_submitted',
      'reservation_request',
      'reservation_order_completed',
      'cancel_request',
      'order_review_submitted',
      'seguro_fleaber_paid',
      'price_offer'
    ) then
      if p_sender_id is distinct from v_order_buyer then
        raise exception 'chat_system_card_buyer_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in ('order_dispute_opened') then
      if p_sender_id is distinct from v_order_buyer
         and p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_party_only' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_kind = 'price_offer_outcome' then
    begin
      v_offer_id := nullif(trim(coalesce(v_json->>'offer_id', '')), '')::uuid;
    exception when others then
      v_offer_id := null;
    end;
    if v_offer_id is null then
      raise exception 'chat_system_card_offer_id_required' using errcode = '23514';
    end if;
    select po.amount into v_offer_amount
    from public.product_offers po
    where po.id = v_offer_id;
    if not found then
      raise exception 'chat_system_card_offer_missing' using errcode = '23514';
    end if;
    begin
      v_payload_amount := nullif(trim(coalesce(v_json->>'amount', '')), '')::numeric;
    exception when others then
      v_payload_amount := null;
    end;
    if v_payload_amount is null
       or abs(v_payload_amount - coalesce(v_offer_amount, 0)) > 0.02 then
      raise exception 'chat_system_card_offer_amount_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'bundle_proposal' then
    begin
      v_bundle_id := nullif(trim(coalesce(v_json->>'bundle_id', '')), '')::uuid;
    exception when others then
      v_bundle_id := null;
    end;
    if v_bundle_id is null then
      raise exception 'chat_system_card_bundle_id_required' using errcode = '23514';
    end if;
    begin
      v_payload_total := nullif(trim(coalesce(v_json->>'total_eur', '')), '')::numeric;
    exception when others then
      v_payload_total := null;
    end;
    select b.total_eur into v_bundle_total
    from public.product_bundles b
    where b.id = v_bundle_id;
    if not found then
      raise exception 'chat_system_card_bundle_missing' using errcode = '23514';
    end if;
    if v_payload_total is null
       or abs(v_payload_total - coalesce(v_bundle_total, 0)) > 0.02 then
      raise exception 'chat_system_card_bundle_total_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'chat_image' then
    v_url := lower(trim(coalesce(v_json->>'url', '')));
    if v_url <> '' and (
      v_url like 'javascript:%'
      or v_url like 'data:%'
      or v_url ~ '^//'
    ) then
      raise exception 'chat_system_card_url_denied' using errcode = '23514';
    end if;
  end if;

  if v_kind not in (
    'chat_image',
    'bundle_proposal',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'price_offer',
    'price_offer_outcome',
    'reservation_accepted',
    'reservation_request',
    'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt',
    'cancel_request',
    'cancel_request_outcome',
    'order_dispute_opened',
    'order_review_submitted',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed',
    'reservation_order_shipped',
    'reservation_payment_submitted',
    'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;
end;
$fn$;

create or replace function public.batata_chat_messages_guard_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if coalesce(auth.role(), '') = 'authenticated' and auth.uid() is not null then
    if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%'
       or btrim(coalesce(OLD.text, '')) like '{%' then
      raise exception 'chat_system_card_immutable' using errcode = '42501';
    end if;
  end if;
  return OLD;
end;
$fn$;

notify pgrst, 'reload schema';
