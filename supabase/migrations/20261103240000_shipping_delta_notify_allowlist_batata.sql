-- =============================================================================
-- ZIP 144 — permitir kinds shipping_delta_* / ship_deadline_* no emit cliente
-- (seller→buyer com p_order_id). Antes: kind_not_allowed_for_client → notify null.
-- Não altera C2 email allowlist (continua sem email comercial destes kinds).
-- =============================================================================

create or replace function public.batata_emit_user_notification(
  p_recipient_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_chat_id uuid default null,
  p_product_id uuid default null,
  p_offer_id uuid default null,
  p_actor_id uuid default null,
  p_dedupe_key text default null,
  p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_service boolean := public.batata_notify_is_service_role();
  v_actor uuid := coalesce(p_actor_id, v_uid);
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_other uuid;
  v_buyer uuid;
  v_seller uuid;
begin
  if v_service then
    return public.batata_emit_user_notification_trusted(
      p_recipient_id, p_kind, p_title, p_body,
      p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
    );
  end if;

  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_recipient_id is null or v_kind = '' then
    raise exception 'invalid_args';
  end if;
  if p_recipient_id = v_uid then
    raise exception 'not_allowed: cannot notify self';
  end if;

  if v_kind in (
    'bundle_proposal',
    'bundle_proposal_counter',
    'bundle_purchase_request',
    'chat_message',
    'price_offer_outcome'
  ) then
    if p_chat_id is null then
      raise exception 'chat_id_required';
    end if;
    v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
    if v_other is null or v_other <> p_recipient_id then
      raise exception 'not_allowed: chat party';
    end if;
  elsif v_kind in ('seguro_fleaber_paid', 'order_paid_seller', 'order_paid_buyer') then
    if p_order_id is not null then
      select buyer_id, seller_id into v_buyer, v_seller
      from public.orders where id = p_order_id;
      if v_buyer is null then
        raise exception 'order_not_found';
      end if;
      if v_uid <> v_buyer and v_uid <> v_seller then
        raise exception 'not_allowed: order party';
      end if;
      if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
        raise exception 'not_allowed: recipient not on order';
      end if;
    elsif p_chat_id is not null then
      v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
      if v_other is null or v_other <> p_recipient_id then
        raise exception 'not_allowed: chat party';
      end if;
    else
      raise exception 'order_or_chat_required';
    end if;
  elsif v_kind = 'reservation_order_shipped' then
    if p_order_id is null then
      raise exception 'order_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = p_order_id;
    if v_buyer is null or v_uid <> v_seller then
      raise exception 'not_allowed: only seller ships';
    end if;
    if p_recipient_id <> v_buyer then
      raise exception 'not_allowed: ship notify buyer only';
    end if;
  elsif v_kind in ('price_offer', 'price_offer_counter') then
    if p_offer_id is null then
      raise exception 'offer_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.product_offers where id = p_offer_id;
    if v_buyer is null then
      raise exception 'offer_not_found';
    end if;
    if v_uid <> v_buyer and v_uid <> v_seller then
      raise exception 'not_allowed: offer party';
    end if;
    if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
      raise exception 'not_allowed: recipient';
    end if;
  elsif v_kind in (
    'shipping_delta_requested',
    'shipping_delta_paid',
    'shipping_delta_expired_cancelled',
    'ship_deadline_auto_cancelled'
  ) then
    -- ZIP144: seller/buyer da encomenda; deep link via dedupe_key ship_delta:<order_id>:…
    if p_order_id is null then
      raise exception 'order_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = p_order_id;
    if v_buyer is null then
      raise exception 'order_not_found';
    end if;
    if v_uid <> v_buyer and v_uid <> v_seller then
      raise exception 'not_allowed: order party';
    end if;
    if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
      raise exception 'not_allowed: recipient not on order';
    end if;
    if v_kind = 'shipping_delta_requested' then
      if v_uid <> v_seller then
        raise exception 'not_allowed: only seller requests delta';
      end if;
      if p_recipient_id <> v_buyer then
        raise exception 'not_allowed: delta request notifies buyer';
      end if;
    end if;
  else
    raise exception 'kind_not_allowed_for_client: %', v_kind;
  end if;

  return public.batata_emit_user_notification_trusted(
    p_recipient_id, p_kind, p_title, p_body,
    p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
  );
end;
$$;

revoke all on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) from public;
grant execute on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;
grant execute on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) to service_role;

comment on function public.batata_emit_user_notification(
  uuid, text, text, text, uuid, uuid, uuid, uuid, text, uuid
) is
  'ZIP144: +shipping_delta_*/ship_deadline_* com party check order_id. Email C2 ainda não nestes kinds.';
