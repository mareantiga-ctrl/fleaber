-- V/W/X 2026-09-01 — fechos pós blind V (FSM unship), W (chat), X (live manual)
-- V-P0: shipped_at selado; sem unship; refund bloqueado pós-envio real
-- V-P0/P1: conjunto exacto (Edge); Hub live qty>0
-- W-P0/P1: chat JSON imutável (DELETE/created_at); cards alinhados à BD
-- X-P1: convert exige order paga (todos os sources); helper não infla qty
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- V-P0 — shipped_at: selo permanente ao primeiro envio
-- ---------------------------------------------------------------------------
alter table public.orders add column if not exists shipped_at timestamptz;

create or replace function public.batata_set_order_shipped_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if lower(trim(coalesce(NEW.status, ''))) = 'enviado'
     and lower(trim(coalesce(OLD.status, ''))) is distinct from 'enviado'
     and NEW.shipped_at is null then
    NEW.shipped_at := now();
  end if;

  if tg_op = 'UPDATE'
     and auth.uid() is not null
     and coalesce(auth.role(), '') = 'authenticated'
     and NEW.shipped_at is distinct from OLD.shipped_at
     and not (
       OLD.shipped_at is null
       and lower(trim(coalesce(NEW.status, ''))) = 'enviado'
       and lower(trim(coalesce(OLD.status, ''))) is distinct from 'enviado'
     ) then
    NEW.shipped_at := OLD.shipped_at;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists batata_set_order_shipped_at_trg on public.orders;
create trigger batata_set_order_shipped_at_trg
  before update on public.orders
  for each row
  execute function public.batata_set_order_shipped_at();

comment on column public.orders.shipped_at is
  'V-P0: primeira transição para enviado; nunca limpa por JWT (anti-hop refund).';

-- ---------------------------------------------------------------------------
-- V-P0 — não reabrir pago (directo, hop, cancelado reembolsado)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_no_reopen_pago()
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
  v_refund text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  v_new := lower(trim(coalesce(NEW.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_refund := coalesce(nullif(trim(coalesce(OLD.stripe_refund_id, NEW.stripe_refund_id)), ''), '');

  if v_new = 'pago' then
    if coalesce(OLD.shipped_at, NEW.shipped_at) is not null then
      raise exception 'order_cannot_reopen_pago' using errcode = '42501';
    end if;
    if v_old in ('cancelado', 'cancelled', 'canceled') and v_refund <> '' then
      raise exception 'order_cannot_reopen_pago' using errcode = '42501';
    end if;
    if v_old in (
      'enviado', 'entregue', 'concluido', 'concluído',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      raise exception 'order_cannot_reopen_pago' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- V-P0 — sem «unship» para reserva_pendente/pendente depois de envio
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

  -- V-P0: bloquear regressão a pré-pago após envio selado
  if v_new in ('reserva_pendente', 'pendente', 'reservado') then
    if coalesce(OLD.shipped_at, NEW.shipped_at) is not null
       or v_old in ('enviado', 'entregue', 'concluido', 'concluído') then
      NEW.status := OLD.status;
      return NEW;
    end if;
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
-- V-P0 — refund Edge: shipped_at manda mesmo após hop
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_allows_seller_stripe_refund(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_st text;
  v_shipped timestamptz;
  v_open_dispute boolean;
begin
  if p_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_order');
  end if;

  select lower(trim(coalesce(o.status, ''))), o.shipped_at
    into v_st, v_shipped
  from public.orders o
  where o.id = p_order_id;

  if v_st is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  if v_shipped is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_shipped',
      'status', v_st
    );
  end if;

  if v_st in ('cancelado', 'cancelled', 'canceled', 'devolvida') then
    return jsonb_build_object('ok', true, 'status', v_st, 'terminal', true);
  end if;

  if v_st in (
    'enviado',
    'concluido',
    'concluído',
    'entregue',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_status',
      'status', v_st
    );
  end if;

  select exists (
    select 1
    from public.order_disputes d
    where d.order_id = p_order_id
      and lower(trim(coalesce(d.status, ''))) in (
        'aberta', 'open', 'pending', 'em_analise', 'em_análise'
      )
  ) into v_open_dispute;

  if coalesce(v_open_dispute, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_open_dispute',
      'status', v_st
    );
  end if;

  return jsonb_build_object('ok', true, 'status', v_st);
end;
$$;

-- ---------------------------------------------------------------------------
-- W — chat: cards JSON, cronologia, valores, DELETE
-- ---------------------------------------------------------------------------
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
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
  v_needs_paid boolean;
  v_captured boolean;
  v_payload_total numeric;
  v_order_total numeric;
  v_outcome text;
  v_bundle_id uuid;
  v_bundle_total numeric;
  v_url text;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
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
           coalesce(o.stripe_refund_id, '')
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi, v_refund
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
        v_order_total := round(v_paid_cents::numeric / 100.0, 2);
        if v_payload_total is null
           or abs(v_payload_total - v_order_total) > 0.02 then
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

    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    if v_kind = 'cancel_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'cancelado', 'cancelled', 'canceled'
      ) and nullif(trim(v_refund), '') is null then
        raise exception 'chat_system_card_cancel_not_refunded' using errcode = '23514';
      end if;
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

  if v_kind = 'bundle_proposal' then
    begin
      v_bundle_id := nullif(trim(coalesce(v_json->>'bundle_id', '')), '')::uuid;
    exception when others then
      v_bundle_id := null;
    end;
    begin
      v_payload_total := nullif(trim(coalesce(v_json->>'total_eur', '')), '')::numeric;
    exception when others then
      v_payload_total := null;
    end;
    if v_bundle_id is not null then
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

create or replace function public.batata_chat_messages_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := v_uid;
  NEW.created_at := now();

  if public.batata_chat_is_forged_seguro_plain(NEW.text) then
    raise exception 'chat_seguro_legacy_plain_forbidden' using errcode = '42501';
  end if;

  perform public.batata_chat_messages_assert_json_card(
    NEW.chat_id, NEW.sender_id, NEW.text
  );
  return NEW;
end;
$fn$;

create or replace function public.batata_chat_messages_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := OLD.sender_id;
  NEW.chat_id := OLD.chat_id;
  NEW.created_at := OLD.created_at;

  if OLD.sender_id is distinct from v_uid then
    NEW.text := OLD.text;
    NEW.is_reservation := OLD.is_reservation;
    return NEW;
  end if;

  if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%'
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_system_card_immutable' using errcode = '42501';
  end if;

  if public.batata_chat_is_forged_seguro_plain(NEW.text)
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_seguro_legacy_plain_forbidden' using errcode = '42501';
  end if;

  if coalesce(OLD.text, '') not like 'FLEABER_JSON_V1:%'
     and coalesce(NEW.text, '') like 'FLEABER_JSON_V1:%' then
    perform public.batata_chat_messages_assert_json_card(
      NEW.chat_id, NEW.sender_id, NEW.text
    );
  end if;

  return NEW;
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
    if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%' then
      raise exception 'chat_system_card_immutable' using errcode = '42501';
    end if;
  end if;
  return OLD;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_delete on public.chat_messages;
create trigger trg_batata_chat_messages_guard_delete
  before delete on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_delete();

-- ---------------------------------------------------------------------------
-- W-P1 — proof_url também no INSERT; dispute reply photos
-- ---------------------------------------------------------------------------
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
  v_paid boolean;
  v_old_url text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_old_url := case when TG_OP = 'UPDATE' then OLD.proof_url else null end;
  if TG_OP = 'UPDATE' and NEW.proof_url is not distinct from v_old_url then
    return NEW;
  end if;

  v_paid :=
    lower(trim(coalesce(
      case when TG_OP = 'UPDATE' then OLD.status else NEW.status end, ''
    ))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    )
    or coalesce(
      case when TG_OP = 'UPDATE' then OLD.amount_paid_cents else NEW.amount_paid_cents end, 0
    ) > 0
    or nullif(trim(coalesce(
      case when TG_OP = 'UPDATE' then OLD.stripe_payment_intent_id else NEW.stripe_payment_intent_id end,
      ''
    )), '') is not null;

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

  if v_paid then
    if not (
      v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'
      or v_url like 'https://fleaber.app/%'
      or v_url like 'https://www.fleaber.app/%'
      or v_url like 'https://fleaber.pt/%'
      or v_url like 'https://www.fleaber.pt/%'
    ) then
      raise exception 'order_proof_url_denied' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_proof_url on public.orders;
create trigger trg_batata_orders_guard_proof_url
  before insert or update of proof_url on public.orders
  for each row
  execute function public.batata_orders_guard_proof_url();

create or replace function public.batata_order_dispute_replies_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_elem text;
begin
  if coalesce(auth.role(), '') is distinct from 'authenticated' or auth.uid() is null then
    return NEW;
  end if;
  if NEW.proof_photos is null or array_length(NEW.proof_photos, 1) is null then
    return NEW;
  end if;
  foreach v_elem in array NEW.proof_photos
  loop
    v_url := lower(trim(coalesce(v_elem, '')));
    if v_url = '' then
      continue;
    end if;
    if v_url like 'javascript:%'
       or v_url like 'data:%'
       or v_url ~ '^//'
       or v_url ~ '[\n\r]' then
      raise exception 'dispute_proof_url_denied' using errcode = '42501';
    end if;
    if not (
      v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'
      or v_url like 'https://fleaber.app/%'
      or v_url like 'https://www.fleaber.app/%'
      or v_url like 'https://fleaber.pt/%'
      or v_url like 'https://www.fleaber.pt/%'
    ) then
      raise exception 'dispute_proof_url_denied' using errcode = '42501';
    end if;
  end loop;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_dispute_replies_guard_insert on public.order_dispute_replies;
create trigger trg_batata_order_dispute_replies_guard_insert
  before insert on public.order_dispute_replies
  for each row
  execute function public.batata_order_dispute_replies_guard_insert();

-- ---------------------------------------------------------------------------
-- V-P2 — Hub live items sem qty=0
-- ---------------------------------------------------------------------------
create or replace view public.hub_live_items_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_public hl on hl.id = li.live_id
where coalesce(li.is_active, false) = true
  and coalesce(li.quantity, 0) > 0
  and lower(trim(coalesce(li.status, ''))) not in ('paused', 'inactive', 'sold');

comment on view public.hub_live_items_public is
  'Hub directo: activos, qty>0, sem paused/inactive/sold.';

grant select on public.hub_live_items_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- X-P1 — convert exige order paga (todos os sources)
-- X-P1 — helper não aumenta qty (só can_mark_items_sold ou dono)
-- V-P1 — live_only sem product_id: sem inflação JWT
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_items_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_live_owner uuid;
  v_product_seller uuid;
  v_has_active_res boolean := false;
  v_reserved int := 0;
  v_prod_qty int;
  v_is_staff boolean := false;
  v_can_mark boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id)
      into v_live_owner
    from public.lives l
    where l.id = NEW.live_id
    limit 1;
  end if;

  if v_live_owner is not null then
    v_is_staff := v_live_owner is distinct from v_uid
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations');
    v_can_mark := v_live_owner = v_uid
      or public.batata_staff_has_permission(v_live_owner, 'can_mark_items_sold');
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin()
     and not v_is_staff then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and not v_can_mark then
    raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity
      into v_product_seller, v_prod_qty
    from public.products p
    where p.id = NEW.product_id
    limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    if v_prod_qty is not null and coalesce(NEW.quantity, 0) > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
        and r.status in ('pending', 'accepted', 'converted')
    ) into v_has_active_res;
    if v_has_active_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int
      into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('pending', 'accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- X-P1: convert_requires_paid_order em todos os sources
create or replace function public.batata_process_live_reservation_request(
  p_request_id uuid,
  p_action text,
  p_processed_by uuid default auth.uid(),
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_item_qty int := 0;
  v_reserved_qty int := 0;
  v_sibling_qty int := 0;
  v_final_qty int := 1;
  v_already int := 0;
  v_avail int := 0;
  v_next_status text;
  v_item_status text;
  v_src text;
  v_paid_order uuid;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  perform pg_advisory_xact_lock(
    hashtext(v_req.live_item_id::text || ':live_res_proc')
  );

  if p_action not in ('accept', 'reject', 'skip', 'expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'invalid_action');
  end if;

  select coalesce(status, '') into v_item_status
  from public.live_items
  where id = v_req.live_item_id;

  if v_item_status = 'sold' and p_action in ('accept', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'item_sold');
  end if;

  if not (
    auth.uid() = v_req.seller_id
    or public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_src := lower(trim(coalesce(v_req.source, 'fleaber_live')));

  if p_action = 'convert' then
    select o.id into v_paid_order
    from public.orders o
    where o.live_item_id = v_req.live_item_id
      and o.buyer_id = v_req.buyer_id
      and lower(trim(coalesce(o.status, ''))) in ('pago', 'enviado', 'entregue', 'concluido')
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
    order by o.created_at desc
    limit 1;
    if v_paid_order is null then
      return jsonb_build_object('ok', false, 'error', 'convert_requires_paid_order');
    end if;
  end if;

  if p_action = 'accept' then
    select coalesce(sum(r.requested_qty), 0)::int
    into v_sibling_qty
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.live_id = v_req.live_id
      and r.buyer_id = v_req.buyer_id
      and r.id <> v_req.id
      and r.status = 'pending';

    v_final_qty := greatest(
      coalesce(v_req.requested_qty, 1) + coalesce(v_sibling_qty, 0),
      1
    );

    v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);
    if v_item_qty <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'no_stock',
        'available_qty', 0
      );
    end if;

    select coalesce(sum(r.requested_qty), 0)::int
    into v_already
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.status in ('accepted', 'converted')
      and r.id is distinct from v_req.id;

    v_avail := greatest(v_item_qty - v_already, 0);
    if v_final_qty > v_avail then
      return jsonb_build_object(
        'ok', false,
        'error', 'qty_exceeds_stock',
        'available_qty', v_avail,
        'requested', v_final_qty
      );
    end if;

    update public.live_reservation_requests
    set
      status = 'rejected',
      notes = trim(both ' |' from coalesce(notes, '') || ' | superseded:sibling_accept'),
      updated_at = now()
    where live_item_id = v_req.live_item_id
      and live_id = v_req.live_id
      and buyer_id = v_req.buyer_id
      and id <> v_req.id
      and status = 'pending';
  end if;

  update public.live_reservation_requests
  set
    requested_qty = case
      when p_action = 'accept' then v_final_qty
      else requested_qty
    end,
    status = case
      when p_action = 'accept' then 'accepted'
      when p_action = 'reject' then 'rejected'
      when p_action = 'skip' then 'rejected'
      when p_action = 'expire' then 'expired'
      else 'converted'
    end,
    expires_at = case
      when p_action = 'accept' then now() + interval '5 days'
      else expires_at
    end,
    notes = case
      when p_action = 'accept' then trim(both ' |' from regexp_replace(
        regexp_replace(coalesce(notes, ''), 'qty_confirm_needed', '', 'gi'),
        '\s*\|\s*\|', ' | ', 'g'))
      when p_action = 'skip' then coalesce('skip:' || p_notes, 'skip')
      else coalesce(p_notes, notes)
    end,
    processed_by_user_id = coalesce(p_processed_by, auth.uid()),
    updated_at = now()
  where id = v_req.id
    and (
      p_action <> 'expire'
      or lower(trim(coalesce(status, ''))) in ('pending', 'accepted')
    )
    and (
      p_action <> 'convert'
      or lower(trim(coalesce(status, ''))) in ('accepted', 'pending')
    );

  if not found and p_action in ('expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'request_state_conflict');
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id;

  if v_item_status = 'sold' then
    return jsonb_build_object(
      'ok', true,
      'request_id', v_req.id,
      'item_status', 'sold'
    );
  end if;

  v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  if p_action in ('reject', 'skip', 'expire') then
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  end if;

  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  if p_action = 'accept' then
    perform public.batata_live_reservation_accept_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id,
      v_final_qty
    );
  elsif p_action = 'convert' and v_req.status = 'converted' then
    perform public.batata_live_purchase_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'reserved_qty', v_reserved_qty,
    'item_qty', v_item_qty
  );
end;
$$;

notify pgrst, 'reload schema';
