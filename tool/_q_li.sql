select id, ref_code, live_id, price, checkout_product_id, product_id, quantity, status
from live_items where live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9';

select id, status, is_active, coalesce(seller_id,vendedor_id) seller,
  (select hub_published from profiles p where p.id=coalesce(l.seller_id,l.vendedor_id)) hub
from lives l where id='c3af87a7-a962-4af5-bb35-90b39a03ede9';

-- function signature
select pg_get_function_identity_arguments(oid), proname
from pg_proc where proname like '%live_item_stock%';
