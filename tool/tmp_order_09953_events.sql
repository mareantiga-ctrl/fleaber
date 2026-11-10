select event, created_at, left(detail::text, 400) as d
from stripe_checkout_events
where order_id = '09953ed3-2b53-4016-8008-c38df9617ca1'
   or detail::text ilike '%09953ed3%'
   or detail::text ilike '%chat_multi%'
order by created_at;
