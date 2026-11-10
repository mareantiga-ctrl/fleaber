update public.live_reservation_requests r
set status = 'expired'
where r.status = 'accepted'
  and r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.live_id = 'f08f3776-579a-4252-9cba-b8d1626be1ca'
returning id, ref_hint, status, requested_qty;
