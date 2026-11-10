select id, status, price_total, quantity, live_item_id, product_id, created_at
from orders
where buyer_id='69104e91-6a00-40d9-a7c9-b1571422ae43'
  and live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9'
order by created_at desc limit 15;
