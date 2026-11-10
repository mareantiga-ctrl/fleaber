-- Mariana pending orders + product stock gate
select o.id, o.status, o.quantity, o.product_id, o.live_item_id, o.live_id, o.created_at,
  public.batata_product_checkout_available(o.product_id, null, o.quantity) as avail_new,
  public.batata_product_checkout_available(o.product_id, o.id, o.quantity) as avail_excl
from public.orders o
where o.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and o.status = 'reserva_pendente'
  and o.created_at > now() - interval '2 days'
order by o.created_at desc;

select p.id, p.title, p.quantity, p.list_on_marketplace
from public.products p
where p.id in (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7',
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750'
);

-- all holds on these products
select o.status, o.quantity, o.product_id, o.buyer_id, o.live_id, o.created_at
from public.orders o
where o.product_id in (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7',
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750'
)
and coalesce(o.status,'') not in ('cancelado','cancelled','rejected','expired')
order by o.product_id, o.created_at desc;
