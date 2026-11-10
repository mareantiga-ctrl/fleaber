select r.id, r.status, r.requested_qty, li.ref_code, r.order_id
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9';
