-- Chats Adidas + mensagens recentes
select c.id, c.product_id, c.user_a, c.user_b, c.last_message, c.created_at
from public.chats c
where c.product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
order by c.created_at;

select cm.id, cm.chat_id, cm.created_at, cm.is_reservation, left(cm.text, 220) as preview
from public.chat_messages cm
join public.chats c on c.id = cm.chat_id
where c.product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
  and cm.created_at > now() - interval '6 hours'
order by cm.created_at;

select o.id, o.status, o.quantity, o.created_at, o.buyer_id, o.payment_method
from public.orders o
where o.product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
  and o.created_at > now() - interval '6 hours'
order by o.created_at;
