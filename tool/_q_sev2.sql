select created_at, event, live_id, order_id, product_id, left(detail::text, 280) as d
from public.stripe_checkout_events
where created_at > '2026-09-13 14:50:00+00'
order by created_at desc
limit 40;
