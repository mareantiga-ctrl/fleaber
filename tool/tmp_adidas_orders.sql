select id, status, created_at, price_total, is_reservation
from orders
where product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
  and buyer_id = (select id from profiles where username ilike 'joao84' limit 1)
order by created_at desc
limit 15;
