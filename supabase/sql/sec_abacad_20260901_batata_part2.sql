-- AB/AC/AD part2 — assert_json_card AC patches
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~*
    '(Seguro Fleaber|Seguro|Compra paga|MB\s*WAY|MBWAY|PIX|Transfer[eê]ncia|Pagamento|Reembolso|PayPal|Bizum|IBAN|Recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|EUR|euros?)|€\s*\d+|\d+\s*€|\d+\s*EUR)'
    or coalesce(p_text, '') ~*
    '(MB\s*WAY|MBWAY|PIX|PayPal|Bizum).*(confirmado|banco|recebido)';
$$;

create or replace function public.batata_chat_strip_format_controls(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    coalesce(p_text, ''),
    '[' || chr(8203) || chr(8204) || chr(8205) || chr(8206) || chr(8207)
      || chr(8234) || chr(8235) || chr(8236) || chr(8237) || chr(8238)
      || chr(8294) || chr(8295) || chr(8296) || chr(8297) || chr(8288)
      || chr(173) || ']+',
    '',
    'g'
  );
$$;

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
  v_raw text := public.batata_chat_strip_format_controls(
    replace(coalesce(p_text, ''), U&'\FEFF', '')
  );
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
  v_offer_status text;
  v_url text;
  v_path text;
  v_has_dispute boolean;
  v_has_review boolean;
  v_review_stars int;
  v_payload_stars int;
  v_label text;
  v_notes text;
  v_label_amount numeric;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
    if public.batata_chat_strip_unicode_ws(v_raw) like '{%'
       or btrim(v_raw) like '{%' then
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
    'marketplace_bag_paid', 'auto_feedback_generated',
    'raffle_prize', 'premio_rifa', 'order_paid'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c where c.id = p_chat_id;
  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;
  if p_sender_id is distinct from v_chat_a and p_sender_id is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  v_needs_order := v_kind in (
    'reservation_seller_confirmed_receipt', 'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller', 'reservation_order_shipped',
    'reservation_accepted', 'reservation_request_outcome', 'price_offer_outcome',
    'cancel_request_outcome', 'bundle_direct_payment_details',
    'order_direct_payment_details', 'bundle_buyer_confirmed_receipt',
    'reservation_payment_submitted', 'reservation_request',
    'reservation_order_completed', 'cancel_request', 'order_review_submitted',
    'seguro_fleaber_paid', 'price_offer', 'order_dispute_opened'
  );
  v_needs_paid := v_kind in (
    'seguro_fleaber_paid', 'reservation_order_shipped', 'reservation_order_completed',
    'reservation_seller_confirmed_receipt', 'bundle_buyer_confirmed_receipt'
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
           o.price_total, o.reservation_expires_at
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi, v_refund,
           v_order_total, v_res_exp
    from public.orders o where o.id = v_oid;
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
        v_label := coalesce(v_json->>'label', '');
        if v_label ~* '(Seguro|PIX|MB\s*WAY|MBWAY|Compra paga|Transferência|Pagamento)' then
          if v_label ~ '\d' then
            begin
              v_label_amount := nullif(
                regexp_replace(v_label, '[^0-9,.]', '', 'g'),
                ''
              )::numeric;
            exception when others then
              v_label_amount := null;
            end;
            if v_label_amount is null
               or abs(v_label_amount - round(v_paid_cents::numeric / 100.0, 2)) > 0.05 then
              raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
            end if;
          else
            -- keywords sem dígitos = mentira de método (AI P2-02)
            raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
          end if;
        end if;
      elsif not (
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
      v_notes := coalesce(v_json->>'notes', '');
      if public.batata_chat_payment_lie_text(v_notes) then
        raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
      end if;
      v_url := lower(trim(coalesce(v_json->>'proof_url', '')));
      if v_url <> '' then
        if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
           or v_url ~ '[\n\r]' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url ~ '[?&][^#]*https?://' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url like '%/object/public/%' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if not (
          v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/%'
          or v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/fleaber_private/%'
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
    if v_kind in ('reservation_cancelled_by_seller', 'bundle_reservation_cancelled_by_seller')
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'cancelado', 'cancelled', 'canceled'
       ) and nullif(trim(v_refund), '') is null then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    if v_kind = 'cancel_request_outcome' then
      if v_outcome not in ('accepted', 'rejected') then
        raise exception 'chat_system_card_outcome_invalid' using errcode = '23514';
      end if;
      if public.batata_chat_payment_lie_text(coalesce(v_json->>'display', '')) then
        raise exception 'chat_system_card_display_forbidden' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'cancel_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'cancelado', 'cancelled', 'canceled'
      ) and nullif(trim(v_refund), '') is null then
        raise exception 'chat_system_card_cancel_not_refunded' using errcode = '23514';
      end if;
    end if;
    if v_kind = 'cancel_request_outcome' and v_outcome = 'rejected' then
      if lower(trim(coalesce(v_order_status, ''))) in (
        'cancelado', 'cancelled', 'canceled'
      ) or nullif(trim(v_refund), '') is not null then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_request_outcome' then
      if v_outcome not in ('accepted', 'rejected') then
        raise exception 'chat_system_card_outcome_invalid' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'reserva_pendente'
      ) then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
      end if;
    end if;
    if v_kind = 'reservation_request_outcome' and v_outcome = 'rejected' then
      if lower(trim(coalesce(v_order_status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'reserva_pendente', 'pago'
      ) then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
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
        select 1 from public.reviews r where r.order_id = v_oid
      ) into v_has_review;
      if not coalesce(v_has_review, false) then
        raise exception 'chat_system_card_review_missing' using errcode = '23514';
      end if;
      select coalesce(r.stars, 0) into v_review_stars
      from public.reviews r where r.order_id = v_oid
      order by r.created_at desc
      limit 1;
      begin
        v_payload_stars := nullif(trim(coalesce(v_json->>'stars', '')), '')::int;
      exception when others then
        v_payload_stars := null;
      end;
      if v_payload_stars is null or v_payload_stars is distinct from v_review_stars then
        raise exception 'chat_system_card_review_stars_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_accepted' then
      if lower(trim(coalesce(v_order_status, ''))) in (
        'pago', 'enviado', 'entregue', 'concluido'
      ) then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
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
      'reservation_seller_confirmed_receipt', 'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller', 'reservation_order_shipped',
      'reservation_accepted', 'reservation_request_outcome', 'price_offer_outcome',
      'cancel_request_outcome', 'bundle_direct_payment_details', 'order_direct_payment_details'
    ) and p_sender_id is distinct from v_order_seller then
      raise exception 'chat_system_card_seller_only' using errcode = '42501';
    end if;
    if v_kind in (
      'bundle_buyer_confirmed_receipt', 'reservation_payment_submitted',
      'reservation_request', 'reservation_order_completed', 'cancel_request',
      'order_review_submitted', 'seguro_fleaber_paid', 'price_offer'
    ) and p_sender_id is distinct from v_order_buyer then
      raise exception 'chat_system_card_buyer_only' using errcode = '42501';
    end if;
    if v_kind = 'order_dispute_opened'
       and p_sender_id is distinct from v_order_buyer
       and p_sender_id is distinct from v_order_seller then
      raise exception 'chat_system_card_party_only' using errcode = '42501';
    end if;
  end if;

  if v_kind = 'price_offer' then
    begin
      v_offer_id := nullif(trim(coalesce(v_json->>'offer_id', '')), '')::uuid;
    exception when others then
      v_offer_id := null;
    end;
    if v_offer_id is null then
      raise exception 'chat_system_card_offer_id_required' using errcode = '23514';
    end if;
    select po.amount, lower(trim(coalesce(po.status, '')))
      into v_offer_amount, v_offer_status
    from public.product_offers po where po.id = v_offer_id;
    if not found then
      raise exception 'chat_system_card_offer_missing' using errcode = '23514';
    end if;
    if v_offer_status not in ('pending', 'accepted') then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
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

  if v_kind = 'price_offer_outcome' then
    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    if v_outcome not in ('accepted', 'rejected') then
      raise exception 'chat_system_card_outcome_invalid' using errcode = '23514';
    end if;
    begin
      v_offer_id := nullif(trim(coalesce(v_json->>'offer_id', '')), '')::uuid;
    exception when others then
      v_offer_id := null;
    end;
    if v_offer_id is null then
      raise exception 'chat_system_card_offer_id_required' using errcode = '23514';
    end if;
    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    select po.amount, lower(trim(coalesce(po.status, '')))
      into v_offer_amount, v_offer_status
    from public.product_offers po where po.id = v_offer_id;
    if not found then
      raise exception 'chat_system_card_offer_missing' using errcode = '23514';
    end if;
    if v_outcome = 'accepted' and v_offer_status is distinct from 'accepted' then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
    end if;
    if v_outcome = 'rejected'
       and v_offer_status not in ('rejected', 'declined', 'cancelled', 'canceled', 'cancelado') then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
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
    select b.total_eur into v_bundle_total from public.product_bundles b where b.id = v_bundle_id;
    if not found then
      raise exception 'chat_system_card_bundle_missing' using errcode = '23514';
    end if;
    if v_payload_total is null
       or abs(v_payload_total - coalesce(v_bundle_total, 0)) > 0.02 then
      raise exception 'chat_system_card_bundle_total_mismatch' using errcode = '23514';
    end if;
    -- product_ids no payload têm de bater com o conjunto (anti decoy)
    if v_json ? 'product_ids' then
      if (
        select coalesce(array_agg(x::text order by x::text), array[]::text[])
        from jsonb_array_elements_text(coalesce(v_json->'product_ids', '[]'::jsonb)) t(x)
      ) is distinct from (
        select coalesce(array_agg(x::text order by x::text), array[]::text[])
        from public.product_bundles b,
             unnest(coalesce(b.product_ids, array[]::uuid[])) as x
        where b.id = v_bundle_id
      ) then
        raise exception 'chat_system_card_bundle_products_mismatch' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'chat_image' then
    v_path := trim(coalesce(v_json->>'path', ''));
    if v_path = '' or v_path like '%..%' or position(chr(92) in v_path) > 0
       or v_path like '%\%%' then
      raise exception 'chat_system_card_path_denied' using errcode = '23514';
    end if;
    if v_path not like ('chat_uploads/' || p_sender_id::text || '/%') then
      raise exception 'chat_system_card_path_denied' using errcode = '23514';
    end if;
    v_url := lower(trim(coalesce(v_json->>'url', '')));
    if v_url <> '' then
      if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
         or v_url ~ '[\n\r]' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if not v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind not in (
    'chat_image', 'bundle_proposal', 'bundle_direct_payment_details',
    'order_direct_payment_details', 'price_offer', 'price_offer_outcome',
    'reservation_accepted', 'reservation_request', 'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt', 'cancel_request', 'cancel_request_outcome',
    'order_dispute_opened', 'order_review_submitted',
    'reservation_cancelled_by_seller', 'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed', 'reservation_order_shipped',
    'reservation_payment_submitted', 'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;
end;
$fn$;

notify pgrst, 'reload schema';
