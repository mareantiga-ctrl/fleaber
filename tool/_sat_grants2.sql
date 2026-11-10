select p.proname,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname like 'batata_lab%'
order by 1;
select p.proname,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname = 'batata_generate_auto_feedback';
select column_name from information_schema.columns
where table_schema='public' and table_name='product_offers' order by 1;
select column_name from information_schema.columns
where table_schema='public' and table_name='order_disputes'
and column_name ilike '%status%' or (table_schema='public' and table_name='order_disputes' and column_name ilike '%offer%')
order by 1;
