-- AT→BE 2026-09-02 — fecho P0–P3 pós-blind POS_ANAS (12 reports)
-- production_touched: false · fase4: false

-- ===========================================================================
-- AT3 — product_offer_id imutável após selo (não detach → tier no preço oferta)
-- ===========================================================================
create or replace function public.batata_orders_guard_offer_id_seal()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if tg_op <> 'UPDATE' then
    return NEW;
  end if;
  if coalesce(auth.role(), '') = 'service_role' then
    return NEW;
  end if;
  if auth.uid() is null then
    return NEW;
  end if;
  if OLD.product_offer_id is not null
     and NEW.product_offer_id is distinct from OLD.product_offer_id then
    raise exception 'order_product_offer_id_immutable' using errcode = '42501';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_offer_id_seal on public.orders;
create trigger trg_batata_orders_guard_offer_id_seal
  before update of product_offer_id on public.orders
  for each row execute function public.batata_orders_guard_offer_id_seal();

-- ===========================================================================
-- AY/BE — FSM devolução: hops honestos
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

  -- BD-P2: pós-reembolso Stripe / anulada — sem enviado/entregue/concluido
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
    -- BE: comprador não marca «retorno entregue» (só vendedor após envio de volta)
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

    -- AY/BE: em_devolucao só após pedido_devolucao
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

    -- BE1: seller não inicia devolução a partir de pago/enviado sem pedido
    if v_new = 'em_devolucao' and v_old is distinct from 'pedido_devolucao' then
      raise exception 'order_em_devolucao_requires_pedido' using errcode = '42501';
    end if;

    -- AY3b: devolucao_entregue só a partir de em_devolucao
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

-- AX5 — shipped_at sempre now() no primeiro enviado (ignora backdate cliente)
create or replace function public.batata_set_order_shipped_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if lower(trim(coalesce(NEW.status, ''))) = 'enviado'
     and lower(trim(coalesce(OLD.status, ''))) is distinct from 'enviado' then
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
    raise exception 'order_shipped_at_immutable' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- AU/BA — denylist chat alargada (Klarna/iDEAL/Twint/…)
-- ===========================================================================
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|wise|revolut|mb\s*way|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o).{0,40}(confirmado|aprovado|processado|feito|caiu|€|eur|💶|\d)';
$$;

-- Extende guard JSON: label seguro + proof_url bound à order
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
      if v_buyer is null
         or position(('order_proofs/' || v_buyer::text || '/' || v_order::text || '/') in v_url) = 0 then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if public.batata_chat_normalize_lie_text(v_label) ~*
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|seguro|pago no mb|transfer|cart[aã]o|multibanco)' then
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

-- AY7 — proof_photos / return_label_url amarrados ao order_id da disputa
create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid := NEW.order_id;
  v_needle text;
begin
  select buyer_id into v_buyer from public.orders where id = v_oid;
  v_needle := case
    when v_buyer is not null and v_oid is not null then
      'order_disputes/' || v_buyer::text || '/' || v_oid::text
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
        if v_needle is null or position(v_needle in v_url) = 0 then
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
    if v_needle is null or position(v_needle in v_url) = 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- Replies proof_photos bind (se coluna existir no trigger de replies)
create or replace function public.batata_order_dispute_replies_guard_proof()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid;
  v_needle text;
begin
  if NEW.proof_photos is null then
    return NEW;
  end if;
  select d.order_id, o.buyer_id into v_oid, v_buyer
  from public.order_disputes d
  join public.orders o on o.id = d.order_id
  where d.id = NEW.dispute_id;
  v_needle := case
    when v_buyer is not null and v_oid is not null then
      'order_disputes/' || v_buyer::text || '/' || v_oid::text
    else null
  end;
  begin
    v_arr := to_jsonb(NEW.proof_photos);
  exception when others then
    raise exception 'dispute_proof_url_denied' using errcode = '23514';
  end;
  if jsonb_typeof(v_arr) <> 'array' then
    return NEW;
  end if;
  for v_url in
    select lower(trim(coalesce(elem, '')))
    from jsonb_array_elements_text(v_arr) as t(elem)
  loop
    if v_url = '' then continue; end if;
    if v_needle is null or position(v_needle in v_url) = 0 then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
  end loop;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_proof_urls
  on public.order_disputes;
create trigger trg_batata_order_disputes_guard_proof_urls
  before insert or update of proof_photos, return_label_url on public.order_disputes
  for each row execute function public.batata_order_disputes_guard_proof_urls();

drop trigger if exists trg_batata_order_dispute_replies_guard_proof
  on public.order_dispute_replies;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='order_dispute_replies'
      and column_name='proof_photos'
  ) then
    execute $t$
      create trigger trg_batata_order_dispute_replies_guard_proof
        before insert or update of proof_photos on public.order_dispute_replies
        for each row execute function public.batata_order_dispute_replies_guard_proof()
    $t$;
  end if;
end $$;

-- AW/BC — total_qty: anon perde oráculo (Hub usa stock gated + views)
revoke execute on function public.batata_live_item_total_qty(uuid) from anon;
grant execute on function public.batata_live_item_total_qty(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
