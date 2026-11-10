
-- Patch restore stock: allow clearing claim under JWT session
create or replace function public.batata_restore_product_stock_on_cancelled_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_after int;
  v_old text;
  v_new text;
  v_pm text;
  v_cleared int;
  v_restore boolean := false;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if new.product_id is null then
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;

  if v_new in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) or position('cancelad' in v_new) > 0
    or position('anulad' in v_new) > 0 then
    v_restore := true;
  end if;

  if v_new = 'devolvida' then
    v_restore := true;
  end if;

  if not v_restore then
    return new;
  end if;

  v_pm := lower(trim(coalesce(new.payment_method, '')));
  perform set_config('batata.allow_internal_order_cols', '1', true);

  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    update public.orders
       set stock_units_applied = null
     where id = new.id
       and stock_units_applied is not null;
    return new;
  end if;

  v_units := new.stock_units_applied;
  if v_units is null or v_units <= 0 then
    return new;
  end if;

  update public.orders
     set stock_units_applied = null
   where id = new.id
     and stock_units_applied is not null;
  get diagnostics v_cleared = row_count;
  if v_cleared = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = new.product_id
   returning quantity into v_after;

  return new;
end;
$$;

notify pgrst, 'reload schema';
