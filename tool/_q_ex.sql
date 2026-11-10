select li.ref_code, li.quantity, li.status, li.item_kind,
  (select sum(requested_qty) from live_reservation_requests r where r.live_item_id=li.id and r.status in ('pending','accepted')) as open_qty
from live_items li
where li.live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9';

-- as seller (service) stock without auth gate - use set role?
select public.batata_live_is_broadcasting('c3af87a7-a962-4af5-bb35-90b39a03ede9'::uuid) as broadcasting;
