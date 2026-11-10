-- AN–AS 2026-09-02 — fecho P0–P3 pós-blind POS_AHAM
-- production_touched: false · fase4: false
-- BATATA: sem enfraquecer RLS; mínimo necessário.

-- ===========================================================================
-- AR7 / AS2 / AS5 — FSM encomenda (buyer concluido em devolução; seller entregue/concluido)
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

    -- AR7: não «concluir» a meio da devolução (trava refund/devolvida do seller)
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

    -- AS5: só o comprador confirma receção / conclusão
    if v_new = 'concluido' then
      raise exception 'order_seller_cannot_mark_concluido' using errcode = '42501';
    end if;

    -- AS2: seller marca enviado; entregue é do comprador (e exige enviado)
    if v_new = 'entregue' then
      raise exception 'order_seller_cannot_mark_entregue' using errcode = '42501';
    end if;

    if v_new = 'enviado' then
      if v_old is distinct from 'pago' and not v_captured then
        raise exception 'order_ship_requires_pago' using errcode = '42501';
      end if;
    end if;

    -- AS3: devolvida só após devolução entregue (sem atalho disputa→devolvida)
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

-- AR5 — unship silencioso → 403 explícito
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
    raise exception 'order_shipped_at_immutable' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- AS5 — return_delivered_at só via hop devolucao_entregue (seller)
create or replace function public.batata_orders_guard_return_delivered_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if tg_op <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.return_delivered_at is not distinct from OLD.return_delivered_at then
    return NEW;
  end if;
  if coalesce(auth.role(), '') = 'service_role' then
    return NEW;
  end if;
  if auth.uid() is null or coalesce(auth.role(), '') is distinct from 'authenticated' then
    return NEW;
  end if;
  -- Só permitir selar ao passar a devolucao_entregue; limpar/forjar recusado
  if OLD.return_delivered_at is not null then
    raise exception 'order_return_delivered_at_immutable' using errcode = '42501';
  end if;
  if lower(trim(coalesce(NEW.status, ''))) is distinct from 'devolucao_entregue'
     or lower(trim(coalesce(OLD.status, ''))) is not distinct from 'devolucao_entregue' then
    raise exception 'order_return_delivered_at_denied' using errcode = '42501';
  end if;
  if NEW.seller_id is distinct from auth.uid() then
    raise exception 'order_return_delivered_at_denied' using errcode = '42501';
  end if;
  NEW.return_delivered_at := coalesce(NEW.return_delivered_at, now());
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_return_delivered on public.orders;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'return_delivered_at'
  ) then
    execute $t$
      create trigger trg_batata_orders_guard_return_delivered
        before update of return_delivered_at on public.orders
        for each row execute function public.batata_orders_guard_return_delivered_at()
    $t$;
  end if;
end $$;

-- AS5/AS8 — release exige envio real (ou mão) + status concluido
create or replace function public.batata_release_seller_wallet_for_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_product_title text;
  v_amount numeric;
  v_base numeric;
  v_remaining numeric;
  v_done boolean;
  v_cleared int;
  v_ship text;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id is null then
    return false;
  end if;

  if auth.uid() is not null and auth.uid() <> v_order.buyer_id
     and coalesce(auth.role(), '') = 'authenticated'
     and not public.batata_is_admin() then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido') then
    return false;
  end if;

  v_ship := coalesce(v_order.shipping_method, '');
  if v_order.shipped_at is null
     and not public.batata_shipping_method_is_hand(v_ship) then
    return false;
  end if;

  if v_order.wallet_release_processed_at is not null then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  if exists (
    select 1 from public.order_disputes d
    where d.order_id = v_order.id
      and lower(coalesce(d.status, '')) is distinct from 'recusada'
      and lower(coalesce(d.status, '')) is distinct from 'fechada'
      and lower(coalesce(d.status, '')) is distinct from 'resolvida'
  ) then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    update public.orders
    set wallet_release_processed_at = now(),
        wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now())
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  if exists (
    select 1 from public.stripe_checkout_events e
    where e.order_id = v_order.id
      and lower(coalesce(e.event, '')) in ('refund_created', 'charge.refunded')
  ) then
    update public.orders
    set wallet_release_processed_at = now(),
        wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now())
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);

  if v_base <= 0 or v_remaining <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0 and v_base <= 0;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products where id = v_order.product_id;

  v_amount := least(
    greatest(v_base - public.batata_order_commission_amount(v_base), 0),
    v_remaining
  );

  if v_amount <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.seller_id, v_order.id, v_amount, 'venda',
    'Venda de ' || coalesce(v_product_title, 'artigo Fleaber')
  );

  if v_done then
    perform public.batata_record_fleaber_commission_once(
      v_order.id, public.batata_order_commission_amount(v_base),
      'protection_fee', 'Taxa de Proteção Fleaber'
    );
    update public.orders set wallet_release_processed_at = now() where id = v_order.id;
  end if;
  return v_done;
end;
$$;

revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

-- AS4 — refund em devolvida mantém terminal devolvida (não mente cancelado)
create or replace function public.batata_finalize_stripe_order_refund(
  p_order_id uuid,
  p_refund_id text,
  p_payment_intent_id text default null,
  p_session_id text default null,
  p_amount_cents integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_status text;
  v_already boolean := false;
  v_terminal text;
begin
  if p_order_id is null or nullif(trim(coalesce(p_refund_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  v_terminal := case
    when v_status = 'devolvida' then 'devolvida'
    else 'cancelado'
  end;

  if nullif(trim(coalesce(v_order.stripe_refund_id, '')), '') is not null then
    v_already := true;
    if v_status is distinct from v_terminal
       and v_status is distinct from 'cancelado'
       and v_status is distinct from 'cancelled'
       and v_status is distinct from 'devolvida' then
      update public.orders
      set status = v_terminal
      where id = p_order_id;
    end if;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'already_refunded', true,
      'refund_id', v_order.stripe_refund_id,
      'status', coalesce(
        (select lower(trim(status)) from public.orders where id = p_order_id),
        v_terminal
      ),
      'stock_units_applied', (
        select stock_units_applied from public.orders where id = p_order_id
      )
    );
  end if;

  update public.orders
  set
    stripe_refund_id = trim(p_refund_id),
    stripe_refunded_at = coalesce(stripe_refunded_at, now()),
    stripe_payment_intent_id = coalesce(
      nullif(trim(coalesce(p_payment_intent_id, '')), ''),
      stripe_payment_intent_id
    ),
    stripe_checkout_session_id = coalesce(
      nullif(trim(coalesce(p_session_id, '')), ''),
      stripe_checkout_session_id
    ),
    amount_paid_cents = coalesce(
      amount_paid_cents,
      case when p_amount_cents is not null and p_amount_cents > 0 then p_amount_cents else null end
    ),
    status = v_terminal
  where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'already_refunded', false,
    'refund_id', trim(p_refund_id),
    'status', v_terminal,
    'stock_units_applied', (
      select stock_units_applied from public.orders where id = p_order_id
    )
  );
end;
$$;

revoke all on function public.batata_finalize_stripe_order_refund(uuid, text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.batata_finalize_stripe_order_refund(uuid, text, text, text, integer)
  to service_role;

-- AS7 — storage: sem ramo raso order_proofs/{buyer}/ficheiro
drop policy if exists fleaber_private_select_order_counterparty on storage.objects;
create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
            and name like (
              'order_proofs/' || o.buyer_id::text || '/' || o.id::text || '/%'
            )
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where (o.seller_id = auth.uid() or o.buyer_id = auth.uid())
            and (
              name like ('order_disputes/' || o.buyer_id::text || '/' || o.id::text || '%')
              or name like ('order_disputes/' || o.buyer_id::text || '/' || o.id::text || '/%')
            )
            and (
              lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
              or exists (
                select 1 from public.order_disputes d
                where d.order_id = o.id
                  and lower(coalesce(d.status, '')) not in ('recusada', 'resolvida')
              )
            )
        )
      )
    )
  );

-- AS7-P2 — proof_photos: só fleaber_private (sign/authenticated), sem public/
create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_arr jsonb;
begin
  if NEW.proof_photos is null then
    return NEW;
  end if;
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
    if v_url = '' then
      continue;
    end if;
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
       or v_url ~ '[\n\r<>"]' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url like '%/object/public/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url not like '%/object/sign/fleaber_private/%'
       and v_url not like '%/object/authenticated/fleaber_private/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
  end loop;
  return NEW;
end;
$fn$;

-- ===========================================================================
-- AO — chat mentiras / image public / notes HTML / NBSP delete
-- ===========================================================================
create or replace function public.batata_chat_normalize_lie_text(p_text text)
returns text
language sql
immutable
as $$
  select lower(
    translate(
      public.batata_chat_strip_format_controls(coalesce(p_text, '')),
      -- cirílico lookalike comum + NBSP
      E'еЕаАоОрРсСхХуУіІ\u00A0',
      E'eeaaооррссххууii '
    )
  );
$$;

create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|venmo|sepa|mbnet|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?)|€\s*\d+|\d+\s*€|\d+\s*eur)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|paypal|bizum|wise|revolut|apple\s*pay|venmo|sepa|mbnet|reembolso|refund|estorno).*(confirmado|banco|recebido|aprovado|processado|feito|caiu)'
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
      '(wise|revolut|apple\s*pay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|reembolso|refund|estorno|pagamento|transfer|recebi).{0,40}(confirmado|aprovado|processado|feito|caiu|€|eur|\d)';
$$;

-- AO4 — chat_image url não pode ser public bucket
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
      if v_path <> '' and position(lower(v_path) in v_url) = 0
         and v_url not like ('%/chat_uploads/' || NEW.sender_id::text || '/%') then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'reservation_payment_submitted' then
    v_notes := coalesce(v_json->>'notes', '');
    if v_notes ~ '[<>]' then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if public.batata_chat_normalize_lie_text(v_label) ~*
       '(wise|revolut|apple|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|seguro|pago no mb|transfer)' then
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

drop trigger if exists trg_batata_chat_messages_guard_image_url on public.chat_messages;
create trigger trg_batata_chat_messages_guard_image_url
  before insert or update on public.chat_messages
  for each row execute function public.batata_chat_messages_guard_image_url();

-- AO5-P3 — DELETE: tratar NBSP/Zs antes do prefixo JSON
create or replace function public.batata_chat_messages_guard_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text;
  v_norm text;
begin
  if coalesce(auth.role(), '') = 'authenticated' and auth.uid() is not null then
    v_raw := coalesce(OLD.text, '');
    v_norm := ltrim(
      translate(
        v_raw,
        E'\u00A0\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u202F\u205F\u3000',
        '                '
      )
    );
    if v_norm like 'FLEABER_JSON_V1:%'
       or btrim(v_norm) like '{%' then
      raise exception 'chat_system_card_immutable' using errcode = '42501';
    end if;
  end if;
  return OLD;
end;
$fn$;

-- AN-P3 — bundle INSERT hostil: rejeitar status/total forjados (não 201 mentiroso)
create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
  v_dead int := 0;
  v_new_st text;
  v_old_st text;
  v_sub numeric(12, 2);
  v_pct numeric(5, 2);
  v_disc numeric(12, 2);
  v_client_total numeric(12, 2);
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
      NEW.discount_pct := 0;
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;

    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;

    select count(*)::int into v_dead
    from unnest(NEW.product_ids) as pid
    join public.products p on p.id = pid
    where coalesce(p.list_on_marketplace, false) = false
       or coalesce(p.is_sold, false) = true;
    if v_dead > 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;

    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);

    -- Cliente não pode forjar total baixo no INSERT
    begin
      v_client_total := NEW.total_eur;
    exception when others then
      v_client_total := null;
    end;
    -- NEW.total_eur já recalculado; se o cliente mandou total distinto via coluna
    -- antes do rewrite, PostgREST passa o valor em NEW — já sobrescrevemos.
    -- Extra: se discount_pct buyer ≠ 0 já forçado a 0 acima.
    return NEW;
  end if;

  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    if v_new_st = 'accepted' and v_uid is distinct from OLD.seller_id then
      raise exception 'bundle_accept_seller_only' using errcode = '42501';
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_party' using errcode = '42501';
    end if;
  end if;

  if v_uid is distinct from OLD.seller_id then
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.total_eur := OLD.total_eur;
  else
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    else
      v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
      v_disc := round(v_sub * (v_pct / 100.0), 2);
      NEW.subtotal_eur := v_sub;
      NEW.discount_pct := v_pct;
      NEW.discount_eur := v_disc;
      NEW.total_eur := greatest(v_sub - v_disc, 0);
    end if;
  end if;

  if v_old_st in ('accepted', 'rejected', 'cancelled', 'cancelado', 'expired', 'purchased') then
    NEW.status := OLD.status;
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- AP — purchase broadcast só com compra paga; pending em ended bloqueado
-- ===========================================================================
create or replace function public.batata_live_purchase_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_name text;
  v_ref text;
  v_title text;
  v_label text;
  v_body text;
  v_paid boolean := false;
begin
  if p_live_id is null or p_buyer_id is null or p_live_item_id is null then
    return false;
  end if;

  select coalesce(l.seller_id, l.vendedor_id)
  into v_seller
  from public.lives l
  where l.id = p_live_id;

  if v_seller is null then
    return false;
  end if;

  -- JWT: buyer próprio OU seller/staff — e sempre com order paga do item
  if v_role = 'authenticated' and v_uid is not null then
    if v_uid is distinct from p_buyer_id
       and v_uid is distinct from v_seller
       and not public.batata_staff_has_permission(v_seller, 'can_manage_chat') then
      return false;
    end if;
  end if;

  select exists (
    select 1
    from public.orders o
    where o.buyer_id = p_buyer_id
      and o.live_item_id = p_live_item_id
      and o.live_id is not distinct from p_live_id
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa'
      )
  ) into v_paid;

  if not coalesce(v_paid, false) then
    return false;
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Comprador')
  into v_name
  from public.profiles
  where id = p_buyer_id;

  select coalesce(nullif(trim(ref_code), ''), ''),
         coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title
  from public.live_items
  where id = p_live_item_id
  limit 1;

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  else
    v_label := 'artigo';
  end if;

  v_body := '✅ ' || v_name || ' comprou ' || v_label;

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.kind = 'system'
      and m.user_id = p_buyer_id
      and m.body = v_body
      and m.created_at > now() - interval '15 minutes'
  ) then
    return true;
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    p_buyer_id,
    'system',
    v_body,
    v_name
  );

  return true;
end;
$$;

revoke all on function public.batata_live_purchase_broadcast(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid)
  to authenticated, service_role;

-- AP-P3 — não entrar na fila se live ended
create or replace function public.batata_live_reservation_requests_guard_live_active()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_live_id uuid;
begin
  select li.live_id into v_live_id
  from public.live_items li
  where li.id = NEW.live_item_id;
  if v_live_id is null then
    raise exception 'live_item_not_found' using errcode = '23514';
  end if;
  if not public.batata_live_is_broadcasting(v_live_id) then
    raise exception 'live_ended' using errcode = '42501';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_requests_live_active
  on public.live_reservation_requests;
create trigger trg_batata_live_reservation_requests_live_active
  before insert on public.live_reservation_requests
  for each row execute function public.batata_live_reservation_requests_guard_live_active();

-- ===========================================================================
-- AQ — Hub REST hitch qty>0; stock anon: ver sec_anas_stock_gate (GRANT+gate)
-- ===========================================================================
-- NÃO revoke anon em batata_live_item_stock — Hub views precisam EXECUTE.
-- Gate AQ-P3 vive em sec_anas_stock_gate_20260902.sql.
drop policy if exists "live_items_select_for_live" on public.live_items;
create policy "live_items_select_for_live"
  on public.live_items
  for select
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (
          auth.uid() = l.seller_id
          or auth.uid() = l.vendedor_id
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_view_live_dashboard'
          )
          or (
            coalesce(live_items.is_active, false) = true
            and lower(trim(coalesce(live_items.status, ''))) not in (
              'paused', 'inactive', 'sold', 'reserved_full'
            )
            and coalesce(live_items.quantity, 0) > 0
            and coalesce(
              (public.batata_live_item_stock(live_items.id)->>'available_qty')::int,
              0
            ) > 0
            and public.batata_live_is_broadcasting(l.id)
          )
        )
    )
  );

notify pgrst, 'reload schema';
