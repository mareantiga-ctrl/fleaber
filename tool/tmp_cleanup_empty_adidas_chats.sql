-- Limpar chats órfãos sem mensagens (CHAT-MULTI) para o artigo Adidas #AM4.
-- Só apaga se msg_count = 0.
delete from chats
where product_id = '1bf32b52-f7df-4fe3-bc07-24604047a776'
  and id in (
    '7e35687e-48bf-409b-bd33-a45d92910968',
    '1d59970a-5817-49c7-b25e-4d8b94bc6117',
    'af4a537b-e894-46d6-bd7f-ba9282bdfc31',
    '1c91b5b1-0c04-4819-88fb-89cfaf632147'
  )
  and not exists (
    select 1 from chat_messages m where m.chat_id = chats.id
  );
