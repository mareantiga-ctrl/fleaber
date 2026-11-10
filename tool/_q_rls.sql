select pol.polname, pol.polcmd,
  pg_get_expr(pol.polqual, pol.polrelid) as using_expr,
  pg_get_expr(pol.polwithcheck, pol.polrelid) as check_expr
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relname='live_reservation_requests'
order by pol.polcmd, pol.polname;

-- try update as Mariana
select set_config('request.jwt.claim.sub', '69104e91-6a00-40d9-a7c9-b1571422ae43', true);
select set_config('request.jwt.claims', '{"sub":"69104e91-6a00-40d9-a7c9-b1571422ae43","role":"authenticated"}', true);
select set_config('role', 'authenticated', true);

update public.live_reservation_requests
set notes = coalesce(notes,'') || ' | stripe_checkout:test'
where id = '87f937b0-88dd-4ce6-bff3-76d1097ffd31'
returning id, left(notes,80);
