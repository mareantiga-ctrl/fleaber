select created_at, event, live_id, order_id, product_id, buyer_id, detail
from public.stripe_checkout_events
where created_at > '2026-09-13 15:00:00+00'
order by created_at desc
limit 40;

select id, status, quantity, live_id, product_id, created_at, price_total
from public.orders
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and created_at > '2026-09-13 15:00:00+00'
order by created_at desc;
