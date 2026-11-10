select created_at, category, left(error_message, 500) as msg
from public.app_logs
where created_at > now() - interval '90 minutes'
  and (
    category in ('hub.bag.pay','stripe.checkout','live.checkout.gate')
    or error_message ilike '%Failed to fetch%'
    or error_message ilike '%create-payment%'
    or error_message ilike '%CORS%'
    or error_message ilike '%order_hold%'
  )
order by created_at desc
limit 50;

select created_at, event, left(detail::text, 280) as d
from public.stripe_checkout_events
where created_at > now() - interval '90 minutes'
order by created_at desc
limit 20;
