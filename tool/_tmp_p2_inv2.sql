select pol.polname, c.relname, pol.polcmd, pg_get_expr(pol.polqual, pol.polrelid) as using_expr, array_agg(r.rolname) as roles
from pg_policy pol
join pg_class c on c.oid=pol.polrelid
join pg_namespace n on n.oid=c.relnamespace
left join lateral unnest(pol.polroles) ur(oid) on true
left join pg_roles r on r.oid=ur.oid
where n.nspname='public' and c.relname in ('live_messages','live_raffle_winners','follows','favorites','notifications_view')
group by 1,2,3,4
order by 2,1;

select grantee, privilege_type from information_schema.role_table_grants
where table_schema='public' and table_name in ('notifications_view','live_messages','live_raffle_winners','follows')
order by table_name, grantee, privilege_type;

select c.relname, c.relrowsecurity, c.relforcerowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('notifications_view','live_messages','live_raffle_winners','follows','favorites');
