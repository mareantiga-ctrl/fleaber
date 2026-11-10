-- Mensagens com order_id da compra 10:40 (antes do pago?)
select m.created_at, m.chat_id, left(m.text, 200) as t
from chat_messages m
where m.text like '%09953ed3-2b53-4016-8008-c38df9617ca1%'
order by m.created_at;
