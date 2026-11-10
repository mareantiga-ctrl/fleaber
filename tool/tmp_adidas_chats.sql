select c.id, c.created_at, c.last_message, c.last_message_time,
  (select count(*) from chat_messages m where m.chat_id = c.id) as msg_count,
  (select count(*) from chat_messages m where m.chat_id = c.id and m.text like '%seguro_fleaber_paid%') as paid_cards
from chats c
where c.product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
order by c.created_at;
