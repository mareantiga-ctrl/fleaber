select created_at, event, left(coalesce(detail::text,''),400) d
from stripe_checkout_events
where created_at > now() - interval '90 minutes'
order by created_at desc limit 25;
