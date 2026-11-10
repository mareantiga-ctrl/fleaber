select li.id, li.ref_code, li.live_id, li.logical_item_id, li.quantity,
  batata_live_item_stock(li.id) as stock
from live_items li
where li.id='fad6c909-b066-48ee-830f-09b503146019';

-- cross reservations same lineage
select r.status, r.requested_qty, r.buyer_id is not null as claimed, li.live_id, li.ref_code
from live_reservation_requests r
join live_items li on li.id=r.live_item_id
where coalesce(li.logical_item_id, li.id) = (
  select coalesce(logical_item_id, id) from live_items where id='fad6c909-b066-48ee-830f-09b503146019'
)
and r.status in ('pending','accepted')
order by r.created_at;
