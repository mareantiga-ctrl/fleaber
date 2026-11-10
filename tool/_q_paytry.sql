select o.id, o.status, o.quantity, o.price_total, o.live_id, o.live_item_id, o.product_id, o.created_at
from public.orders o
where o.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and o.created_at > now() - interval '6 hours'
order by o.created_at desc
limit 25;

select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);

-- simulate capacity check like client for each pending
select li.ref_code, r.requested_qty,
  (s->>'total_qty')::int as total,
  (s->>'available_qty')::int as avail,
  (s->>'pending_bag_qty')::int as pending,
  (s->>'blocked_qty')::int as blocked,
  s->>'ok' as ok
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
cross join lateral public.batata_live_item_stock(li.id) s
where r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
  and r.status = 'pending';
