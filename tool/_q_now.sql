select li.ref_code, r.status, r.requested_qty, r.buyer_id is not null as claimed,
  r.expires_at, left(coalesce(r.notes,''),80) notes
from live_reservation_requests r
join live_items li on li.id=r.live_item_id
where li.live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by li.ref_code;

select id, status, is_active from lives where id='c3af87a7-a962-4af5-bb35-90b39a03ede9';

-- any recent orders any live last hour for mariana
select id, live_id, status, price_total, quantity, created_at
from orders
where buyer_id='69104e91-6a00-40d9-a7c9-b1571422ae43'
  and created_at > now() - interval '2 hours'
order by created_at desc limit 20;
