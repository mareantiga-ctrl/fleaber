-- BATATA: stock idempotente por encomenda (evita 10→8 no settle duplo webhook+return).
alter table public.orders
  add column if not exists stock_units_applied integer;

comment on column public.orders.stock_units_applied is
  'Unidades já descontadas de products.quantity; null = ainda não aplicado.';

create or replace function public.batata_mark_product_sold_on_paid_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_remaining int;
  v_claimed int;
begin
  if new.product_id is null then
    return new;
  end if;

  if lower(coalesce(new.status, '')) <> 'pago' then
    return new;
  end if;

  if new.stock_units_applied is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) is not distinct from lower(coalesce(new.status, '')) then
    return new;
  end if;

  -- Prémio da Rifa: stock já retido no sorteio.
  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) = 'premio_rifa' then
    return new;
  end if;

  v_units := greatest(coalesce(new.quantity, 1), 1);

  -- Claim atómico: settle duplo (webhook + return) não desce 2×.
  update public.orders
     set stock_units_applied = v_units
   where id = new.id
     and stock_units_applied is null;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = greatest(coalesce(quantity, 1) - v_units, 0)
   where id = new.product_id
   returning quantity into v_remaining;

  raise log 'BATATA_STOCK order=% product=% units=% qty_before=% qty_after=%',
    new.id, new.product_id, v_units, v_before, v_remaining;

  if v_remaining is not null and v_remaining <= 0 then
    update public.products
       set is_sold = true,
           list_on_marketplace = false
     where id = new.product_id;
  elsif v_remaining is not null and v_remaining > 0 then
    update public.products
       set is_sold = false
     where id = new.product_id
       and is_sold = true;
  end if;

  return new;
end;
$$;

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
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if new.product_id is null then
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;
  if v_new not in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) and position('cancelad' in v_new) = 0
    and position('anulad' in v_new) = 0 then
    return new;
  end if;

  v_units := new.stock_units_applied;
  if v_units is null then
    if v_old not in (
      'pago', 'enviado', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      return new;
    end if;
    v_units := greatest(coalesce(new.quantity, 1), 1);
  elsif v_units <= 0 then
    return new;
  end if;

  v_pm := lower(trim(coalesce(new.payment_method, '')));
  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    update public.orders
       set stock_units_applied = null
     where id = new.id;
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

  update public.orders
     set stock_units_applied = null
   where id = new.id;

  raise log
    'BATATA_STOCK restore order=% product=% units=% qty_before=% qty_after=% old_status=%',
    new.id, new.product_id, v_units, v_before, v_after, v_old;

  return new;
end;
$$;

update public.orders o
set stock_units_applied = greatest(coalesce(o.quantity, 1), 1)
where o.stock_units_applied is null
  and lower(coalesce(o.status, '')) in (
    'pago', 'enviado', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );
