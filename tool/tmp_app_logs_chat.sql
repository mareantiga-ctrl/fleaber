select category, message, left(payload::text, 300) as payload, created_at
from app_logs
where created_at > now() - interval '3 hours'
  and (
    message ilike '%chat_multi%'
    or category ilike '%chat%'
    or payload::text ilike '%chat_multi%'
  )
order by created_at desc
limit 30;
