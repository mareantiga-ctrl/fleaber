-- cancel test order
update public.orders set status = 'cancelado'
where id = 'f74be61d-e3bd-4331-baa8-129c716b3135';

select event, created_at, payload::text
from public.stripe_checkout_events
where created_at > now() - interval '1 day'
order by created_at desc
limit 30;
