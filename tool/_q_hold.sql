select column_name from information_schema.columns
where table_name='live_items' and column_name like '%seller%';

-- pending orders still blocking stock for product checkout?
select o.id, o.status, o.quantity, o.product_id, o.created_at,
  public.batata_product_checkout_available(o.product_id, o.id, o.quantity) as avail
from public.orders o
where o.buyer_id='69104e91-6a00-40d9-a7c9-b1571422ae43'
  and o.live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9'
  and o.status='reserva_pendente'
order by o.created_at;
