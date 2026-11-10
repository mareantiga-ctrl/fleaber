select r.status, r.requested_qty, r.live_id, li.ref_code, li.id as live_item_id,
       r.buyer_id::text as buyer, r.source,
       coalesce(li.checkout_product_id, li.product_id)::text as prod
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where coalesce(li.logical_item_id, li.id) = '46a20ad2-0c44-4fb9-9f30-d68481d616b6'
  and r.status in ('pending','accepted')
order by r.created_at;
