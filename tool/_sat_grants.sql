select p.proname,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
  has_function_privilege('public', p.oid, 'EXECUTE') as public_exec
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and (
  p.proname ilike '%lab%' or p.proname ilike '%clear_all_fm%' or p.proname ilike '%clear_fm%'
  or p.proname = 'batata_generate_auto_feedback' or p.proname ilike '%nuke%'
)
order by 1;
select column_name from information_schema.columns
where table_schema='public' and table_name='product_offers' order by 1;
select column_name from information_schema.columns
where table_schema='public' and table_name='live_reservation_requests' order by 1;
