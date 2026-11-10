select created_at, category, left(error_message, 200)
from public.app_logs
where created_at > '2026-09-13 15:10:00+00'
  and category not like 'hub.qa%'
  and category not like 'hub.player%'
  and category not like 'video.%'
order by created_at desc
limit 40;
