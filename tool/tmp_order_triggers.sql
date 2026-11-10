select tgname from pg_trigger
where not tgisinternal and tgrelid = 'public.orders'::regclass
order by tgname;
