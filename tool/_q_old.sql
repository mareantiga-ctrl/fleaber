select li.ref_code, r.status, r.requested_qty, r.buyer_id is not null as claimed
from live_reservation_requests r
join live_items li on li.id=r.live_item_id
where li.live_id='f08f3776-579a-4252-9cba-b8d1626be1ca' and r.status='accepted';
