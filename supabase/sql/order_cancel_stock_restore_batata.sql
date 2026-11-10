-- Fleaber BATATA: repor products.quantity quando encomenda paga é cancelada.
-- Espelho do decremento em stripe_checkout_batata.sql (batata_mark_product_sold_on_paid_order).
--
-- Executar no SQL Editor staging/prod DEPOIS de stripe_checkout_batata.sql.
--
-- Política:
--   · pago / enviado → cancelado  → +order.quantity no mesmo product_id
--   · is_sold=false + list_on_marketplace=true se qty > 0
--   · Prémio da Rifa: NÃO repor (products.quantity não desceu no pago pós-premio_rifa)
--   · reserva_pendente / reservado / etc.: NÃO repor (nunca decrementaram)

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

  -- Só transição para cancelado (variantes PT/EN).
  if v_new is not distinct from v_old then
    return new;
  end if;
  if v_new not in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) and position('cancelad' in v_new) = 0
    and position('anulad' in v_new) = 0 then
    return new;
  end if;

  -- Stock só foi decrementado ao ficar «pago» (ou estados pós-pago).
  if v_old not in (
    'pago', 'enviado', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    return new;
  end if;

  -- Prémio da Rifa: batata_mark_product_sold_on_paid_order salta o decremento
  -- em premio_rifa → pago; repor aqui inflava stock.
  v_pm := lower(trim(coalesce(new.payment_method, '')));
  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    raise log
      'BATATA_STOCK skip_restore_prize order=% product=% old=% pm=%',
      new.id, new.product_id, v_old, v_pm;
    return new;
  end if;

  v_units := greatest(coalesce(new.quantity, 1), 1);

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = new.product_id
   returning quantity into v_after;

  raise log
    'BATATA_STOCK restore order=% product=% units=% qty_before=% qty_after=% old_status=%',
    new.id, new.product_id, v_units, v_before, v_after, v_old;

  return new;
end;
$$;

drop trigger if exists batata_restore_product_stock_on_cancelled_order_trg
  on public.orders;

create trigger batata_restore_product_stock_on_cancelled_order_trg
after update of status on public.orders
for each row
execute function public.batata_restore_product_stock_on_cancelled_order();

comment on function public.batata_restore_product_stock_on_cancelled_order() is
  'BATATA: repor products.quantity + marketplace quando order pago/enviado → cancelado.';
