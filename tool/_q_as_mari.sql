select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);
select auth.uid() as uid, auth.role() as role;

select li.ref_code,
  public.batata_live_item_total_qty(li.id) as total_qty,
  public.batata_live_item_stock(li.id) as stock
from public.live_items li
where li.live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by li.ref_code;
