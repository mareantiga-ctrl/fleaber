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
