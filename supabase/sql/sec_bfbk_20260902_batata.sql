-- POS_ATBE BF–BK fecho 2026-09-02
-- production_touched: false · fase4: false · BATATA

-- ===========================================================================
-- BJ-P1 — mão = allowlist exacta (sem LIKE 'entrega em m%' / 'hand%')
-- ===========================================================================
create or replace function public.batata_shipping_method_is_hand(p_method text)
returns boolean
language plpgsql
immutable
as $$
declare
  m text := lower(trim(coalesce(p_method, '')));
begin
  if m = '' then
    return false;
  end if;
  return m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)',
    'entrega em mão (€0)', 'entrega em mao (€0)'
  );
end;
$$;

-- ===========================================================================
-- BK-P1 — seller NÃO marca pedido_devolucao (só buyer com disputa)
-- + reapply paid_status guard (patch seller block)
-- ===========================================================================
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
  v_proof text;
  v_return_fsm boolean := false;
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
  v_proof := coalesce(nullif(trim(coalesce(NEW.proof_url, OLD.proof_url)), ''), '');
  v_return_fsm := v_old in (
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );

  if coalesce(nullif(trim(coalesce(OLD.stripe_refund_id, NEW.stripe_refund_id)), ''), '') <> ''
     or v_old in ('devolvida', 'cancelado', 'cancelled') then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      raise exception 'order_status_denied_after_refund' using errcode = '42501';
    end if;
  end if;

  if v_new in (
    'reserva_pendente', 'pendente', 'reservado',
    'aguarda_confirmacao', 'aguarda_pagamento'
  ) then
    if coalesce(OLD.shipped_at, NEW.shipped_at) is not null
       or v_old in ('enviado', 'entregue', 'concluido', 'concluído')
       or (v_captured and v_old = 'pago') then
      raise exception 'order_status_regression_denied' using errcode = '42501';
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
    raise exception 'order_cancel_denied_post_pay' using errcode = '42501';
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      raise exception 'order_status_requires_capture' using errcode = '42501';
    end if;
  end if;

  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      raise exception 'order_buyer_cannot_mark_pago' using errcode = '42501';
    end if;
    if v_new = 'enviado' then
      raise exception 'order_buyer_cannot_mark_enviado' using errcode = '42501';
    end if;
    if v_new = 'devolvida' then
      raise exception 'order_buyer_cannot_mark_devolvida' using errcode = '42501';
    end if;
    if v_new = 'devolucao_entregue' then
      raise exception 'order_buyer_cannot_mark_devolucao_entregue' using errcode = '42501';
    end if;

    if v_new = 'entregue' and v_old is distinct from 'enviado' then
      raise exception 'order_entregue_requires_enviado' using errcode = '42501';
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      raise exception 'order_return_after_release_denied' using errcode = '42501';
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        raise exception 'order_pedido_devolucao_denied' using errcode = '42501';
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        raise exception 'order_pedido_devolucao_requires_dispute' using errcode = '42501';
      end if;
    end if;

    if v_new = 'em_devolucao' and v_old is distinct from 'pedido_devolucao' then
      raise exception 'order_em_devolucao_requires_pedido' using errcode = '42501';
    end if;

    if v_new = 'concluido' then
      if v_return_fsm then
        raise exception 'order_concluido_denied_during_return' using errcode = '42501';
      end if;
      if v_old = 'pago' then
        if not public.batata_shipping_method_is_hand(v_ship) then
          raise exception 'order_concluido_requires_shipped'
            using errcode = '42501';
        end if;
      elsif v_old not in ('enviado', 'entregue') then
        raise exception 'order_concluido_denied' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_is_seller then
    if v_return_fsm and v_new in ('enviado', 'entregue', 'pago', 'concluido') then
      raise exception 'order_return_in_progress' using errcode = '42501';
    end if;

    -- BK-P1: seller não inicia pedido_devolucao (PI hostage)
    if v_new = 'pedido_devolucao' then
      raise exception 'order_seller_cannot_mark_pedido_devolucao'
        using errcode = '42501';
    end if;

    if v_new = 'pago' and v_old is distinct from 'pago' then
      if public.batata_is_off_platform_payment(v_pm) then
        if v_proof = '' then
          raise exception 'order_mbway_pago_requires_proof' using errcode = '42501';
        end if;
      elsif not v_captured then
        raise exception 'order_seller_pago_requires_capture' using errcode = '42501';
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new = 'concluido' then
      raise exception 'order_seller_cannot_mark_concluido' using errcode = '42501';
    end if;

    if v_new = 'entregue' then
      raise exception 'order_seller_cannot_mark_entregue' using errcode = '42501';
    end if;

    if v_new = 'enviado' then
      if v_old is distinct from 'pago' and not v_captured then
        raise exception 'order_ship_requires_pago' using errcode = '42501';
      end if;
    end if;

    if v_new = 'em_devolucao' and v_old is distinct from 'pedido_devolucao' then
      raise exception 'order_em_devolucao_requires_pedido' using errcode = '42501';
    end if;

    if v_new = 'devolucao_entregue' and v_old is distinct from 'em_devolucao' then
      raise exception 'order_devolucao_entregue_denied' using errcode = '42501';
    end if;

    if v_new = 'devolvida' then
      if v_old is distinct from 'devolucao_entregue' then
        raise exception 'order_devolvida_denied' using errcode = '42501';
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
        raise exception 'order_devolvida_requires_dispute' using errcode = '42501';
      end if;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    raise exception 'order_status_not_party' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- BG — Affirm / Cash App / Pix emoji + rails inbox
-- ===========================================================================
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|venmo|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|wise|revolut|mb\s*way|affirm|cash\s*app|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|mb\s*way|mbway|pix)\M';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|affirm|cash\s*app|pix|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o).{0,40}(confirmado|aprovado|processado|feito|caiu|€|eur|💶|\d)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|klarna|sofort|ideal|twint|afterpay|pix|paypal)\M';
$$;

-- Label/notes Affirm + proof_url path-only (antes de ?/#)
create or replace function public.batata_chat_messages_guard_image_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text;
  v_json jsonb;
  v_kind text;
  v_url text;
  v_path text;
  v_notes text;
  v_label text;
  v_display text;
  v_order uuid;
  v_buyer uuid;
  v_needle text;
begin
  v_raw := coalesce(NEW.text, '');
  if position('FLEABER_JSON_V1:' in v_raw) = 0 then
    return NEW;
  end if;
  begin
    v_json := (regexp_replace(v_raw, '^.*?FLEABER_JSON_V1:', ''))::jsonb;
  exception when others then
    return NEW;
  end;
  v_kind := lower(trim(coalesce(v_json->>'kind', '')));

  if v_kind = 'chat_image' then
    v_path := trim(coalesce(v_json->>'path', ''));
    v_url := lower(trim(coalesce(v_json->>'url', '')));
    if v_url <> '' then
      if v_url like '%/object/public/%'
         or v_url like 'javascript:%'
         or v_url like 'data:%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like '%/object/sign/%'
         and v_url not like '%/object/authenticated/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'reservation_payment_submitted' then
    v_notes := coalesce(v_json->>'notes', '');
    if v_notes ~ '[<>]' or public.batata_chat_payment_lie_text(v_notes) then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    if public.batata_chat_normalize_lie_text(v_notes) ~*
       '(affirm|cash\s*app|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple|google|mb\s*way|mbway|pix|multibanco)' then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    begin
      v_order := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
    exception when others then
      v_order := null;
    end;
    v_url := lower(trim(coalesce(v_json->>'proof_url', '')));
    if v_url <> '' then
      if v_url like '%/object/public/%' or v_url like 'javascript:%' or v_url like 'data:%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like '%/object/sign/fleaber_private/%'
         and v_url not like '%/object/authenticated/fleaber_private/%'
         and v_url not like '%/object/fleaber_private/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_order is null then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      select buyer_id into v_buyer from public.orders where id = v_order;
      v_path := split_part(split_part(v_url, '?', 1), '#', 1);
      v_needle := 'order_proofs/' || coalesce(v_buyer::text, '') || '/' || v_order::text || '/';
      if v_buyer is null or position(v_needle in v_path) = 0 then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if public.batata_chat_normalize_lie_text(v_label) ~*
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|affirm|cash\s*app|seguro|pago no mb|transfer|cart[aã]o|multibanco)' then
      raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
    end if;
    if public.batata_chat_payment_lie_text(v_label) then
      raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'cancel_request_outcome' then
    v_display := coalesce(v_json->>'display', '');
    if public.batata_chat_payment_lie_text(v_display) then
      raise exception 'chat_system_card_display_forbidden' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- Dispute proofs: path-only needle
create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_path text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid := NEW.order_id;
  v_needle text;
begin
  select buyer_id into v_buyer from public.orders where id = v_oid;
  v_needle := case
    when v_buyer is not null and v_oid is not null then
      'order_disputes/' || v_buyer::text || '/' || v_oid::text || '/'
    else null
  end;

  if NEW.proof_photos is not null then
    begin
      v_arr := to_jsonb(NEW.proof_photos);
    exception when others then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end;
    if jsonb_typeof(v_arr) = 'array' then
      for v_url in
        select lower(trim(coalesce(elem, '')))
        from jsonb_array_elements_text(v_arr) as t(elem)
      loop
        if v_url = '' then continue; end if;
        if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
           or v_url ~ '[\n\r<>"]' or v_url like '%/object/public/%' then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        if v_url not like '%/object/sign/fleaber_private/%'
           and v_url not like '%/object/authenticated/fleaber_private/%' then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        v_path := split_part(split_part(v_url, '?', 1), '#', 1);
        if v_needle is null or position(v_needle in v_path) = 0 then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
      end loop;
    end if;
  end if;

  if NEW.return_label_url is not null
     and nullif(trim(NEW.return_label_url), '') is not null then
    v_url := lower(trim(NEW.return_label_url));
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%/object/public/%' then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
    v_path := split_part(split_part(v_url, '?', 1), '#', 1);
    if v_needle is null or position(v_needle in v_path) = 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- BH — FOMO sinónimos + ZWJ/leet; stock marketplace qty NULL; total_qty gate
-- ===========================================================================
create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;

  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- strip zero-width / leet leve
  v_norm := lower(v_body);
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff]', '', 'g');
  v_norm := translate(v_norm, 'áàâãäéèêëíìîïóòôõöúùûüç0', 'aaaaaeeeeiiiiooooouuuuco');
  v_norm := regexp_replace(v_norm, '[^a-z0-9€🛒✅\s]', ' ', 'g');

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|vendido|sold|adquiriu|encomenda(da)?|c0mprou)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot)') then
    return jsonb_build_object(
      'ok', false,
      'error', 'purchase_announce_via_broadcast_only'
    );
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller
  from public.lives
  where id = p_live_id;

  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_uid is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_manage_chat') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_live_system_message', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 60 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.live_messages (
    live_id, user_id, kind, body, sender_label
  ) values (
    p_live_id, v_uid, 'system', v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text)
  from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

-- Stock: qty NULL em marketplace_product NÃO esconde vitrine broadcasting
create or replace function public.batata_live_item_stock(p_live_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_total integer;
  v_blocked integer := 0;
  v_blocked_orders integer := 0;
  v_blocked_cross_res integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_unit_price numeric;
  v_live_only boolean := false;
  v_uid uuid := auth.uid();
  v_staff boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_uid is not null and v_seller is not null then
    v_staff := public.batata_staff_has_permission(v_seller, 'can_manage_chat')
      or v_uid = v_seller;
  end if;

  if not coalesce(v_staff, false) then
    if not public.batata_live_is_broadcasting(v_li.live_id)
       or lower(trim(coalesce(v_li.status, ''))) in (
         'paused', 'inactive', 'sold', 'reserved_full'
       ) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    -- live_only exige quantity > 0; marketplace usa stock do produto (qty NULL OK)
    if lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only'
       and coalesce(v_li.quantity, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
  end if;

  v_live_only := lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only';
  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'pendente',
        'pedido_devolucao', 'em_devolucao'
      );

    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and lower(trim(li2.ref_code)) = lower(trim(v_li.ref_code))
      and coalesce(l2.seller_id, l2.vendedor_id) = v_seller;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
        and (
          o.live_item_id = v_li.id
          or (
            o.live_id = v_li.live_id
            and v_product_id is not null
            and o.product_id = v_product_id
          )
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live'
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where (
      public.batata_order_status_is_sold_fulfilled(o.status)
      or coalesce(o.stock_units_applied, 0) > 0
    )
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;
  if v_available < 0 then v_available := 0; end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p where p.id = v_li.product_id;
  else
    v_unit_price := v_li.price;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'live_id', v_li.live_id,
    'item_kind', v_li.item_kind,
    'product_id', v_li.product_id,
    'checkout_product_id', v_li.checkout_product_id,
    'ref_code', v_li.ref_code,
    'total_qty', v_total,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved_accepted,
    'pending_bag_qty', v_pending_bag,
    'sold_converted_qty', v_sold_converted,
    'available_qty', v_available,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated, service_role;

-- total_qty: buyer JWT fora de broadcasting → 0 (não oráculo)
create or replace function public.batata_live_item_total_qty(p_live_item_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_qty integer;
  v_seller uuid;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_staff boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_seller
  from public.lives l where l.id = v_li.live_id;

  if v_uid is not null and v_seller is not null then
    v_staff := v_uid = v_seller
      or public.batata_staff_has_permission(v_seller, 'can_manage_chat');
  end if;

  if v_role is distinct from 'service_role' and not coalesce(v_staff, false) then
    if not public.batata_live_is_broadcasting(v_li.live_id) then
      return 0;
    end if;
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    select p.quantity into v_qty from public.products p where p.id = v_li.product_id;
    if v_qty is null then return 0; end if;
    return greatest(v_qty, 0);
  end if;

  if v_li.item_kind = 'live_only' then
    if v_seller is not null then
      return public.batata_ref_history_pool_base_qty(
        v_seller, coalesce(v_li.logical_item_id, v_li.id)
      );
    end if;
  end if;

  return greatest(coalesce(v_li.quantity, 0), 0);
end;
$$;

revoke execute on function public.batata_live_item_total_qty(uuid) from anon;
grant execute on function public.batata_live_item_total_qty(uuid)
  to authenticated, service_role;

-- Reconcile: exige captura real (não aguarda_confirmacao sem PI)
create or replace function public.batata_live_reconcile_stripe_order(
  p_order_id uuid,
  p_reservation_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_request_id uuid;
  v_req public.live_reservation_requests%rowtype;
  v_convert jsonb;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_captured boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id;
  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_captured :=
    coalesce(v_order.amount_paid_cents, 0) > 0
    or coalesce(nullif(trim(v_order.stripe_payment_intent_id), ''), '') <> '';

  if not v_captured then
    return jsonb_build_object('ok', false, 'error', 'order_not_captured');
  end if;

  if lower(trim(coalesce(v_order.status, ''))) not in (
    'pago', 'enviado', 'entregue', 'concluido'
  ) then
    return jsonb_build_object(
      'ok', false, 'error', 'order_not_paid', 'status', v_order.status
    );
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null or v_role is distinct from 'authenticated' then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
    if v_uid is distinct from v_order.buyer_id
       and v_uid is distinct from v_order.seller_id
       and not public.batata_staff_has_permission(
         v_order.seller_id, 'can_manage_reservations'
       ) then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
  end if;

  v_request_id := p_reservation_request_id;

  if v_request_id is null and v_order.live_id is not null then
    select r.id into v_request_id
    from public.live_reservation_requests r
    where r.live_id = v_order.live_id
      and r.buyer_id = v_order.buyer_id
      and r.source = 'fleaber_live'
      and r.status in ('pending', 'accepted')
      and (
        v_order.live_item_id is null
        or r.live_item_id = v_order.live_item_id
      )
      and coalesce(r.notes, '') ilike (
        '%stripe_checkout:' || p_order_id::text || '%'
      )
    order by r.queue_position nulls last, r.created_at asc
    limit 1;
  end if;

  if v_request_id is null and v_order.live_id is not null then
    select r.id into v_request_id
    from public.live_reservation_requests r
    where r.live_id = v_order.live_id
      and r.buyer_id = v_order.buyer_id
      and r.source = 'fleaber_live'
      and r.status in ('pending', 'accepted')
      and (
        v_order.live_item_id is null
        or r.live_item_id = v_order.live_item_id
      )
    order by r.queue_position nulls last, r.created_at asc
    limit 1;
  end if;

  for v_req in
    select *
    from public.live_reservation_requests r
    where r.status in ('pending', 'accepted')
      and (
        (v_request_id is not null and r.id = v_request_id)
        or coalesce(r.notes, '') ilike (
          '%stripe_checkout:' || p_order_id::text || '%'
        )
      )
    order by r.queue_position nulls last, r.created_at asc
  loop
    update public.orders o
    set
      live_id = coalesce(o.live_id, v_req.live_id),
      live_item_id = coalesce(o.live_item_id, v_req.live_item_id),
      seller_id = coalesce(o.seller_id, v_req.seller_id)
    where o.id = p_order_id;
    select * into v_order from public.orders where id = p_order_id;

    v_convert := public.batata_live_reservation_stripe_convert(
      v_req.id, p_order_id
    );
    if coalesce((v_convert->>'ok')::boolean, false) then
      return v_convert || jsonb_build_object('reconciled', true);
    end if;
  end loop;

  if v_order.live_id is not null
     and v_order.live_item_id is not null
     and v_order.buyer_id is not null then
    if not exists (
      select 1 from public.live_reservation_requests r
      where r.live_id = v_order.live_id
        and r.buyer_id = v_order.buyer_id
        and r.live_item_id = v_order.live_item_id
        and r.status = 'converted'
        and (
          coalesce(r.notes, '') ilike ('%stripe_paid:' || p_order_id::text || '%')
          or coalesce(r.notes, '') ilike (
            '%stripe_paid_direct:' || p_order_id::text || '%'
          )
        )
    ) then
      insert into public.live_reservation_requests (
        live_id, live_item_id, seller_id, buyer_id,
        requested_qty, source, status, notes
      ) values (
        v_order.live_id, v_order.live_item_id, v_order.seller_id, v_order.buyer_id,
        greatest(coalesce(v_order.quantity, 1), 1),
        'fleaber_live', 'converted',
        'stripe_paid_direct:' || p_order_id::text
      );
    end if;

    return jsonb_build_object(
      'ok', true, 'direct_insert', true, 'live_item_id', v_order.live_item_id
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'no_request_to_convert');
end;
$$;

-- ===========================================================================
-- BI — hub_lives_discovery_public: mesmos filtros de playback que hub_lives_public
-- ===========================================================================
create or replace view public.hub_lives_discovery_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as seller_handle,
  nullif(trim(p.full_name), '') as seller_name,
  nullif(trim(p.photo_url), '') as seller_photo_url,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  case
    when lower(trim(coalesce(l.status, ''))) = 'live'
         and coalesce(l.is_active, false) = true
      then l.mux_playback_id
    else null
  end as mux_playback_id,
  case
    when lower(trim(coalesce(l.status, ''))) = 'ended'
      then l.mux_vod_playback_id
    else null
  end as mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
inner join public.profiles p
  on p.id = coalesce(l.seller_id, l.vendedor_id)
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = true
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'scheduled'
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
      and coalesce(p.hub_published, false) = true
    )
  );

grant select on public.hub_lives_discovery_public to anon, authenticated;

-- BI-P3: anon não consulta oráculo broadcasting
revoke execute on function public.batata_live_is_broadcasting(uuid) from anon;
grant execute on function public.batata_live_is_broadcasting(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
