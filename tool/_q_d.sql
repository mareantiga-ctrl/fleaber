-- RRR5/6 holds
select li.ref_code, r.status, r.requested_qty, r.live_id
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where coalesce(li.logical_item_id, li.id) in (
  '5cd8a2f1-f5e9-457d-88b2-4e1f3bc8ad09',
  '83657882-46d9-4db1-ad2f-293bbcea6e8e'
)
and r.status in ('pending','accepted')
order by li.ref_code, r.created_at;

-- shadow product qty
select id, title, quantity, list_on_marketplace
from public.products
where id in (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7',
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750',
  '70925b01-e485-4b05-93f9-2ead37097d23'
);
