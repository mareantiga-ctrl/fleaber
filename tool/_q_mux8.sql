-- Mux8 seller + recent live + Fila 8
select id, full_name, handle from public.profiles
where handle ilike '%mux8%' or full_name ilike '%mux 8%' or full_name ilike '%Mux8%';

select id, title, status, is_active, ended_at, seller_id, created_at
from public.lives
where seller_id in (
  select id from public.profiles where handle ilike '%mux8%' or full_name ilike '%Mux 8%'
)
order by created_at desc limit 5;
