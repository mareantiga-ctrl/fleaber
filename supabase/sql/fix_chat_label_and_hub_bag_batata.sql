-- =============================================================================
-- BATATA 2026-09-13 — labels chat limpos (Ref sem «Qty N») + cancel aceite FB
-- =============================================================================

-- Label estável para chat: preferir Ref CODE; nunca título com «Qty …»
create or replace function public.batata_live_item_chat_label(p_live_item_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ref text;
  v_title text;
  v_clean text;
begin
  if p_live_item_id is null then
    return 'artigo';
  end if;

  select coalesce(nullif(trim(ref_code), ''), ''),
         coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title
  from public.live_items
  where id = p_live_item_id
  limit 1;

  v_clean := regexp_replace(v_ref, '^#+', '');
  if v_clean <> '' then
    return 'Ref ' || v_clean;
  end if;

  -- Título sem sufixo de stock («· Qty 10» / «- qtd 10»)
  v_title := regexp_replace(
    v_title,
    '\s*[·\-–—|•]\s*(?:Qty|qtd|quantidade)\s*\d+\s*$',
    '',
    'i'
  );
  if v_title <> '' and v_title !~* '(qty|qtd)\s*\d+' then
    return v_title;
  end if;

  return 'artigo';
end;
$$;

revoke all on function public.batata_live_item_chat_label(uuid) from public;
grant execute on function public.batata_live_item_chat_label(uuid)
  to authenticated, service_role;

-- Announce pending: label limpo
create or replace function public.batata_live_announce_pending_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_label text;
  v_body text;
  v_channel text := 'fleaber';
  v_user uuid;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if lower(trim(coalesce(new.status, ''))) is distinct from 'pending' then
    return new;
  end if;
  if lower(trim(coalesce(new.ingest_status, ''))) = 'rejected' then
    return new;
  end if;
  if new.live_id is null or new.live_item_id is null then
    return new;
  end if;

  if new.buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(handle), ''), 'Comprador')
    into v_name
    from public.profiles
    where id = new.buyer_id;
  end if;
  if v_name is null or trim(v_name) = '' then
    v_name := coalesce(nullif(trim(new.external_display_name), ''), 'Comprador');
  end if;

  v_label := public.batata_live_item_chat_label(new.live_item_id);
  v_body := '🛍️ ' || v_name || ' reservou ' || v_label;

  if lower(trim(coalesce(new.source, ''))) = 'facebook_manual' then
    -- Mantém-se fleaber: anúncio social público (não OCR).
    v_channel := 'fleaber';
  end if;

  v_user := coalesce(new.buyer_id, new.seller_id);

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = new.live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return new;
  end if;

  begin
    insert into public.live_messages (
      live_id, user_id, kind, body, sender_label, channel
    ) values (
      new.live_id, v_user, 'system', v_body, 'Sistema', v_channel
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

-- Accept broadcast: label limpo + qty real do pedido
create or replace function public.batata_live_reservation_accept_broadcast(
  p_live_id uuid,
  p_buyer_id uuid,
  p_live_item_id uuid,
  p_requested_qty integer default 1
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
  v_label text;
  v_body text;
  v_qty integer;
  v_has_accept boolean := false;
begin
  if p_live_id is null or p_live_item_id is null then
    return false;
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller from public.lives where id = p_live_id;
  if v_seller is null then
    return false;
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null or v_role is distinct from 'authenticated' then
      return false;
    end if;
    if v_uid is distinct from v_seller
       and not public.batata_staff_has_permission(v_seller, 'can_manage_chat')
       and not public.batata_staff_has_permission(v_seller, 'can_manage_reservations') then
      return false;
    end if;
  end if;

  select exists(
    select 1 from public.live_reservation_requests r
    where r.live_id = p_live_id
      and r.live_item_id = p_live_item_id
      and r.status = 'accepted'
      and (
        (p_buyer_id is not null and r.buyer_id = p_buyer_id)
        or (p_buyer_id is null and r.buyer_id is null)
      )
  ) into v_has_accept;
  if not coalesce(v_has_accept, false) then
    return false;
  end if;

  if p_buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), 'Comprador') into v_name
    from public.profiles where id = p_buyer_id;
  else
    select coalesce(
      nullif(trim(r.external_display_name), ''),
      'Comprador Facebook'
    )
    into v_name
    from public.live_reservation_requests r
    where r.live_id = p_live_id
      and r.live_item_id = p_live_item_id
      and r.status = 'accepted'
      and r.buyer_id is null
    order by r.updated_at desc nulls last, r.created_at desc
    limit 1;
  end if;
  v_name := coalesce(nullif(trim(v_name), ''), 'Comprador');

  v_label := public.batata_live_item_chat_label(p_live_item_id);
  v_qty := greatest(coalesce(p_requested_qty, 1), 1);

  if v_qty > 1 then
    v_body := '🔒 Reserva aceite — ' || v_qty || ' un. · ' || v_label
      || ' · ' || v_name || ' tem 5 dias para pagar';
  else
    v_body := '🔒 Reserva aceite — ' || v_label || ' · ' || v_name
      || ' tem 5 dias para pagar';
  end if;

  if exists (
    select 1 from public.live_messages m
    where m.live_id = p_live_id and m.body = v_body
      and m.created_at > now() - interval '2 minutes'
  ) then
    return true;
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label)
  values (p_live_id, coalesce(p_buyer_id, v_seller), 'system', v_body, 'Sistema');
  return true;
end;
$$;

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';
