select m.id, m.chat_id, m.created_at, left(m.text, 120) as text_preview
from chat_messages m
where m.text like '%seguro_fleaber_paid%'
  and m.created_at > now() - interval '6 hours'
order by m.created_at desc
limit 20;
