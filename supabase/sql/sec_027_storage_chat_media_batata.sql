-- SEC-027 — Storage chat_media versionado no repo (BATATA)
-- + SEC-020 residual: purchase_broadcast só buyer/seller/staff (não spam alheio)
--
-- Storage: bucket público para getPublicUrl (como a app usa hoje).
-- INSERT autenticado (chat_uploads / order_proofs SEM uid no path — não partir).
-- UPDATE só em pastas com uid (profile/product/live photos — upsert).
-- Anon NÃO escreve.
-- Se o Dashboard já tiver policies com outros nomes, as *chat_media* antigas são
-- removidas e estas substituem; policies genéricas sem "chat_media" no nome
-- podem coexistir (rever no Dashboard após aplicar).

-- =============================================================================
-- SEC-027 — bucket + policies
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('chat_media', 'chat_media', true)
on conflict (id) do update
set public = true;

do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname ilike '%chat_media%'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

-- Leitura pública (URLs getPublicUrl na app / Hub)
create policy chat_media_public_select
  on storage.objects
  for select
  using (bucket_id = 'chat_media');

-- Upload: qualquer autenticado (mantém chat_uploads/ e order_proofs/ sem uid)
create policy chat_media_auth_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
  );

-- Update/upsert: objecto cujo path contém o próprio uid
-- (profile_photos/{uid}/…, product_photos/{uid}/…, order_disputes/{uid}_…)
create policy chat_media_auth_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  )
  with check (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  );

-- Delete: só se o path contém o próprio uid
create policy chat_media_auth_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'chat_media'
    and auth.uid() is not null
    and position(auth.uid()::text in name) > 0
  );

-- =============================================================================
-- SEC-020 residual — purchase broadcast: buyer da compra ou seller/staff
-- =============================================================================

create or replace function public.batata_live_purchase_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
  v_name text;
  v_ref text;
  v_title text;
  v_label text;
  v_body text;
begin
  if p_live_id is null or p_buyer_id is null or p_live_item_id is null then
    return false;
  end if;

  -- Cliente autenticado: só anuncia a própria compra, ou seller/staff da live.
  -- service_role / nested DEFINER sem JWT: ok.
  if v_role = 'authenticated' and v_uid is not null then
    if v_uid is distinct from p_buyer_id then
      select coalesce(l.seller_id, l.vendedor_id)
      into v_seller
      from public.lives l
      where l.id = p_live_id;
      if v_seller is null
         or (
           v_seller is distinct from v_uid
           and not public.batata_staff_has_permission(v_seller, 'can_manage_chat')
         ) then
        return false;
      end if;
    end if;
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Comprador')
  into v_name
  from public.profiles
  where id = p_buyer_id;

  select coalesce(nullif(trim(ref_code), ''), ''),
         coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title
  from public.live_items
  where id = p_live_item_id
  limit 1;

  if v_title <> '' then
    v_label := v_title;
  elsif v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  else
    v_label := 'artigo';
  end if;

  v_body := '✅ ' || v_name || ' comprou ' || v_label;

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = p_live_id
      and m.kind = 'system'
      and m.user_id = p_buyer_id
      and m.body = v_body
      and m.created_at > now() - interval '15 minutes'
  ) then
    return false;
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    p_buyer_id,
    'system',
    v_body,
    v_name
  );

  return true;
end;
$$;

revoke all on function public.batata_live_purchase_broadcast(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
