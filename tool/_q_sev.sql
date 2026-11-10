select column_name from information_schema.columns
where table_name='stripe_checkout_events' and table_schema='public';

select * from public.stripe_checkout_events
order by created_at desc nulls last
limit 5;

-- cancel test if still pending
update public.orders set status='cancelado'
where id='f74be61d-e3bd-4331-baa8-129c716b3135' and status='reserva_pendente';
