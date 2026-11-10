select m.created_at, m.chat_id, left(m.text, 160) as t
from chat_messages m
where m.chat_id = '495ea658-a538-481c-b0ec-07733a41bdd6'
order by m.created_at desc
limit 15;
