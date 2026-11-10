select id, product_id, user_a, user_b, last_message, created_at
from public.chats
where id in (
  'd11522ae-46ac-40b0-88c1-ad5e4590765c',
  '495ea658-a538-481c-b0ec-07733a41bdd6'
);

select cm.chat_id, cm.id, cm.created_at, left(cm.text, 200) as preview
from public.chat_messages cm
where cm.chat_id in (
  'd11522ae-46ac-40b0-88c1-ad5e4590765c',
  '495ea658-a538-481c-b0ec-07733a41bdd6'
)
and cm.created_at > '2026-08-09 08:00:00+00'
order by cm.created_at;
