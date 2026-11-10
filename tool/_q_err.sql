select created_at, event, left(detail::text, 350) as d
from public.stripe_checkout_events
where created_at > '2026-09-13 15:20:00+00'
order by created_at desc
limit 10;

select id, status, left(coalesce(notes,''), 120) as notes, live_item_id, requested_qty
from public.live_reservation_requests
where buyer_id='69104e91-6a00-40d9-a7c9-b1571422ae43'
  and live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9';
