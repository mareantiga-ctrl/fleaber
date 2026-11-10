-- live_items update policies / triggers on quantity
select tgname, pg_get_triggerdef(oid) from pg_trigger
where tgrelid = 'public.live_items'::regclass and not tgisinternal;
