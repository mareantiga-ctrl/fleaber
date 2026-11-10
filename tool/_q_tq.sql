select id, logical_item_id, quantity, checkout_product_id, product_id,
  public.batata_live_item_total_qty(id) as tq
from live_items where id='fad6c909-b066-48ee-830f-09b503146019';
select id, logical_item_id, quantity from live_items where id='4fca575d-cced-41e3-85bb-7bedfc94e082';
