select created_at, category, left(coalesce(error_message,''), 400) as msg
from public.app_logs
where created_at > '2026-09-13 14:00:00+00'
order by created_at desc
limit 60;
