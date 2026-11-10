-- BATATA 2026-09-30: índice para listagem de mensagens por conversa.
-- Queries app: ChatMessagesTable eq(chat_id) + order(created_at|id) (chat_page, lista).
-- Staging confirmado: só chat_messages_pkey — sem índice em chat_id.

create index if not exists chat_messages_chat_id_created_at_idx
  on public.chat_messages (chat_id, created_at);

comment on index public.chat_messages_chat_id_created_at_idx is
  'C1-2026-09-30: acelera fetch por conversa (chat_id + created_at).';
