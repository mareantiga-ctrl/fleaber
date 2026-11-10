with ranked as (
  select id, product_id, created_at,
    row_number() over (partition by product_id order by created_at desc) as rn
  from public.orders
  where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
    and live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
    and status = 'reserva_pendente'
)
update public.orders o
set status = 'cancelado'
from ranked r
where o.id = r.id and r.rn > 1;

select id, status, quantity, product_id, created_at
from public.orders
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by created_at desc;
