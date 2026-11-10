-- Purge legado order_proofs / order_disputes no bucket PÚBLICO chat_media (staging).
-- Objectos novos vão para fleaber_private. URLs públicas antigas deixam de servir.
-- Correr via tool ou Dashboard Storage — este SQL documenta a intenção.
-- (Storage API remove objects; SQL directo em storage.objects é frágil.)

-- Contagem (diagnóstico):
-- select count(*) from storage.objects
-- where bucket_id='chat_media' and (name like 'order_proofs/%' or name like 'order_disputes/%');
