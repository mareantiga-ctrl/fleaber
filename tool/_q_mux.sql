select id, full_name, handle from public.profiles
where handle ilike '%mux%' or full_name ilike '%Mux%'
order by full_name;

select l.id, l.title, l.status, l.is_active, l.ended_at, p.handle, p.full_name
from public.lives l
join public.profiles p on p.id = coalesce(l.seller_id, l.vendedor_id)
where p.handle ilike '%mux%' or p.full_name ilike '%Mux%'
order by l.created_at desc limit 8;
