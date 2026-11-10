select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select (public.batata_live_item_stock('fad6c909-b066-48ee-830f-09b503146019')->>'available_qty')::int as avail,
       case when (public.batata_live_item_stock('fad6c909-b066-48ee-830f-09b503146019')->>'available_qty')::int < 1
         then 'BLOCK' else 'ALLOW' end as pay_guard;
