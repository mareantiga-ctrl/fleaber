update public.orders
set status = 'cancelado'
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and status = 'reserva_pendente'
  and live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9';

select product_id, count(*), sum(quantity) as qty
from public.orders
where product_id in (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7',
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750'
)
and status = 'reserva_pendente'
group by product_id;

select public.batata_product_checkout_available(
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7'::uuid, null, 5) as rrr5;
select public.batata_product_checkout_available(
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d'::uuid, null, 5) as rrr4;
select public.batata_product_checkout_available(
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750'::uuid, null, 1) as rrr6;
