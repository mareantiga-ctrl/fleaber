-- Fleaber BATATA: permitir Editar rápido (qty) via batata_update_live_item
-- sem abrir UPDATE directo em products (cliente / PostgREST).
--
-- Causa: trg batata_products_guard_quantity_authority bloqueava QUALQUER
-- aumento de products.quantity se o SKU tiver em live_items — incluindo o
-- RPC legítimo do vendedor no studio (erro genérico na app).
--
-- Fix: flag de sessão batata.live_item_qty_update=1 só dentro do RPC;
-- cliente directo continua bloqueado.
--
-- Aplicar em staging + produção. Não reabre buracos: active_order e
-- below_applied_stock mantêm-se.

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
  v_via_live_item boolean :=
    coalesce(current_setting('batata.live_item_qty_update', true), '') = '1';
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

  -- Bloqueio live_catalog: mantém-se para UPDATE directo no cliente.
  -- RPC batata_update_live_item arma a flag (Editar rápido).
  if NEW.quantity > OLD.quantity
     and not v_via_live_item
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

comment on function public.batata_products_guard_quantity_authority() is
  'Qty authority: bloqueia aumento em live_catalog excepto via batata_update_live_item (flag). Mantém active_order / below_held.';

-- Patch pontual: armar flag antes de tocar products.quantity.
-- Recria a função a partir do corpo canónico + 1 linha.
create or replace function public.batata_update_live_item(
  p_live_item_id uuid,
  p_quantity integer default null,
  p_price numeric default null,
  p_title text default null,
  p_clothing_size text default null,
  p_gender text default null,
  p_ref_code text default null,
  p_photo_url text default null,
  p_description text default null,
  p_list_on_marketplace boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_qty integer;
  v_old_price numeric;
  v_new_price numeric;
  v_should_broadcast boolean := false;
  v_pid uuid;
  v_eff_title text;
  v_eff_price numeric;
  v_eff_desc text;
  v_eff_photo text;
  v_eff_size text;
  v_eff_gender text;
  v_images text[];
begin
  select li.* into v_li
  from public.live_items li
  where li.id = p_live_item_id;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_change_current_item')
    or public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if coalesce(p_list_on_marketplace, false) is true then
    v_eff_title := coalesce(nullif(trim(p_title), ''), v_li.title);
    v_eff_price := coalesce(p_price, v_li.price);
    v_eff_photo := coalesce(nullif(trim(p_photo_url), ''), v_li.photo_url);
    v_eff_size := coalesce(nullif(trim(p_clothing_size), ''), v_li.clothing_size);
    v_eff_gender := coalesce(nullif(trim(p_gender), ''), v_li.gender);
    v_eff_desc := null;
    v_images := null;

    if v_li.product_id is not null then
      select
        coalesce(nullif(trim(p_description), ''), p.description),
        p.image_urls
      into v_eff_desc, v_images
      from public.products p
      where p.id = v_li.product_id;
    elsif v_li.checkout_product_id is not null then
      select
        coalesce(nullif(trim(p_description), ''), p.description),
        p.image_urls
      into v_eff_desc, v_images
      from public.products p
      where p.id = v_li.checkout_product_id;
    end if;

    if p_description is not null then
      v_eff_desc := nullif(trim(p_description), '');
    end if;

    if (v_eff_photo is null or trim(v_eff_photo) = '')
       and v_images is not null
       and coalesce(array_length(v_images, 1), 0) > 0 then
      v_eff_photo := nullif(trim(v_images[1]), '');
    end if;

    if v_eff_title is null or trim(v_eff_title) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_title');
    end if;
    if v_eff_price is null or v_eff_price < 1 then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_price');
    end if;
    if v_eff_desc is null or trim(v_eff_desc) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_description');
    end if;
    if v_eff_photo is null or trim(v_eff_photo) = '' then
      return jsonb_build_object('ok', false, 'error', 'marketplace_missing_photo');
    end if;
    if coalesce(nullif(trim(v_eff_size), ''), nullif(trim(v_eff_gender), '')) is not null then
      if v_eff_size is null or trim(v_eff_size) = '' then
        return jsonb_build_object('ok', false, 'error', 'marketplace_missing_size');
      end if;
      if v_eff_gender is null or trim(v_eff_gender) = '' then
        return jsonb_build_object('ok', false, 'error', 'marketplace_missing_color');
      end if;
    end if;
  end if;

  v_old_price := v_li.price;
  v_qty := greatest(coalesce(p_quantity, 1), 1);

  if p_price is not null
     and p_price is distinct from v_old_price
     and public.batata_live_item_price_locked(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'price_locked_after_sale');
  end if;

  -- Editar rápido / studio: autoriza aumento de stock no guarda (só este RPC).
  perform set_config('batata.live_item_qty_update', '1', true);

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    update public.products
    set
      quantity = coalesce(p_quantity, quantity),
      price = coalesce(p_price, price),
      title = coalesce(nullif(trim(p_title), ''), title),
      description = case when p_description is not null then nullif(trim(p_description), '') else description end,
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      list_on_marketplace = case
        when p_list_on_marketplace is not null then p_list_on_marketplace
        else list_on_marketplace
      end
    where id = v_li.product_id;

    update public.live_items
    set
      title = coalesce(nullif(trim(p_title), ''), title),
      price = coalesce(p_price, price),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      photo_url = case
        when p_photo_url is not null then nullif(trim(p_photo_url), '')
        else photo_url
      end,
      updated_at = now()
    where id = v_li.id;
  else
    update public.live_items
    set
      quantity = coalesce(p_quantity, quantity),
      price = coalesce(p_price, price),
      title = coalesce(nullif(trim(p_title), ''), title),
      ref_code = coalesce(nullif(trim(p_ref_code), ''), ref_code),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
      photo_url = case
        when p_photo_url is not null then nullif(trim(p_photo_url), '')
        else photo_url
      end,
      updated_at = now()
    where id = v_li.id;

    if coalesce(v_li.logical_item_id, v_li.id) is not null then
      perform public.batata_ensure_ref_history(
        v_seller,
        coalesce(v_li.logical_item_id, v_li.id),
        coalesce(
          (select ref_code from public.live_items where id = v_li.id),
          v_li.ref_code,
          ''
        ),
        (select title from public.live_items where id = v_li.id),
        (select photo_url from public.live_items where id = v_li.id),
        'history_updated'
      );
    end if;

    if v_li.checkout_product_id is not null then
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title),
        description = case when p_description is not null then nullif(trim(p_description), '') else description end,
        clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
        gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
        list_on_marketplace = case
          when p_list_on_marketplace is not null then p_list_on_marketplace
          else list_on_marketplace
        end
      where id = v_li.checkout_product_id;
    elsif p_list_on_marketplace is true then
      v_pid := public.batata_ensure_checkout_product(v_li.id);
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title),
        description = case when p_description is not null then nullif(trim(p_description), '') else description end,
        clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
        gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
        list_on_marketplace = true,
        is_sold = false
      where id = v_pid;
    end if;
  end if;

  perform public.batata_recompute_live_item_status(v_li.id);

  select li.price into v_new_price
  from public.live_items li
  where li.id = p_live_item_id;

  if p_price is not null and v_new_price is not null and v_new_price > 0 then
    if coalesce(v_old_price, 0) <= 0 then
      v_should_broadcast := true;
    elsif v_old_price is distinct from v_new_price then
      v_should_broadcast := true;
    end if;
  end if;

  if v_should_broadcast then
    perform public.batata_live_price_defined_broadcast(
      v_li.live_id,
      v_li.id,
      v_new_price
    );
  end if;

  return public.batata_live_item_stock(v_li.id);
end;
$$;

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text, text, text, boolean) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text, text, text, boolean) to authenticated;
