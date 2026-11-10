select id, seller_id, list_on_marketplace, quantity, title
from public.products
where id in (
  '710ff215-a7e8-44b5-a04e-ce295fe6ae6d',
  '555208ec-dc34-4f3a-b6b0-29d575c7a6d7',
  '7483efdd-9fab-4b72-aab7-7d4b17fa3750'
);

-- triggers on live_reservation_requests update?
select tgname, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid = 'public.live_reservation_requests'::regclass
  and not tgisinternal;
