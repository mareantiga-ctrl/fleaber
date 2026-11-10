select pol.polname, pol.polcmd::text,
  left(pg_get_expr(pol.polqual, pol.polrelid), 200) as using_expr
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
where c.relname='orders'
order by pol.polcmd, pol.polname;
