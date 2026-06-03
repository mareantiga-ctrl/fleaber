-- Fleaber BATATA: finalizar artigo vendido quando o pagamento Stripe fica pago.
-- Executar no SQL Editor do Supabase.
-- Isto evita depender do comprador atualizar `products`, que é bloqueado por RLS.

create or replace function public.batata_mark_product_sold_on_paid_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_id is not null
     and lower(coalesce(new.status, '')) = 'pago'
     and (
       tg_op = 'INSERT'
       or lower(coalesce(old.status, '')) is distinct from lower(coalesce(new.status, ''))
     ) then
    update public.products
       set is_sold = true,
           list_on_marketplace = false
     where id = new.product_id;
  end if;

  return new;
end;
$$;

drop trigger if exists batata_mark_product_sold_on_paid_order_trg on public.orders;

create trigger batata_mark_product_sold_on_paid_order_trg
after insert or update of status on public.orders
for each row
execute function public.batata_mark_product_sold_on_paid_order();

-- Backfill para encomendas já pagas antes deste trigger existir.
update public.products p
   set is_sold = true,
       list_on_marketplace = false
  from public.orders o
 where o.product_id = p.id
   and lower(coalesce(o.status, '')) = 'pago';
