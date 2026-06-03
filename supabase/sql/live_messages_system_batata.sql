-- Fleaber BATATA: mensagens de sistema no chat público da live (Fase 2).
-- Alteração mínima: preserva chat/tip e adiciona kind=system.

do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.live_messages'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    execute format('alter table public.live_messages drop constraint if exists %I', c.conname);
  end loop;
exception
  when undefined_table then
    null;
end $$;

alter table public.live_messages
  add constraint live_messages_kind_check
  check (kind in ('chat', 'tip', 'system'));

create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_live public.lives%rowtype;
begin
  if p_live_id is null or coalesce(trim(p_body), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    v_uid,
    'system',
    trim(p_body),
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text) from public;
grant execute on function public.batata_live_system_message(uuid, text, text) to authenticated;

-- Anúncio público de compra (Stripe / saco convertido). Idempotente ~15 min.
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
  v_name text;
  v_ref text;
  v_title text;
  v_label text;
  v_body text;
begin
  if p_live_id is null or p_buyer_id is null or p_live_item_id is null then
    return false;
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

  if v_ref <> '' then
    v_label := 'Ref ' || v_ref;
  elsif v_title <> '' then
    v_label := v_title;
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

revoke all on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) from public;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) to authenticated;
grant execute on function public.batata_live_purchase_broadcast(uuid, uuid, uuid) to service_role;

notify pgrst, 'reload schema';
