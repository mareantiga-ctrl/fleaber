-- =============================================================================
-- BATATA 2026-10-09 — Phase 7: Fleaber 1:1 DM notices for reservation lifecycle
-- Staging only. Production untouched. No Meta Messenger. No new reservation engine.
-- Essential messages only (D19 guarantee + pending expire + reject).
-- Idempotent via commerce_reservation_events (request_id, kind).
-- =============================================================================

-- Allow reject event kind (buyer notice)
alter table public.commerce_reservation_events
  drop constraint if exists commerce_reservation_events_kind_check;

alter table public.commerce_reservation_events
  add constraint commerce_reservation_events_kind_check
  check (kind in (
    'reservation_guaranteed',
    'pending_expired_buyer_notice',
    'pending_stock_unavailable',
    'guaranteed_expired',
    'extension_applied',
    'promotion_applied',
    'promotion_skipped_no_stock',
    'guaranteed_cancelled_by_buyer',
    'reservation_rejected'
  ));

-- Ensure 1:1 chat (reuse product scope when available)
create or replace function public.batata_commerce_ensure_dm_chat(
  p_buyer_id uuid,
  p_seller_id uuid,
  p_product_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chat uuid;
begin
  if p_buyer_id is null or p_seller_id is null or p_buyer_id = p_seller_id then
    return null;
  end if;

  if p_product_id is not null then
    select c.id into v_chat
    from public.chats c
    where c.product_id = p_product_id
      and (
        (c.user_a = p_buyer_id and c.user_b = p_seller_id)
        or (c.user_a = p_seller_id and c.user_b = p_buyer_id)
      )
      and coalesce(nullif(trim(c.last_message), ''), '') <> ''
    order by coalesce(c.last_message_time, c.created_at) desc nulls last
    limit 1;

    if v_chat is null then
      select c.id into v_chat
      from public.chats c
      where c.product_id = p_product_id
        and (
          (c.user_a = p_buyer_id and c.user_b = p_seller_id)
          or (c.user_a = p_seller_id and c.user_b = p_buyer_id)
        )
      order by coalesce(c.last_message_time, c.created_at) desc nulls last
      limit 1;
    end if;
  end if;

  if v_chat is null then
    -- Prefer general thread (no product) with preview
    select c.id into v_chat
    from public.chats c
    where c.product_id is null
      and (
        (c.user_a = p_buyer_id and c.user_b = p_seller_id)
        or (c.user_a = p_seller_id and c.user_b = p_buyer_id)
      )
      and coalesce(nullif(trim(c.last_message), ''), '') <> ''
    order by coalesce(c.last_message_time, c.created_at) desc nulls last
    limit 1;
  end if;

  if v_chat is null then
    insert into public.chats (user_a, user_b, product_id)
    values (p_buyer_id, p_seller_id, p_product_id)
    returning id into v_chat;
  end if;

  return v_chat;
end;
$$;

revoke all on function public.batata_commerce_ensure_dm_chat(uuid, uuid, uuid) from public;
grant execute on function public.batata_commerce_ensure_dm_chat(uuid, uuid, uuid)
  to service_role;

-- Post essential buyer DM (plain text — not forgeable JSON card)
create or replace function public.batata_commerce_post_reservation_dm(
  p_request_id uuid,
  p_kind text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_li public.live_items%rowtype;
  v_product uuid;
  v_ref text;
  v_title text;
  v_qty int;
  v_chat uuid;
  v_body text;
  v_preview text;
  v_exp_local text;
  v_marker text;
  v_exists boolean;
begin
  if p_request_id is null or coalesce(trim(p_kind), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- Fleaber DM requires a linked Fleaber buyer (guest-only FB has no chat uuid)
  if v_req.buyer_id is null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'no_fleaber_buyer_id',
      'hint', 'claim_or_link_account_first'
    );
  end if;

  if v_req.seller_id is null or v_req.buyer_id = v_req.seller_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_parties');
  end if;

  select * into v_li from public.live_items where id = v_req.live_item_id;
  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  v_ref := coalesce(nullif(trim(v_li.ref_code), ''), 'artigo');
  v_title := coalesce(nullif(trim(v_li.title), ''), v_ref);
  v_qty := greatest(coalesce(v_req.requested_qty, 1), 1);

  v_marker := '[[fleaber_res:' || p_kind || ':' || p_request_id::text || ']]';

  -- Idempotent against retries (even if event row already existed)
  select exists (
    select 1 from public.chat_messages m
    where m.text like '%' || v_marker || '%'
  ) into v_exists;
  if v_exists then
    return jsonb_build_object('ok', true, 'inserted', false, 'deduped', true, 'kind', p_kind);
  end if;

  v_chat := public.batata_commerce_ensure_dm_chat(v_req.buyer_id, v_req.seller_id, v_product);
  if v_chat is null then
    return jsonb_build_object('ok', false, 'error', 'chat_create_failed');
  end if;

  if p_kind = 'reservation_guaranteed' then
    if v_req.expires_at is not null then
      v_exp_local := to_char(
        timezone('Europe/Lisbon', v_req.expires_at),
        'DD/MM/YYYY HH24:MI'
      );
    else
      v_exp_local := null;
    end if;
    v_preview := 'Reserva garantida · ' || v_ref;
    v_body :=
      'Reserva garantida' || E'\n'
      || v_title || ' (' || v_ref || ') · ' || v_qty::text
      || case when v_qty = 1 then ' unidade' else ' unidades' end || E'\n'
      || case
           when v_exp_local is not null then
             'Reservado até ' || v_exp_local || ' (hora de Lisboa).' || E'\n'
             || 'Paga no saco até esta hora.'
           else
             'Paga no saco para concluir a compra.'
         end
      || E'\n\n' || v_marker;
  elsif p_kind = 'pending_expired_buyer_notice' then
    v_preview := 'Pedido de reserva expirado · ' || v_ref;
    v_body :=
      'O teu pedido de reserva expirou.' || E'\n'
      || v_title || ' (' || v_ref || ')' || E'\n'
      || 'Enquanto estava pendente, o artigo não ficou garantido. '
      || 'Se ainda houver stock, podes pedir de novo ou pagar no saco.'
      || E'\n\n' || v_marker;
  elsif p_kind = 'reservation_rejected' then
    v_preview := 'Pedido de reserva recusado · ' || v_ref;
    v_body :=
      'O teu pedido de reserva não foi aceite.' || E'\n'
      || v_title || ' (' || v_ref || ')' || E'\n'
      || 'O artigo não ficou reservado.'
      || E'\n\n' || v_marker;
  else
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'kind_not_messaged');
  end if;

  insert into public.chat_messages (
    sender_id, receiver_id, chat_id, text, is_read, is_reservation
  ) values (
    v_req.seller_id, v_req.buyer_id, v_chat, v_body, false, true
  );

  update public.chats
  set last_message = left(v_preview, 180),
      last_message_time = timezone('utc', now())
  where id = v_chat;

  return jsonb_build_object(
    'ok', true,
    'inserted', true,
    'kind', p_kind,
    'chat_id', v_chat,
    'request_id', p_request_id,
    'buyer_id', v_req.buyer_id,
    'seller_id', v_req.seller_id
  );
end;
$$;

revoke all on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb)
  to service_role;

-- Emit event + post DM when newly inserted (idempotent)
create or replace function public.batata_commerce_emit_reservation_event(
  p_request_id uuid,
  p_kind text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
  v_dm jsonb;
  v_kind text := trim(p_kind);
begin
  if p_request_id is null or coalesce(v_kind, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  begin
    insert into public.commerce_reservation_events (request_id, kind, payload)
    values (p_request_id, v_kind, coalesce(p_payload, '{}'::jsonb));
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  -- Essential DMs only on first insert (no flood on retries)
  if v_inserted and v_kind in (
    'reservation_guaranteed',
    'pending_expired_buyer_notice',
    'reservation_rejected'
  ) then
    begin
      v_dm := public.batata_commerce_post_reservation_dm(
        p_request_id, v_kind, coalesce(p_payload, '{}'::jsonb)
      );
    exception when others then
      v_dm := jsonb_build_object(
        'ok', false,
        'error', 'dm_post_failed',
        'sqlstate', SQLSTATE,
        'sqlerrm', SQLERRM
      );
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'inserted', v_inserted,
    'kind', v_kind,
    'dm', v_dm
  );
end;
$$;

revoke all on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb)
  to service_role;

-- Reject pending → emit rejected (triggers DM once)
create or replace function public.batata_commerce_reject_pending(
  p_request_id uuid,
  p_processed_by uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_req public.live_reservation_requests%rowtype;
  v_event jsonb;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
    if v_uid is null or v_uid is distinct from v_req.seller_id then
      if not public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations') then
        return jsonb_build_object('ok', false, 'error', 'seller_only');
      end if;
    end if;
  end if;

  if v_req.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;

  update public.live_reservation_requests
  set
    status = 'rejected',
    expiry_reason = 'seller_cancelled',
    notes = coalesce(p_notes, notes),
    processed_by_user_id = coalesce(p_processed_by, v_uid),
    updated_at = timezone('utc', now())
  where id = v_req.id
  returning * into v_req;

  begin
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then
    null;
  end;

  v_event := public.batata_commerce_emit_reservation_event(
    v_req.id,
    'reservation_rejected',
    jsonb_build_object(
      'source', 'seller_reject',
      'live_item_id', v_req.live_item_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'outcome', 'REJECTED',
    'request_id', v_req.id,
    'status', v_req.status,
    'event', v_event
  );
end;
$$;

revoke all on function public.batata_commerce_reject_pending(uuid, uuid, text) from public;
grant execute on function public.batata_commerce_reject_pending(uuid, uuid, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
