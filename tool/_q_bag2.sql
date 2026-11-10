select created_at, category, left(error_message, 450) as msg
from public.app_logs
where created_at > '2026-09-13 15:30:00+00'
  and category in ('hub.bag.pay','stripe.checkout')
order by created_at desc
limit 40;
