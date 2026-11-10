select created_at, category, left(coalesce(error_message,''), 500) as msg
from public.app_logs
where created_at > '2026-09-13 14:00:00+00'
  and (
    category ilike '%stripe%'
    or error_message ilike '%stripe%'
    or error_message ilike '%checkout%'
    or error_message ilike '%Pagar%'
    or error_message ilike '%bag%'
    or error_message ilike '%payment%'
    or error_message ilike '%invoke%'
  )
order by created_at desc
limit 40;
