-- =============================================================================
-- BATATA 2026-09-12 — chat live OCR + propostas expiradas + directory chat
--
-- 1) accept_broadcast: reservas FB/OCR com buyer_id NULL usam external_display_name
-- 2) expire offers: payload com prefixo FLEABER_JSON_V1: (+ backfill)
-- 3) profiles_directory_public: incluir contraparte de chat existente
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Reserva aceite → mensagem no chat do directo (inclui FB sem buyer_id)
-- ---------------------------------------------------------------------------
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
  v_ref text;
  v_title text;
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

  -- BN-P2: só seller/staff (ou service) — buyer não forja «Reserva aceite»
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

  select coalesce(nullif(trim(ref_code), ''), ''), coalesce(nullif(trim(title), ''), '')
  into v_ref, v_title from public.live_items where id = p_live_item_id limit 1;

  if v_title <> '' then v_label := v_title;
  elsif v_ref <> '' then v_label := 'Ref ' || v_ref;
  else v_label := 'artigo';
  end if;

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
    where m.live_id = p_live_id and m.kind = 'system' and m.body = v_body
      and m.created_at > now() - interval '15 minutes'
  ) then
    return false;
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label)
  values (
    p_live_id,
    coalesce(v_uid, p_buyer_id, v_seller),
    'system',
    v_body,
    'Sistema'
  );
  return true;
end;
$$;

comment on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) is
  'Publica «Reserva aceite» no chat do directo. buyer_id NULL = FB/OCR (usa external_display_name).';

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Propostas expiradas: prefixo FLEABER_JSON_V1: (UI do chat)
-- ---------------------------------------------------------------------------
create or replace function public.batata_expire_product_offers()
returns integer
language plpgsql
security definer
set search_path = public
as $batata_expire_product_offers$
declare
  r record;
  v_count integer := 0;
  v_amount text;
  v_payload text;
  v_preview text;
begin
  for r in
    select *
    from public.product_offers
    where status = 'pending'
      and expires_at < now()
    for update skip locked
  loop
    update public.product_offers
    set
      status = 'expired',
      responded_at = now()
    where id = r.id;

    v_count := v_count + 1;

    if r.chat_id is null then
      continue;
    end if;

    v_amount := to_char(r.amount, 'FM999999990.00') || ' €';
    v_preview := 'Proposta expirada (' || v_amount || ')';
    v_payload := 'FLEABER_JSON_V1:' || jsonb_build_object(
      'kind', 'price_offer_outcome',
      'offer_id', r.id,
      'product_id', r.product_id,
      'buyer_id', r.buyer_id,
      'seller_id', r.seller_id,
      'amount', r.amount,
      'outcome', 'expired',
      'offered_by', r.offered_by,
      'v', 1
    )::text;

    insert into public.chat_messages (
      sender_id,
      receiver_id,
      chat_id,
      text,
      is_read,
      is_reservation
    )
    values (
      r.seller_id,
      r.buyer_id,
      r.chat_id,
      v_payload,
      false,
      false
    );

    update public.chats
    set
      last_message = v_preview,
      last_message_time = now()
    where id = r.chat_id;
  end loop;

  return v_count;
end;
$batata_expire_product_offers$;

comment on function public.batata_expire_product_offers() is
  'Marca propostas pending expiradas e regista outcome no chat com FLEABER_JSON_V1:.';

-- Backfill mensagens já gravadas sem prefixo (só price_offer_outcome / price_offer bare JSON)
update public.chat_messages
set text = 'FLEABER_JSON_V1:' || text
where text like '{%'
  and text like '%"kind"%'
  and (
    text like '%"price_offer_outcome"%'
    or text like '%"price_offer"%'
  )
  and text not like 'FLEABER_JSON_V1:%';

-- ---------------------------------------------------------------------------
-- 3) Directory: contraparte de chat (sem reabrir PII — mesma view)
-- ---------------------------------------------------------------------------
create or replace view public.profiles_directory_public
with (security_barrier = true)
as
select
  p.id,
  p.created_at,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  p.user_type,
  p.handle,
  coalesce(p.vacation_mode, false) as vacation_mode,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  (p.phone_verified_at is not null) as phone_verified
from public.profiles p
where coalesce(p.hub_published, false) = true
   or p.id = auth.uid()
   or exists (
     select 1
     from public.chats c
     where auth.uid() is not null
       and (
         (c.user_a = auth.uid() and c.user_b = p.id)
         or (c.user_b = auth.uid() and c.user_a = p.id)
       )
   );

comment on view public.profiles_directory_public is
  'Directory autenticada = hub_published OU self OU contraparte de chat. Sem PII sensível.';

grant select on public.profiles_directory_public to authenticated;
revoke all on public.profiles_directory_public from anon;
