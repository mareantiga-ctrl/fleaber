select pol.polname, pol.polcmd::text,
  pg_get_expr(pol.polqual, pol.polrelid) as using_expr,
  pg_get_expr(pol.polwithcheck, pol.polrelid) as check_expr
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
where c.relname='stripe_checkout_events';

select relrowsecurity from pg_class where relname='stripe_checkout_events';
