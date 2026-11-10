select li.ref_code, r.status, r.requested_qty, r.live_id, r.buyer_id::text
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where li.live_id in (
  'c3af87a7-a962-4af5-bb35-90b39a03ede9',
  'f08f3776-579a-4252-9cba-b8d1626be1ca'
)
and r.status in ('pending','accepted')
order by li.ref_code, r.status;
