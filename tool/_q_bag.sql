select id, full_name, handle from public.profiles
where handle ilike '%0913%' or full_name ilike '%Vendora%'
order by full_name;

select r.id, r.status, r.requested_qty, r.live_id, li.ref_code, li.title, li.price,
       li.checkout_product_id, l.status as live_status, p.handle, p.full_name
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
join public.lives l on l.id = r.live_id
join public.profiles p on p.id = coalesce(l.seller_id, l.vendedor_id)
where r.buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and r.status in ('pending','accepted')
order by r.created_at desc
limit 20;
