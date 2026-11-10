-- FASE3B: remover policies legadas portuguesas que OR-bypass ownership
drop policy if exists "Fotos do chat são públicas" on storage.objects;
drop policy if exists "Users podem fazer upload de fotos" on storage.objects;

-- Confirmar buckets
select id, public from storage.buckets where id in ('chat_media', 'fleaber_private');
