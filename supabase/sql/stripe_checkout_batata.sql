-- Fleaber BATATA: finalizar artigo vendido quando o pagamento Stripe fica pago.
-- Executar no SQL Editor do Supabase.
-- Isto evita depender do comprador atualizar `products`, que é bloqueado por RLS.

-- BUG-QA-016: multi-stock real. Ao ficar «pago», decrementa `quantity` pelas
-- unidades da encomenda e só marca `is_sold`/tira do marketplace quando o
-- stock chega a 0. Continua a ser o único responsável pelo stock (o webhook
-- Stripe deixou de atualizar `products` diretamente para não haver duplo
-- decremento).
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
begin
  if new.product_id is not null
     and lower(coalesce(new.status, '')) = 'pago'
     and (
       tg_op = 'INSERT'
       or lower(coalesce(old.status, '')) is distinct from lower(coalesce(new.status, ''))
     ) then
    v_units := greatest(coalesce(new.quantity, 1), 1);

    select quantity into v_before
    from public.products
    where id = new.product_id;

    update public.products
       set quantity = greatest(coalesce(quantity, 1) - v_units, 0)
     where id = new.product_id
     returning quantity into v_remaining;

    -- BUG-QA-021: rasto do stock para diagnóstico (Supabase logs).
    raise log 'BATATA_STOCK order=% product=% units=% qty_before=% qty_after=%',
      new.id, new.product_id, v_units, v_before, v_remaining;

    -- Só esgota quando o stock chega mesmo a 0. Se o UPDATE não tocou linha
    -- nenhuma (v_remaining NULL), NÃO marcar vendido por engano.
    if v_remaining is not null and v_remaining <= 0 then
      update public.products
         set is_sold = true,
             list_on_marketplace = false
       where id = new.product_id;
      raise log 'BATATA_STOCK esgotado product=% (is_sold=true, off marketplace)',
        new.product_id;
    elsif v_remaining is not null and v_remaining > 0 then
      -- Stock parcial: manter no marketplace (is_sold=false).
      update public.products
         set is_sold = false
       where id = new.product_id
         and is_sold = true;
      raise log 'BATATA_STOCK parcial product=% qty_remaining=%',
        new.product_id, v_remaining;
    end if;
  end if;

  return new;
end;
$$;

-- BUG-QA-020: permitir quantity=0 quando esgotado (antes CHECK >= 1 bloqueava o UPDATE).
alter table public.products drop constraint if exists products_quantity_check;
alter table public.products
  add constraint products_quantity_check check (quantity >= 0);

drop trigger if exists batata_mark_product_sold_on_paid_order_trg on public.orders;

create trigger batata_mark_product_sold_on_paid_order_trg
after insert or update of status on public.orders
for each row
execute function public.batata_mark_product_sold_on_paid_order();

-- Nota: o backfill destrutivo (marcar vendido todas as encomendas pagas antigas)
-- foi removido. Com multi-stock, forçar is_sold=true reativava a venda de artigos
-- recolocados que ainda têm stock. O trigger acima trata das vendas futuras.

-- Cancel/refund: repor quantity no mesmo product_id — ver
-- order_cancel_stock_restore_batata.sql (batata_restore_product_stock_on_cancelled_order).
