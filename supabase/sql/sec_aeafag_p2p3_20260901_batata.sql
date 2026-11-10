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
  v_li_status text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if NEW.live_item_id is not null then
    select lower(trim(coalesce(li.status, ''))) into v_li_status
    from public.live_items li where li.id = NEW.live_item_id;
    v_avail := coalesce(
      (public.batata_live_item_stock(NEW.live_item_id)->>'available_qty')::int, 0
    );
    if v_avail < 1
       or v_li_status in ('sold', 'reserved_full') then
      if TG_OP = 'INSERT' then
        raise exception 'order_live_item_exhausted' using errcode = '23514';
      end if;
      if TG_OP = 'UPDATE'
         and NEW.live_item_id is distinct from OLD.live_item_id then
        raise exception 'order_live_item_exhausted' using errcode = '23514';
      end if;
      v_new := lower(trim(coalesce(NEW.status, '')));
      if public.batata_order_status_holds_product_qty(v_new) then
        raise exception 'order_live_item_exhausted' using errcode = '23514';
      end if;
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
