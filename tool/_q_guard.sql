select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);

-- dry-run: o que o trigger vê
select
  (public.batata_live_item_stock('fad6c909-b066-48ee-830f-09b503146019')->>'available_qty')::int as avail_rrr4,
  case when (public.batata_live_item_stock('fad6c909-b066-48ee-830f-09b503146019')->>'available_qty')::int < 1
    then 'WOULD_BLOCK' else 'OK_INSERT' end as guard_rrr4;

-- pending ainda no saco actual
select li.ref_code, r.status, r.requested_qty
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
where r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
  and r.status in ('pending','accepted');
