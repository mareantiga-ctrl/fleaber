select created_at, category, left(error_message, 400)
from public.app_logs
where category = 'stripe.checkout'
   or category like 'stripe%'
order by created_at desc
limit 30;

select event, count(*), max(created_at)
from public.stripe_checkout_events
where created_at > '2026-09-13'::timestamptz
group by event
order by max(created_at) desc;
