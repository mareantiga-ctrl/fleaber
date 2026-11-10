select created_at, category, left(coalesce(error_message,''), 300) as msg
from public.app_logs
where created_at > '2026-09-13 15:00:00+00'
order by created_at desc
limit 50;

select created_at, event, left(detail::text, 200) as d
from public.stripe_checkout_events
where buyer_id = '69104e91-6a00-40d9-a7c9-b1571422ae43'
  and created_at > '2026-09-13 12:00:00+00'
order by created_at desc
limit 30;
