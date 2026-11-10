-- AE/AF/AG P2/P3 residuais — 2026-09-01
-- production_touched: false · fase4: false
-- assert_json_card: ver sec_abacad_20260901_batata_part2.sql (com payment_lie)

create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* '(Seguro Fleaber|Seguro|Compra paga|MB\s*WAY|MBWAY|PIX|Transferência|Pagamento recebido|Pagamento confirmado|confirmado).*(\d+[,.]?\d*\s*(€|EUR)|€\s*\d+|\d+\s*€|\d+\s*EUR)';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text);
$$;

-- AG-P3 — order em live_item esgotado (mesmo sem product_id)
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

  if NEW.product_id is null then
    return NEW;
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

-- AG-P2-AG3 — REST live_items esconde esgotados para compradores
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
            and coalesce(
              (public.batata_live_item_stock(live_items.id)->>'available_qty')::int,
              0
            ) > 0
            and (
              public.batata_live_is_broadcasting(l.id)
              or exists (
                select 1 from public.hub_lives_public hlp where hlp.id = l.id
              )
            )
          )
        )
    )
  );

-- AG-P3-AG5 / AG-P3-AG2
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
  v_kind text;
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

  v_kind := lower(trim(coalesce(NEW.item_kind, '')));

  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and v_role is distinct from 'service_role' then
    if NEW.product_id is null
       and v_kind in ('', 'live_only') then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    elsif not v_can_mark then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    end if;
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
       and not public.batata_staff_has_permission(v_seller, 'can_mark_items_sold') then
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

notify pgrst, 'reload schema';
-- AB/AC/AD part2 — assert_json_card AC patches
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* '(Seguro Fleaber|Seguro|Compra paga|MB\s*WAY|MBWAY|PIX|Transferência|Pagamento recebido|Pagamento confirmado|confirmado).*(\d+[,.]?\d*\s*(€|EUR)|€\s*\d+|\d+\s*€|\d+\s*EUR)';
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
        if v_label ~ '\d'
           and v_label ~* '(Seguro|PIX|MB\s*WAY|MBWAY|Compra paga|Transferência|Pagamento)' then
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
