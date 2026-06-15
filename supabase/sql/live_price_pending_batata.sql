-- Fleaber BATATA V1: artigo live_only sem preço — sync shadow, bloqueio pós-venda, broadcast.
-- Incluir em live_ops_hotfix_batata.sql (deploy completo).

-- ---------------------------------------------------------------------------
-- Helper: item já teve venda/pagamento convertido
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_item_price_locked(p_live_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.live_reservation_requests r
    where r.live_item_id = p_live_item_id
      and r.status = 'converted'
  )
  or exists (
    select 1
    from public.orders o
    where o.live_item_id = p_live_item_id
      and lower(trim(coalesce(o.status, ''))) in ('pago', 'paid')
  );
$$;

-- ---------------------------------------------------------------------------
-- Broadcast chat: preço definido (debounce por corpo + 15 min)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_price_defined_broadcast(
  p_live_id uuid,
  p_live_item_id uuid,
  p_price numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_ref text;
  v_label text;
  v_body text;
  v_price_txt text;
  v_uid uuid := auth.uid();
begin
  if p_live_id is null or p_live_item_id is null then
    return false;
  end if;
  if p_price is null or p_price <= 0 then
    return false;
  end if;

  select coalesce(nullif(trim(title), ''), ''),
         coalesce(nullif(trim(ref_code), ''), '')
  into v_title, v_ref
  from public.live_items
  where id = p_live_item_id
  limit 1;

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := v_ref;
  else
    v_label := 'artigo';
  end if;

  v_price_txt := replace(trim(to_char(p_price, 'FM999999990.00')), '.', ',');
  v_body := '💶 Preço definido · ' || v_label || ' · ' || v_price_txt || '€';

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.kind = 'system'
      and m.body = v_body
      and m.created_at > now() - interval '15 minutes'
  ) then
    return false;
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    coalesce(v_uid, (select coalesce(l.seller_id, l.vendedor_id) from public.lives l where l.id = p_live_id)),
    'system',
    v_body,
    'Sistema'
  );

  return true;
end;
$$;

revoke all on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) from public;
grant execute on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) to authenticated;
grant execute on function public.batata_live_price_defined_broadcast(uuid, uuid, numeric) to service_role;

-- ---------------------------------------------------------------------------
-- batata_update_live_item — sync shadow price, lock pós-venda, broadcast
-- ---------------------------------------------------------------------------
create or replace function public.batata_update_live_item(
  p_live_item_id uuid,
  p_quantity integer default null,
  p_price numeric default null,
  p_title text default null,
  p_clothing_size text default null,
  p_gender text default null,
  p_ref_code text default null
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

  v_old_price := v_li.price;
  v_qty := greatest(coalesce(p_quantity, 1), 1);

  if p_price is not null
     and p_price is distinct from v_old_price
     and public.batata_live_item_price_locked(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'price_locked_after_sale');
  end if;

  if v_li.item_kind = 'marketplace_product' and v_li.product_id is not null then
    update public.products
    set
      quantity = coalesce(p_quantity, quantity),
      price = coalesce(p_price, price),
      title = coalesce(nullif(trim(p_title), ''), title),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end
    where id = v_li.product_id;

    update public.live_items
    set
      title = coalesce(nullif(trim(p_title), ''), title),
      price = coalesce(p_price, price),
      clothing_size = case when p_clothing_size is not null then nullif(trim(p_clothing_size), '') else clothing_size end,
      gender = case when p_gender is not null then nullif(trim(p_gender), '') else gender end,
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
      updated_at = now()
    where id = v_li.id;

    if v_li.checkout_product_id is not null then
      update public.products
      set
        quantity = case when p_quantity is not null then v_qty else quantity end,
        price = case when p_price is not null then p_price else price end,
        title = coalesce(nullif(trim(p_title), ''), title)
      where id = v_li.checkout_product_id;
    end if;
  end if;

  perform public.batata_recompute_live_item_status(v_li.id);

  if p_quantity is not null and v_li.product_id is not null then
    update public.products
    set is_sold = false, list_on_marketplace = true
    where id = v_li.product_id
      and is_sold = true
      and exists (
        select 1
        from public.live_items li2
        where li2.id = v_li.id
          and coalesce(li2.status, '') <> 'sold'
      );
  end if;

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

revoke all on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) from public;
grant execute on function public.batata_update_live_item(uuid, integer, numeric, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
