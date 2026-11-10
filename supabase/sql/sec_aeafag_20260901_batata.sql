-- AE / AF / AG 2026-09-01 — pós-refutação ABACAD (P0–P3, sem P4)
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- AE-P0 — contrato: live ended não usa preço histórico abaixo do catálogo
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_seal_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_jwt boolean := (v_role = 'authenticated' and v_uid is not null);
  v_unit_cents int := 0;
  v_li numeric;
  v_prod numeric;
  v_prod_cents int := 0;
  v_live_id uuid;
  v_offer public.product_offers%rowtype;
  v_auth_qty int;
  v_res_qty int := 0;
  v_client_offer_id uuid;
  v_min_total numeric;
begin
  v_client_offer_id := NEW.product_offer_id;

  if v_jwt then
    NEW.contract_unit_cents := null;
    NEW.contract_qty := null;
  elsif NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    NEW.quantity := NEW.contract_qty;
    return NEW;
  end if;

  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  v_auth_qty := greatest(coalesce(NEW.quantity, 1), 1);
  if v_auth_qty > 99 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;

  if v_jwt
     and NEW.live_item_id is not null
     and NEW.buyer_id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_res_qty
    from public.live_reservation_requests r
    where r.live_item_id = NEW.live_item_id
      and r.buyer_id = NEW.buyer_id
      and r.status in ('accepted', 'converted');
    if v_res_qty > 0 and v_auth_qty > v_res_qty then
      raise exception 'order_quantity_exceeds_reservation'
        using errcode = '23514';
    end if;
  end if;

  if NEW.product_id is not null then
    select p.price into v_prod from public.products p where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_prod_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

  if NEW.live_item_id is not null then
    select li.price, li.live_id into v_li, v_live_id
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0
       and v_live_id is not null
       and public.batata_live_is_broadcasting(v_live_id) then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  if v_unit_cents <= 0 and v_prod_cents > 0 then
    v_unit_cents := v_prod_cents;
  elsif v_unit_cents > 0 and v_prod_cents > 0
        and (NEW.live_item_id is null
             or not public.batata_live_is_broadcasting(
               (select li.live_id from public.live_items li where li.id = NEW.live_item_id limit 1)
             )) then
    v_unit_cents := greatest(v_unit_cents, v_prod_cents);
  end if;

  v_offer := null;
  if NEW.product_offer_id is not null then
    select * into v_offer from public.product_offers po where po.id = NEW.product_offer_id;
  elsif NEW.product_id is not null and NEW.buyer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.product_id = NEW.product_id
      and po.buyer_id = NEW.buyer_id
      and (NEW.seller_id is null or po.seller_id = NEW.seller_id)
      and lower(trim(coalesce(po.status, ''))) = 'accepted'
      and (po.expires_at is null or po.expires_at > now())
      and not public.batata_product_offer_is_consumed(po.id, NEW.id)
    order by coalesce(po.responded_at, po.created_at) desc
    limit 1;
  end if;

  if v_offer.id is not null then
    if lower(trim(coalesce(v_offer.status, ''))) is distinct from 'accepted'
       or v_offer.product_id is distinct from NEW.product_id
       or v_offer.buyer_id is distinct from NEW.buyer_id
       or (NEW.seller_id is not null and v_offer.seller_id is distinct from NEW.seller_id)
       or (v_offer.expires_at is not null and v_offer.expires_at <= now())
       or coalesce(v_offer.amount, 0) <= 0
       or v_offer.responded_at is null then
      NEW.product_offer_id := null;
    elsif public.batata_product_offer_is_consumed(v_offer.id, NEW.id) then
      if v_client_offer_id is not null then
        raise exception 'offer_already_consumed' using errcode = '23514';
      end if;
      NEW.product_offer_id := null;
    else
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
      if v_auth_qty > 1 then
        raise exception 'offer_quantity_must_be_one' using errcode = '23514';
      end if;
      v_auth_qty := 1;
    end if;
  else
    if v_client_offer_id is not null
       and public.batata_product_offer_is_consumed(v_client_offer_id, NEW.id) then
      raise exception 'offer_already_consumed' using errcode = '23514';
    end if;
    NEW.product_offer_id := null;
  end if;

  if v_unit_cents <= 0 then
    raise exception 'order_contract_price_missing' using errcode = '23514';
  end if;

  NEW.contract_unit_cents := v_unit_cents;
  NEW.contract_qty := v_auth_qty;
  NEW.quantity := v_auth_qty;

  if v_jwt then
    v_min_total := (v_unit_cents::numeric * v_auth_qty::numeric) / 100.0;
    NEW.price_total := round(v_min_total, 2);
    if NEW.product_offer_id is null
       and lower(coalesce(NEW.payment_method, '')) like '%proposta%' then
      NEW.payment_method := 'Pagamento na app';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AG-P2 regressão — mark_sold RPC pode gravar status=sold (flag interna)
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
  v_has_any_res boolean := false;
  v_reserved int := 0;
  v_prod_qty int;
  v_is_staff boolean := false;
  v_can_mark boolean := false;
  v_mark_sold_internal boolean := false;
begin
  v_mark_sold_internal :=
    coalesce(current_setting('batata.mark_sold_internal', true), '') = '1';

  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and lower(trim(coalesce(NEW.status, ''))) = 'sold'
     and lower(trim(coalesce(OLD.status, ''))) is distinct from 'sold'
     and not v_mark_sold_internal
     and v_role is distinct from 'service_role' then
    raise exception 'live_item_status_sold_rpc_only' using errcode = '42501';
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id) into v_live_owner
    from public.lives l where l.id = NEW.live_id limit 1;
  end if;

  if v_live_owner is not null then
    v_is_staff := v_live_owner is distinct from v_uid
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations');
    v_can_mark := v_live_owner = v_uid
      or public.batata_staff_has_permission(v_live_owner, 'can_mark_items_sold');
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin() and not v_is_staff then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and not v_can_mark then
    raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE' and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
    ) into v_has_any_res;
    if v_has_any_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity into v_product_seller, v_prod_qty
    from public.products p where p.id = NEW.product_id limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    if v_prod_qty is not null and coalesce(NEW.quantity, 0) > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

create or replace function public.batata_mark_live_item_sold(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_uid uuid;
  v_role text := coalesce(auth.role(), '');
  v_has_paid boolean := false;
begin
  select li.* into v_li from public.live_items li where li.id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_role is distinct from 'service_role' then
    v_uid := auth.uid();
    if v_uid is null or v_role is distinct from 'authenticated' then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
    if v_uid is distinct from v_seller
       and not public.batata_staff_has_permission(v_seller, 'can_mark_items_sold')
       and not public.batata_staff_has_permission(v_seller, 'can_change_current_item')
    then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
  end if;

  if v_li.product_id is not null
     or lower(trim(coalesce(v_li.item_kind, ''))) = 'marketplace_product' then
    select exists (
      select 1 from public.orders o
      where o.live_item_id = v_li.id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'enviado', 'entregue', 'concluido'
        )
        and (
          coalesce(o.amount_paid_cents, 0) > 0
          or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
        )
    ) into v_has_paid;
    if coalesce(v_has_paid, false) then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.product_id;
      if v_li.checkout_product_id is not null
         and v_li.checkout_product_id is distinct from v_li.product_id then
        update public.products
        set is_sold = true, list_on_marketplace = false
        where id = v_li.checkout_product_id;
      end if;
    end if;
  else
    if v_li.checkout_product_id is not null then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.checkout_product_id;
    end if;
  end if;

  update public.live_reservation_requests
  set status = 'expired',
      notes = coalesce(notes || ' | ', '') || 'auto:item_vendido',
      updated_at = now()
  where live_item_id = v_li.id
    and status in ('pending', 'accepted');

  perform set_config('batata.mark_sold_internal', '1', true);
  update public.live_items
  set status = 'sold', updated_at = now()
  where id = v_li.id;
  perform set_config('batata.mark_sold_internal', '', true);

  perform public.batata_recompute_live_item_status(v_li.id);

  return public.batata_live_item_stock(v_li.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- AG-P2/P3 — MB WAY: seller não marca pago sem comprovativo
-- AG-P3 — order em item esgotado (marketplace path)
-- ---------------------------------------------------------------------------
-- Patch paid_status seller pago for off-platform — read yzaa and patch

create or replace function public.batata_orders_guard_product_hold_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_new text;
  v_old text;
  v_need int;
  v_check jsonb;
  v_avail int := 0;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if NEW.product_id is null then
    return NEW;
  end if;

  if NEW.live_item_id is not null then
    v_avail := coalesce(
      (public.batata_live_item_stock(NEW.live_item_id)->>'available_qty')::int, 0
    );
    if v_avail < 1
       and public.batata_order_status_holds_product_qty(
         lower(trim(coalesce(NEW.status, '')))
       ) then
      raise exception 'order_live_item_exhausted' using errcode = '23514';
    end if;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_old := case when TG_OP = 'UPDATE'
    then lower(trim(coalesce(OLD.status, '')))
    else '' end;

  if not public.batata_order_status_holds_product_qty(v_new) then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and public.batata_order_status_holds_product_qty(v_old)
     and v_new is not distinct from v_old then
    return NEW;
  end if;

  v_need := greatest(coalesce(NEW.quantity, 1), 1);
  v_check := public.batata_product_checkout_available(
    NEW.product_id,
    NEW.id,
    v_need
  );

  if coalesce((v_check->>'ok')::boolean, false) is not true then
    raise exception 'order_hold_exceeds_stock'
      using errcode = '23514';
  end if;

  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
-- AE/AF/AG part2 — chat AF + MB WAY pago guard

create or replace function public.batata_chat_strip_unicode_ws(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    replace(coalesce(p_text, ''), U&'\FEFF', ''),
    '[' || chr(9) || chr(10) || chr(11) || chr(12) || chr(13) || chr(32)
      || chr(133) || chr(160) || chr(5760) || chr(8192) || chr(8193)
      || chr(8194) || chr(8195) || chr(8196) || chr(8197) || chr(8198)
      || chr(8199) || chr(8200) || chr(8201) || chr(8202) || chr(8232)
      || chr(8233) || chr(8239) || chr(8287) || chr(12288) || ']+',
    '',
    'g'
  );
$$;

-- MB WAY: seller não marca pago sem proof_url
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
  v_proof text;
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
      if public.batata_is_off_platform_payment(v_pm) then
        if v_proof = '' then
          NEW.status := OLD.status;
          return NEW;
        end if;
      elsif not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        if public.batata_is_off_platform_payment(v_pm) and v_old = 'pago' and v_proof <> '' then
          null;
        else
          NEW.status := OLD.status;
          return NEW;
        end if;
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
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

-- Inbox regex alargado (AF-P2-03)
create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* '(Seguro Fleaber|Compra paga|MB\s*WAY|MBWAY|PIX|Transferência|Pagamento recebido).*(\d+[,.]?\d*\s*(€|EUR)|€\s*\d+)';
$$;

create or replace function public.batata_chats_guard_insert()
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
  if not (NEW.user_a = v_uid or NEW.user_b = v_uid) then
    return NEW;
  end if;
  if public.batata_chat_is_forged_inbox_preview(NEW.last_message) then
    raise exception 'chat_inbox_preview_forbidden' using errcode = '42501';
  end if;
  if NEW.last_message_time is not null
     and NEW.last_message_time < now() - interval '30 seconds' then
    NEW.last_message_time := now();
  end if;
  if NEW.last_message_time is not null
     and NEW.last_message_time > now() + interval '5 minutes' then
    NEW.last_message_time := now();
  end if;
  return NEW;
end;
$fn$;

create or replace function public.batata_chats_guard_update()
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
  if not public.batata_chat_is_participant(NEW.id) then
    return NEW;
  end if;
  if NEW.last_message is distinct from OLD.last_message
     and public.batata_chat_is_forged_inbox_preview(NEW.last_message) then
    raise exception 'chat_inbox_preview_forbidden' using errcode = '42501';
  end if;
  if NEW.last_message_time is distinct from OLD.last_message_time then
    if NEW.last_message_time < now() - interval '30 seconds'
       or NEW.last_message_time > now() + interval '5 minutes' then
      NEW.last_message_time := now();
    end if;
  end if;
  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
-- AB/AC/AD part2 — assert_json_card AC patches
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
  v_raw text := replace(coalesce(p_text, ''), U&'\FEFF', '');
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
        if v_label ~* '(Seguro|PIX|MB\s*WAY|MBWAY|Compra paga|Transferência|Pagamento).*(\d+[,.]?\d*\s*(€|EUR)|€\s*\d+)'
           and abs(
             coalesce(
               nullif(regexp_replace(v_label, '[^0-9,.]', '', 'g'), '')::numeric,
               0
             ) - round(v_paid_cents::numeric / 100.0, 2)
           ) > 0.05 then
          raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
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
