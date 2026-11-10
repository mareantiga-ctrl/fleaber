-- POS_BRBW BX–CC fecho 2026-09-06
-- P0:0 P1:5 P2:7 TOTAL:12 · production_touched:false · fase4:false · BATATA

-- ===========================================================================
-- BY — strip + rails Skrill/Neteller/… + enviando MB + canonical URL
-- ===========================================================================
create or replace function public.batata_chat_strip_format_controls(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    coalesce(p_text, ''),
    '[' || chr(8203) || chr(8204) || chr(8205) || chr(8206) || chr(8207)
      || chr(8234) || chr(8235) || chr(8236) || chr(8237) || chr(8238)
      || chr(8294) || chr(8295) || chr(8296) || chr(8297) || chr(8288)
      || chr(8291) || chr(8298) || chr(8299) || chr(8300) || chr(8301)
      || chr(8302) || chr(8303) || chr(847) || chr(1564) || chr(6155)
      || chr(6156) || chr(6157) || chr(6158) || chr(12644) || chr(65440)
      || chr(65279) || chr(173) || chr(160) || chr(8199) || chr(8200)
      || chr(8201) || chr(8202) || chr(8287) || ']+',
    '',
    'g'
  );
$$;

create or replace function public.batata_chat_normalize_lie_text(p_text text)
returns text
language sql
immutable
as $$
  select lower(
    translate(
      convert_from(
        convert_to(
          public.batata_chat_strip_format_controls(coalesce(p_text, '')),
          'UTF8'
        ),
        'UTF8'
      ),
      E'еЕаАоОрРсСхХуУіІΑαΡρΟοΕεΙιΚκΤτΥυΧχЅѕ' || chr(160)
        || E'ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ'
        || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ'
        || E'０１２３４５６７８９',
      E'eeaaooppssxxyyiiAaPpOoEeIiKkTtYyXxSs '
        || E'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        || E'abcdefghijklmnopqrstuvwxyz'
        || E'0123456789'
    )
  );
$$;

create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|venmo|payoneer|western\s*union|\mwu\M|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|crypto|coinbase|binance|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶|received)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|wise|revolut|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|mb\s*way|mbway|pix)\M'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\menviado\s*mb\M';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|pix|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o).{0,40}(confirmado|aprovado|processado|feito|caiu|received|€|eur|💶|\d)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|klarna|sofort|ideal|twint|afterpay|pix|paypal)\M';
$$;

-- Multi-pass URL canonical (CC + BY proof)
create or replace function public.batata_storage_url_path_canonical(p_url text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_url, '');
  i int;
begin
  v := split_part(split_part(v, '?', 1), '#', 1);
  -- strip bidi / directional / invisible
  v := regexp_replace(v,
    '[' || chr(8206) || chr(8207) || chr(8234) || chr(8235) || chr(8236)
      || chr(8237) || chr(8238) || chr(8294) || chr(8295) || chr(8296)
      || chr(8297) || chr(8234) || chr(8235) || chr(8236) || chr(8237)
      || chr(8238) || chr(8206) || chr(8207) || ']+',
    '', 'g');
  for i in 1..3 loop
    v := replace(v, E'／', '/');
    v := replace(v, E'＼', '/');
    v := replace(v, E'∕', '/');
    v := replace(v, E'⁄', '/');
    v := replace(v, E'⧸', '/');
    v := replace(v, E'．', '.');
    v := replace(v, E'․', '.');
    v := replace(v, chr(92), '/');
    v := regexp_replace(v, '%c0%ae', '.', 'gi');
    v := regexp_replace(v, '%c0%af', '/', 'gi');
    v := regexp_replace(v, '%c1%9c', '/', 'gi');
    v := regexp_replace(v, '%e0%80%ae', '.', 'gi');
    v := regexp_replace(v, '%e0%80%af', '/', 'gi');
    v := regexp_replace(v, '%252e', '.', 'gi');
    v := regexp_replace(v, '%252f', '/', 'gi');
    v := regexp_replace(v, '%255c', '/', 'gi');
    v := regexp_replace(v, '%2e', '.', 'gi');
    v := regexp_replace(v, '%2f', '/', 'gi');
    v := regexp_replace(v, '%5c', '/', 'gi');
  end loop;
  return lower(v);
end;
$$;

-- guards refreshed
create or replace function public.batata_chat_messages_guard_image_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text;
  v_json jsonb;
  v_kind text;
  v_url text;
  v_path text;
  v_notes text;
  v_label text;
  v_display text;
  v_order uuid;
  v_buyer uuid;
  v_prefix text;
begin
  v_raw := coalesce(NEW.text, '');
  if position('FLEABER_JSON_V1:' in v_raw) = 0 then
    return NEW;
  end if;
  begin
    v_json := (regexp_replace(v_raw, '^.*?FLEABER_JSON_V1:', ''))::jsonb;
  exception when others then
    return NEW;
  end;
  v_kind := lower(trim(coalesce(v_json->>'kind', '')));

  if v_kind = 'chat_image' then
    v_url := public.batata_storage_url_path_canonical(coalesce(v_json->>'url', ''));
    if v_url <> '' then
      if v_url like '%/object/public/%' or v_url like 'javascript:%' or v_url like 'data:%'
         or v_url like '%..%' or v_url like '%25%2e%2e%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like '%/object/sign/%'
         and v_url not like '%/object/authenticated/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'reservation_payment_submitted' then
    if v_json ? 'meta' or v_json ? 'rail' or v_json ? 'status' then
      raise exception 'chat_system_card_payload_forbidden' using errcode = '23514';
    end if;
    v_notes := coalesce(v_json->>'notes', '');
    if v_notes ~ '[<>]' or public.batata_chat_payment_lie_text(v_notes) then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    if public.batata_chat_normalize_lie_text(v_notes) ~*
       '(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple|google|mb\s*way|mbway|pix|multibanco)' then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    begin
      v_order := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
    exception when others then
      v_order := null;
    end;
    v_url := public.batata_storage_url_path_canonical(coalesce(v_json->>'proof_url', ''));
    if v_url <> '' then
      if v_url like '%/object/public/%' or v_url like 'javascript:%' or v_url like 'data:%'
         or v_url like '%..%' or position('%2e%2e' in v_url) > 0 then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_url not like '%/object/sign/fleaber_private/%'
         and v_url not like '%/object/authenticated/fleaber_private/%'
         and v_url not like '%/object/fleaber_private/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_order is null then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      select buyer_id into v_buyer from public.orders where id = v_order;
      v_path := v_url;
      v_prefix := 'fleaber_private/order_proofs/' || coalesce(v_buyer::text, '')
        || '/' || v_order::text || '/';
      if v_buyer is null
         or position(v_prefix in v_path) = 0 then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_path !~ ('fleaber_private/order_proofs/' || v_buyer::text || '/' || v_order::text || '/') then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if public.batata_chat_normalize_lie_text(v_label) ~*
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|seguro|pago no mb|transfer|cart[aÃ£]o|multibanco)' then
      raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
    end if;
    if public.batata_chat_payment_lie_text(v_label) then
      raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'cancel_request_outcome' then
    v_display := coalesce(v_json->>'display', '');
    if public.batata_chat_payment_lie_text(v_display) then
      raise exception 'chat_system_card_display_forbidden' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;
create or replace function public.batata_order_dispute_replies_guard_proof()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_path text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid;
  v_needle text;
begin
  if NEW.proof_photos is null then
    return NEW;
  end if;
  select d.order_id, o.buyer_id into v_oid, v_buyer
  from public.order_disputes d
  join public.orders o on o.id = d.order_id
  where d.id = NEW.dispute_id;
  v_needle := case
    when v_buyer is not null and v_oid is not null then
      'order_disputes/' || v_buyer::text || '/' || v_oid::text || '/'
    else null
  end;
  begin
    v_arr := to_jsonb(NEW.proof_photos);
  exception when others then
    raise exception 'dispute_proof_url_denied' using errcode = '23514';
  end;
  if jsonb_typeof(v_arr) <> 'array' then
    return NEW;
  end if;
  for v_url in
    select public.batata_storage_url_path_canonical(coalesce(elem, ''))
    from jsonb_array_elements_text(v_arr) as t(elem)
  loop
    if v_url = '' then continue; end if;
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%..%'
       or position('%2e%2e' in v_url) > 0 then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url not like '%/object/sign/fleaber_private/%'
       and v_url not like '%/object/authenticated/fleaber_private/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    v_path := v_url;
    if v_needle is null or position(v_needle in v_path) = 0 then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_path !~ ('fleaber_private/' || v_needle) then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
  end loop;
  return NEW;
end;
$fn$;
create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_path text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid := NEW.order_id;
  v_needle text;
begin
  select buyer_id into v_buyer from public.orders where id = v_oid;
  v_needle := case
    when v_buyer is not null and v_oid is not null then
      'order_disputes/' || v_buyer::text || '/' || v_oid::text || '/'
    else null
  end;

  if NEW.proof_photos is not null then
    begin
      v_arr := to_jsonb(NEW.proof_photos);
    exception when others then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end;
    if jsonb_typeof(v_arr) = 'array' then
      for v_url in
        select public.batata_storage_url_path_canonical(coalesce(elem, ''))
        from jsonb_array_elements_text(v_arr) as t(elem)
      loop
        if v_url = '' then continue; end if;
        if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
           or v_url ~ '[\n\r<>"]' or v_url like '%/object/public/%'
           or v_url like '%..%' or position('%2e%2e' in v_url) > 0 then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        if v_url not like '%/object/sign/fleaber_private/%'
           and v_url not like '%/object/authenticated/fleaber_private/%' then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        v_path := v_url;
        if v_needle is null or position(v_needle in v_path) = 0 then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
        if v_path !~ ('fleaber_private/' || v_needle) then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
      end loop;
    end if;
  end if;

  if NEW.return_label_url is not null
     and nullif(trim(NEW.return_label_url), '') is not null then
    v_url := public.batata_storage_url_path_canonical(NEW.return_label_url);
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%/object/public/%'
       or v_url like '%..%' then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
    v_path := v_url;
    if v_needle is null or position(v_needle in v_path) = 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- BZ FOMO synonyms
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
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;
  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  v_norm := lower(v_body);
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff\u2800-\u28ff]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüç0оОсС'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucoooss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[^a-z0-9€🛒✅\s]', '', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|esgotado|esgotada|esgotados|vendido|vendida|sold|sold out|adquiriu|encomenda|c0mprou|snapped|snap up|claimed|grabbed|took it|its gone|it s gone|its mine|it s mine|that s mine|thats mine|mine now|mine|reserved for|reserved|gone|acabou|out of stock|outofstock|no more|taken|it s taken|its taken|last one|last 1|last piece|last available|1 left|only one left|ja nao ha|ja nao ha|nao ha mais|ja nao existe|fora de stock|sem stock|stock 0|zero stock|unavailable|off sale|ja saiu|no quedan|ultima unidade)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab|stock|taken|mine|last|reserved)') then
    return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller from public.lives where id = p_live_id;
  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;
  if v_uid is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_manage_chat') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_live_system_message', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;
  if v_hits > 60 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.live_messages (live_id, user_id, kind, body, sender_label)
  values (p_live_id, v_uid, 'system', v_body,
          coalesce(nullif(trim(p_sender_label), ''), 'Sistema'));
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text) from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text) to authenticated, service_role;

-- BZ/CA: mux_playback_id nao legivel por JWT generico (Hub/Edge)
revoke select (mux_playback_id, mux_vod_playback_id, mux_asset_id, mux_stream_key, stream_key)
  on public.lives from authenticated;
revoke select (mux_playback_id, mux_vod_playback_id, mux_asset_id, mux_stream_key, stream_key)
  on public.lives from anon;

-- CA: resolve_handle so hub_published
create or replace function public.batata_resolve_handle(p_handle text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_in text := public.batata_normalize_handle(p_handle);
  v_profile_id uuid;
  v_handle text;
  v_published boolean;
  v_redirect text;
begin
  if v_in = '' then
    return jsonb_build_object('found', false, 'error', 'not_found', 'http_status', 404);
  end if;

  select p.id, p.handle, p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where p.handle = v_in
  limit 1;

  if v_profile_id is not null and coalesce(v_published, false) then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', true,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  if v_profile_id is not null then
    return jsonb_build_object('found', false, 'error', 'not_found', 'http_status', 404);
  end if;

  select
    p.id,
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name),
    p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name) = v_in
  limit 1;

  if v_profile_id is not null and coalesce(v_published, false) then
    return jsonb_build_object(
      'found', true,
      'profile_id', v_profile_id,
      'handle', v_handle,
      'hub_published', true,
      'redirect_to', null,
      'http_status', 200
    );
  end if;

  select r.new_handle into v_redirect
  from public.profile_handle_redirects r
  where r.old_handle = v_in
    and (r.redirect_until is null or r.redirect_until > now())
  limit 1;

  if v_redirect is not null then
    return jsonb_build_object(
      'found', true,
      'profile_id', (select p.id from public.profiles p where p.handle = v_redirect limit 1),
      'handle', v_redirect,
      'redirect_to', v_redirect,
      'hub_published', (select p.hub_published from public.profiles p where p.handle = v_redirect limit 1),
      'http_status', 301
    );
  end if;

  return jsonb_build_object('found', false, 'error', 'not_found', 'http_status', 404);
end;
$$;

grant execute on function public.batata_resolve_handle(text) to anon, authenticated, service_role;

-- CA: discovery profiles so publicados
create or replace view public.hub_profiles_discovery_public
with (security_barrier = true)
as
select
  p.id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name) as handle,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  coalesce(p.vacation_mode, false) as vacation_mode,
  (p.phone_verified_at is not null) as phone_verified,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  coalesce(vs.total_seguidores, 0)::int as follower_count,
  nullif(trim(p.hub_bio), '') as hub_bio,
  coalesce(p.hub_published, false) as hub_published
from public.profiles p
left join public.v_seguidores_stats vs on vs.profile_id = p.id
where coalesce(p.hub_published, false) = true
  and length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2;

grant select on public.hub_profiles_discovery_public to anon, authenticated;

notify pgrst, 'reload schema';