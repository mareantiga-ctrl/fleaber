select created_at, event, live_id, order_id, left(detail::text,200) as detail
from public.stripe_checkout_events
where created_at > '2026-09-13 14:00:00+00'
order by created_at desc
limit 50;

select created_at, category, message, left(coalesce(data::text, meta::text, ''), 240) as data
from public.app_logs
where created_at > '2026-09-13 15:00:00+00'
  and (category ilike '%stripe%' or message ilike '%stripe%' or message ilike '%checkout%' or message ilike '%invoke%')
order by created_at desc
limit 40;
