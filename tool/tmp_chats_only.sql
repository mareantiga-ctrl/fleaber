select c.id, c.last_message, c.created_at,
  (select count(*) from chat_messages m where m.chat_id = c.id) as msg_count
from public.chats c
where c.product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
order by c.created_at;
