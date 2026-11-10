select p.proname, pg_get_function_identity_arguments(p.oid) as args,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and (p.proname ilike '%lab%' or p.proname ilike '%clear%fm%' or p.proname ilike '%nuke%'
       or p.proname ilike '%seed%' or p.proname ilike '%e2e%' or p.proname ilike '%director%'
       or p.proname = 'batata_generate_auto_feedback')
order by 1;
select pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='batata_orders_seal_contract';
