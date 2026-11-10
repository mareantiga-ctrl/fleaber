-- products RLS policies
select polname, cmd, qual::text, with_check::text
from pg_policy p
join pg_class c on c.oid=p.polrelid
where c.relname='products'
limit 20;
