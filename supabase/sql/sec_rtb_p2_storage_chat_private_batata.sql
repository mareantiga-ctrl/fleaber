-- =============================================================================
-- RTB-P2-STORAGE-CHAT-ENUM fecho CDN residual (staging only)
-- chat_uploads → fleaber_private; catálogo marketplace permanece público.
-- Não apaga objectos sem cópia (migração via tool/sec_rtb_migrate_chat_uploads.dart).
-- Restaura counterparty order_proofs (não enfraquecer).
-- PRODUÇÃO NÃO. FASE 4 NÃO.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) chat_media INSERT: sem chat_uploads (novos media de chat → privado)
-- ---------------------------------------------------------------------------
drop policy if exists chat_media_auth_insert on storage.objects;
create policy chat_media_auth_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and name not like 'order_proofs/%'
    and name not like 'order_disputes/%'
    and name not like 'chat_uploads/%'
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
    )
  );

-- UPDATE/DELETE: remover chat_uploads do bucket público (só catálogo + legado proofs path)
drop policy if exists chat_media_auth_update_own on storage.objects;
create policy chat_media_auth_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
    )
  )
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
    )
  );

drop policy if exists chat_media_auth_delete_own on storage.objects;
create policy chat_media_auth_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and (
      name like ('product_photos/' || auth.uid()::text || '/%')
      or name like ('profile_photos/' || auth.uid()::text || '/%')
      or name like ('live_item_photos/' || auth.uid()::text || '/%')
      or name like ('live_raffle_prize/' || auth.uid()::text || '/%')
      or (
        (name like 'order_proofs/%' or name like 'order_disputes/%')
        and position(auth.uid()::text in name) > 0
      )
    )
  );

-- Já não há SELECT público/próprio de chat_uploads no bucket público
drop policy if exists chat_media_chat_uploads_own_select on storage.objects;

-- Catálogo + proofs owner mantêm-se (recriar proofs se preciso)
drop policy if exists chat_media_public_catalog_select on storage.objects;
create policy chat_media_public_catalog_select
  on storage.objects
  for select
  using (
    bucket_id = 'chat_media'
    and (
      name like 'product_photos/%'
      or name like 'profile_photos/%'
      or name like 'live_item_photos/%'
      or name like 'live_raffle_prize/%'
    )
  );

drop policy if exists chat_media_proofs_owner_select on storage.objects;
create policy chat_media_proofs_owner_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'chat_media'
    and (
      name like 'order_proofs/%'
      or name like 'order_disputes/%'
    )
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  );

-- ---------------------------------------------------------------------------
-- 2) fleaber_private: chat_uploads + order_proofs/disputes (restaura counterparty)
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname ilike 'fleaber_private%'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy fleaber_private_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  )
  with check (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

create policy fleaber_private_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      name like ('order_proofs/' || auth.uid()::text || '/%')
      or name like ('order_disputes/' || auth.uid()::text || '/%')
      or name like ('chat_uploads/' || auth.uid()::text || '/%')
    )
  );

-- Vendedor/comprador lê provas do outro em encomenda partilhada
create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and name like ('order_proofs/' || o.buyer_id::text || '/%')
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where (o.seller_id = auth.uid() or o.buyer_id = auth.uid())
            and (
              name like ('order_disputes/' || o.buyer_id::text || '/%')
              or name like ('order_disputes/' || o.seller_id::text || '/%')
            )
        )
      )
    )
  );

-- Participante do chat lê media do outro (re-sign / open)
create policy fleaber_private_select_chat_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and name like 'chat_uploads/%'
    and exists (
      select 1
      from public.chats c
      where (
        (
          c.user_a = auth.uid()
          and name like ('chat_uploads/' || c.user_b::text || '/%')
        )
        or (
          c.user_b = auth.uid()
          and name like ('chat_uploads/' || c.user_a::text || '/%')
        )
      )
    )
  );

notify pgrst, 'reload schema';
