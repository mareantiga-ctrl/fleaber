select id, ref_code, quantity, live_id, item_kind, logical_item_id,
       checkout_product_id, product_id, status
from public.live_items
where live_id = 'c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by ref_code;
