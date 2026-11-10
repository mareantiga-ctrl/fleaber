-- RT2120 Indep P1 + Blind B 2125 P1 (+ P2 dual-pool leve)
-- Classe raiz anon: SECURITY DEFINER + auth.uid() NULL salta IF NOT (...)
-- + GRANT drift anon EXECUTE.
-- Oferta: amount = unitário de 1 unidade (não N×).
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- Helper: exige JWT autenticado (service_role OK)
-- ---------------------------------------------------------------------------
create or replace function public.batata_require_authenticated_uid()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role = 'service_role' then
    return coalesce(v_uid, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;
  if v_uid is null or v_role is distinct from 'authenticated' then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

revoke all on function public.batata_require_authenticated_uid() from public, anon, authenticated;
grant execute on function public.batata_require_authenticated_uid() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- mark_live_item_sold — fail-closed se uid nulo; sem EXECUTE anon
-- ---------------------------------------------------------------------------
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
begin
  select li.* into v_li
  from public.live_items li
  where li.id = p_live_item_id;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  -- RT2120: anon/uid NULL NÃO passa (PL/pgSQL IF NULL = skip do then).
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

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    update public.products
    set is_sold = true, list_on_marketplace = false
    where id = v_li.product_id;
  else
    if v_li.checkout_product_id is not null then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.checkout_product_id;
    end if;
  end if;

  update public.live_reservation_requests
  set
    status = 'expired',
    notes = coalesce(notes || ' | ', '') || 'auto:item_vendido',
    updated_at = now()
  where live_item_id = v_li.id
    and status in ('pending', 'accepted');

  update public.live_items
  set
    status = 'sold',
    updated_at = now()
  where id = v_li.id;

  return public.batata_live_item_stock(v_li.id);
end;
$$;

revoke all on function public.batata_mark_live_item_sold(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_mark_live_item_sold(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- reconcile stripe order — authz fail-closed + idempotência notes
-- ---------------------------------------------------------------------------
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
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  if coalesce(v_order.price_total, 0) <= 0
     and v_order.product_id is not null then
    update public.orders o
    set price_total = p.price * greatest(coalesce(o.quantity, 1), 1)
    from public.products p
    where o.id = p_order_id
      and p.id = v_order.product_id
      and coalesce(o.price_total, 0) <= 0
      and coalesce(p.price, 0) > 0;
    select * into v_order from public.orders where id = p_order_id;
  end if;

  if lower(trim(coalesce(v_order.status, ''))) not in (
    'pago', 'enviado', 'aguarda_confirmacao'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_not_paid',
      'status', v_order.status
    );
  end if;

  -- RT2120: service_role OK; JWT só buyer/seller/staff; anon → not_allowed
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
      v_req.id,
      p_order_id
    );
    if coalesce((v_convert->>'ok')::boolean, false) then
      return v_convert || jsonb_build_object('reconciled', true);
    end if;
  end loop;

  if v_order.live_id is not null
     and v_order.live_item_id is not null
     and v_order.buyer_id is not null then
    -- Idempotência: stripe_paid: OU stripe_paid_direct:
    if not exists (
      select 1
      from public.live_reservation_requests r
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
        live_id,
        live_item_id,
        seller_id,
        buyer_id,
        requested_qty,
        source,
        status,
        notes
      )
      values (
        v_order.live_id,
        v_order.live_item_id,
        v_order.seller_id,
        v_order.buyer_id,
        greatest(coalesce(v_order.quantity, 1), 1),
        'fleaber_live',
        'converted',
        'stripe_paid_direct:' || p_order_id::text
      );
    end if;

    return jsonb_build_object(
      'ok', true,
      'direct_insert', true,
      'live_item_id', v_order.live_item_id
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'no_request_to_convert');
end;
$$;

revoke all on function public.batata_live_reconcile_stripe_order(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.batata_live_reconcile_stripe_order(uuid, uuid)
  to authenticated, service_role;

-- sync: mesma classe authz
create or replace function public.batata_sync_live_item_for_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_live_item_id uuid;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null or v_role is distinct from 'authenticated' then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
    if v_uid is distinct from v_order.seller_id
       and v_uid is distinct from v_order.buyer_id
       and not public.batata_staff_has_permission(
         v_order.seller_id, 'can_manage_reservations'
       ) then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
  end if;

  v_live_item_id := v_order.live_item_id;

  if v_live_item_id is null
     and v_order.live_id is not null
     and v_order.product_id is not null then
    select li.id into v_live_item_id
    from public.live_items li
    where li.live_id = v_order.live_id
      and li.product_id = v_order.product_id
    order by li.created_at desc
    limit 1;
  end if;

  if v_live_item_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_live_item');
  end if;

  if lower(trim(coalesce(v_order.status, ''))) in (
       'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
     )
     and v_order.buyer_id is not null then
    update public.live_reservation_requests r
    set
      status = 'converted',
      notes = case
        when coalesce(r.notes, '') ilike '%direct_paid:%' then r.notes
        else coalesce(nullif(trim(r.notes), '') || ' | ', '') ||
          'direct_paid:' || p_order_id::text
      end,
      updated_at = now()
    where r.live_item_id = v_live_item_id
      and r.buyer_id = v_order.buyer_id
      and r.status in ('pending', 'accepted');
  end if;

  return public.batata_recompute_live_item_status(v_live_item_id);
end;
$$;

revoke all on function public.batata_sync_live_item_for_order(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_sync_live_item_for_order(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Oferta aceite = 1 unidade ao preço negociado (RTBB-S-P1-01)
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

  if NEW.live_item_id is not null then
    select li.price into v_li
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0 then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  if v_unit_cents <= 0 and NEW.product_id is not null then
    select p.price into v_prod
    from public.products p
    where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_unit_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

  v_offer := null;
  if NEW.product_offer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.id = NEW.product_offer_id;
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
      -- RTBB-S-P1-01: oferta = 1 unidade ao preço aceite (não N× unitário).
      if v_auth_qty > 1 then
        raise exception 'offer_quantity_must_be_one' using errcode = '23514';
      end if;
      v_auth_qty := 1;
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
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
    if NEW.price_total is null or NEW.price_total < v_min_total then
      NEW.price_total := v_min_total;
    end if;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_seal_contract() is
  'SAT + 1755 + RTBB-S-P1-01: oferta aceite = qty 1 ao amount negociado.';

-- ---------------------------------------------------------------------------
-- P2: live accepted conta no hold de checkout marketplace
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_held_qty(
  p_product_id uuid,
  p_exclude_order_id uuid default null,
  p_exclude_order_ids uuid[] default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_held int := 0;
  v_live int := 0;
begin
  if p_product_id is null then
    return 0;
  end if;
  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = p_product_id
    and (p_exclude_order_id is null or o.id is distinct from p_exclude_order_id)
    and (
      p_exclude_order_ids is null
      or cardinality(p_exclude_order_ids) = 0
      or not (o.id = any (p_exclude_order_ids))
    )
    and coalesce(o.status, '') not in (
      'cancelado', 'cancelled', 'rejected', 'expired'
    )
    and public.batata_order_status_holds_product_qty(o.status);

  select coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
    into v_live
  from public.live_reservation_requests r
  join public.live_items li on li.id = r.live_item_id
  where r.status = 'accepted'
    and coalesce(li.product_id, li.checkout_product_id) = p_product_id;

  return v_held + v_live;
end;
$$;

notify pgrst, 'reload schema';
