-- =============================================================================
-- E74 — DM kinds: accepted + expired_guaranteed (além dos kinds E7.1)
-- Preserva batata_commerce_post_reservation_dm; só alarga kinds messaged.
-- Dedup via commerce_reservation_dm_posts (já em prod).
-- =============================================================================

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
  v_kind text := trim(p_kind);
  v_claimed boolean := false;
  v_preview_ok boolean := false;
begin
  perform set_config('row_security', 'off', true);
  perform set_config('batata.allow_fleaber_res_dm', '1', true);

  if p_request_id is null or coalesce(v_kind, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  perform pg_advisory_xact_lock(
    hashtext(p_request_id::text || ':dm:' || v_kind)
  );

  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_req.buyer_id is null then
    return jsonb_build_object(
      'ok', true, 'skipped', true, 'reason', 'no_fleaber_buyer_id'
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
  v_marker := '[[fleaber_res:' || v_kind || ':' || p_request_id::text || ']]';

  if exists (
    select 1 from public.commerce_reservation_dm_posts d
    where d.request_id = p_request_id and d.kind = v_kind
  ) then
    if exists (
      select 1 from public.chat_messages m where m.text like '%' || v_marker || '%'
    ) then
      return jsonb_build_object(
        'ok', true, 'inserted', false, 'deduped', true, 'kind', v_kind
      );
    end if;
  else
    begin
      insert into public.commerce_reservation_dm_posts (request_id, kind, marker)
      values (p_request_id, v_kind, v_marker);
      v_claimed := true;
    exception when unique_violation then
      if exists (
        select 1 from public.chat_messages m where m.text like '%' || v_marker || '%'
      ) then
        return jsonb_build_object(
          'ok', true, 'inserted', false, 'deduped', true, 'kind', v_kind
        );
      end if;
    end;
  end if;

  if exists (
    select 1 from public.chat_messages m where m.text like '%' || v_marker || '%'
  ) then
    return jsonb_build_object(
      'ok', true, 'inserted', false, 'deduped', true, 'kind', v_kind
    );
  end if;

  v_chat := public.batata_commerce_ensure_dm_chat(v_req.buyer_id, v_req.seller_id, v_product);
  if v_chat is null then
    return jsonb_build_object('ok', false, 'error', 'chat_create_failed');
  end if;

  if v_kind in ('reservation_guaranteed', 'reservation_accepted') then
    if v_req.expires_at is not null then
      begin
        v_exp_local := to_char(
          timezone('Europe/Lisbon', v_req.expires_at), 'DD/MM/YYYY HH24:MI'
        );
      exception when others then
        v_exp_local := to_char(v_req.expires_at at time zone 'UTC', 'DD/MM/YYYY HH24:MI') || ' UTC';
      end;
    end if;
    v_preview := case
      when v_kind = 'reservation_accepted' then 'Reserva aceite · ' || v_ref
      else 'Reserva garantida · ' || v_ref
    end;
    v_body :=
      'Fleaber · sistema' || E'\n'
      || case when v_kind = 'reservation_accepted' then 'Reserva aceite' else 'Reserva garantida' end
      || E'\n'
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
  elsif v_kind = 'pending_expired_buyer_notice' then
    v_preview := 'Pedido de reserva expirado · ' || v_ref;
    v_body :=
      'Fleaber · sistema' || E'\n'
      || 'O teu pedido de reserva expirou.' || E'\n'
      || v_title || ' (' || v_ref || ')' || E'\n'
      || 'Enquanto estava pendente, o artigo não ficou garantido.'
      || E'\n\n' || v_marker;
  elsif v_kind = 'guaranteed_expired_buyer_notice' then
    v_preview := 'Reserva expirada · ' || v_ref;
    v_body :=
      'Fleaber · sistema' || E'\n'
      || 'A tua reserva expirou.' || E'\n'
      || v_title || ' (' || v_ref || ')' || E'\n'
      || 'O stock voltou a ficar disponível.'
      || E'\n\n' || v_marker;
  elsif v_kind = 'reservation_rejected' then
    v_preview := 'Pedido de reserva recusado · ' || v_ref;
    v_body :=
      'Fleaber · sistema' || E'\n'
      || 'O teu pedido de reserva não foi aceite.' || E'\n'
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

  update public.commerce_reservation_dm_posts
  set chat_id = v_chat
  where request_id = p_request_id and kind = v_kind;

  begin
    update public.chats
    set last_message = left(v_preview, 180),
        last_message_time = timezone('utc', now())
    where id = v_chat;
    v_preview_ok := true;
  exception when others then
    begin
      update public.chats
      set last_message_time = timezone('utc', now())
      where id = v_chat;
    exception when others then
      null;
    end;
    v_preview_ok := false;
  end;

  return jsonb_build_object(
    'ok', true,
    'inserted', true,
    'kind', v_kind,
    'chat_id', v_chat,
    'request_id', p_request_id,
    'atomic_claimed', v_claimed,
    'inbox_preview_updated', v_preview_ok
  );
end;
$$;

revoke all on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_post_reservation_dm(uuid, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';
