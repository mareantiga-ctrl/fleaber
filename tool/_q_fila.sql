select li.id, li.ref_code, li.title, li.quantity, li.live_id, li.checkout_product_id, li.price,
       l.status as live_status, l.is_active
from public.live_items li
join public.lives l on l.id = li.live_id
where li.title ilike '%Fila 8%' or li.ref_code ilike '%Fila%' or li.ref_code ilike '%FILA%'
order by li.created_at desc nulls last
limit 15;
