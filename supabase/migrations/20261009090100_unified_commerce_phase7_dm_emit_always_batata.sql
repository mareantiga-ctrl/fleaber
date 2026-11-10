-- Phase 7.1 — always attempt DM after guarantee/expire/reject (idempotent marker).
-- Surfaces DM errors instead of silent null when event already exists.

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
  -- Ensure system path is not blocked by caller JWT RLS edge-cases
  perform set_config('row_security', 'off', true);

  if p_request_id is null or coalesce(trim(p_kind), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

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
      begin
        v_exp_local := to_char(
          timezone('Europe/Lisbon', v_req.expires_at),
          'DD/MM/YYYY HH24:MI'
        );
      exception when others then
        v_exp_local := to_char(v_req.expires_at at time zone 'UTC', 'DD/MM/YYYY HH24:MI') || ' UTC';
      end;
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
  v_dm jsonb := null;
  v_kind text := trim(p_kind);
begin
  perform set_config('row_security', 'off', true);

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

  -- Always attempt essential DMs (post is marker-idempotent) so a failed first
  -- attempt can heal on retry without duplicating events.
  if v_kind in (
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

revoke all on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb)
  to service_role;

revoke all on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';
