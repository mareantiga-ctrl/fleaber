-- POS_BLBQ BR–BW fecho 2026-09-06
-- production_touched: false · fase4: false · BATATA
-- P0:0 P1:5 P2:9 P3:1 TOTAL:15

-- ===========================================================================
-- BS — strip format controls (U+180E, Hangul filler, invisible sep) + rails novas
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
      || chr(8291) || chr(8288) || chr(6158) || chr(12644) || chr(65279)
      || chr(173) || chr(160) || chr(8199) || chr(8200) || chr(8201)
      || chr(8202) || chr(8287) || ']+',
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
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|venmo|payoneer|western\s*union|\mwu\M|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|crypto|coinbase|binance|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶|received)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|wise|revolut|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|mb\s*way|mbway|pix)\M';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|pix|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o).{0,40}(confirmado|aprovado|processado|feito|caiu|received|€|eur|💶|\d)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|klarna|sofort|ideal|twint|afterpay|pix|paypal)\M';
$$;

-- Canonicalize storage URL path before proof checks
create or replace function public.batata_storage_url_path_canonical(p_url text)
returns text
language sql
immutable
as $$
  select lower(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          replace(replace(
            split_part(split_part(coalesce(p_url, ''), '?', 1), '#', 1),
            E'／', '/'),
            E'．', '.'),
          '%c0%ae', '.', 'gi'),
        '%c0%af', '/', 'gi'),
      '%2e', '.', 'gi')
  );
$$;

-- ===========================================================================
-- BS/BM guard: notes rails + proof canonical + seguro label
-- ===========================================================================
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
       '(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple|google|mb\s*way|mbway|pix|multibanco)' then
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
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|seguro|pago no mb|transfer|cart[aã]o|multibanco)' then
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

-- ===========================================================================
-- BW — dispute proofs: unicode slash + overlong
-- ===========================================================================
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

-- ===========================================================================
-- BT — FOMO synonyms + paused item block + Mux cols authenticated
-- ===========================================================================
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

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|esgotado|vendido|sold|adquiriu|encomenda|c0mprou|snapped|snap up|claimed|grabbed|took it|its gone|it s gone|its mine|it s mine|mine now|reserved for|gone|acabou|out of stock|outofstock)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab)') then
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

-- paused/inactive item: block pending insert + accept
-- NOTA 2026-09-12: is_active = destaque vitrine, NÃO bloqueia venda
-- (ver 20260912193000_fix_is_active_highlight_not_sellable_batata.sql).
create or replace function public.batata_live_reservation_requests_guard_item_sellable()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_status text;
begin
  select lower(trim(coalesce(li.status, '')))
  into v_status
  from public.live_items li
  where li.id = NEW.live_item_id;
  if v_status is null then
    raise exception 'live_item_not_found' using errcode = '23514';
  end if;
  if v_status in ('paused', 'inactive', 'sold', 'reserved_full') then
    raise exception 'live_item_not_sellable' using errcode = '42501';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_item_sellable
  on public.live_reservation_requests;
create trigger trg_batata_live_reservation_item_sellable
  before insert or update of status, live_item_id on public.live_reservation_requests
  for each row
  when (NEW.status is distinct from 'cancelled' and NEW.status is distinct from 'rejected'
        and NEW.status is distinct from 'expired')
  execute function public.batata_live_reservation_requests_guard_item_sellable();

-- BT-P2-03: authenticated não lê VOD/asset Mux de lives alheias via REST
-- (seller studio: Hub views / Edge; playback público via hub_* views)
revoke select (mux_vod_playback_id, mux_asset_id, mux_stream_key, stream_key)
  on public.lives from authenticated;
-- manter mux_playback_id para dono via RLS (studio ao vivo); anon já revogado no BLBQ
revoke select (mux_playback_id) on public.lives from anon;

-- ===========================================================================
-- BU — discovery exige hub_published (alinhar à página Hub)
-- ===========================================================================
create or replace view public.hub_lives_discovery_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as seller_handle,
  nullif(trim(p.full_name), '') as seller_name,
  nullif(trim(p.photo_url), '') as seller_photo_url,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  case
    when lower(trim(coalesce(l.status, ''))) = 'live'
         and coalesce(l.is_active, false) = true
      then l.mux_playback_id
    else null
  end as mux_playback_id,
  case
    when lower(trim(coalesce(l.status, ''))) = 'ended'
      then l.mux_vod_playback_id
    else null
  end as mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
inner join public.profiles p
  on p.id = coalesce(l.seller_id, l.vendedor_id)
where coalesce(p.hub_published, false) = true
  and length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = true
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'scheduled'
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
    )
  );

grant select on public.hub_lives_discovery_public to anon, authenticated;

-- ===========================================================================
-- BR — claim atómico multi-order (FOR UPDATE em todos os ids do saco)
-- ===========================================================================
create or replace function public.batata_bag_checkout_claim(
  p_order_ids uuid[],
  p_claim_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  r record;
  v_sid text;
  v_any_cs text := null;
  v_any_other_claim boolean := false;
begin
  if p_order_ids is null or cardinality(p_order_ids) < 1
     or length(trim(coalesce(p_claim_token, ''))) < 12 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select array_agg(x order by x) into v_ids
  from (select distinct unnest(p_order_ids) as x) s
  where x is not null;

  if v_ids is null or cardinality(v_ids) < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  -- Lock all rows in id order (evita deadlock AB vs BC vs CA)
  for r in
    select id, stripe_checkout_session_id
    from public.orders
    where id = any(v_ids)
    order by id
    for update
  loop
    v_sid := nullif(trim(coalesce(r.stripe_checkout_session_id, '')), '');
    if v_sid is not null and v_sid like 'cs_%' then
      v_any_cs := v_sid;
    elsif v_sid is not null and v_sid like 'claiming:%'
          and v_sid is distinct from trim(p_claim_token) then
      v_any_other_claim := true;
    end if;
  end loop;

  if v_any_cs is not null then
    return jsonb_build_object(
      'ok', true, 'action', 'reuse', 'session_id', v_any_cs
    );
  end if;

  if v_any_other_claim then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

  update public.orders
  set stripe_checkout_session_id = trim(p_claim_token)
  where id = any(v_ids)
    and (
      stripe_checkout_session_id is null
      or nullif(trim(stripe_checkout_session_id), '') is null
      or stripe_checkout_session_id = trim(p_claim_token)
    );

  return jsonb_build_object(
    'ok', true, 'action', 'create', 'session_id', trim(p_claim_token)
  );
end;
$$;

revoke all on function public.batata_bag_checkout_claim(uuid[], text)
  from public, anon, authenticated;
grant execute on function public.batata_bag_checkout_claim(uuid[], text)
  to service_role;

notify pgrst, 'reload schema';

-- BU-P3: FOMO nao trata scheduled inactivo como publico
create or replace function public.batata_hub_live_fomo_snapshot(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_live public.hub_lives_public%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_row record;
  v_stock jsonb;
  v_pending int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select * into v_live
  from public.hub_lives_public hl
  where hl.id = p_live_id;

  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  if lower(trim(coalesce(v_live.status, ''))) = 'scheduled'
     and coalesce(v_live.is_active, false) is not true then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  if lower(trim(coalesce(v_live.status, ''))) = 'live'
     and coalesce(v_live.is_active, false) is not true then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  for v_row in
    select li.id as live_item_id, li.status as item_status
    from public.hub_live_items_public li
    where li.live_id = p_live_id
    order by li.is_active desc, li.created_at asc
  loop
    v_stock := public.batata_live_item_stock(v_row.live_item_id);

    select coalesce(count(*)::int, 0) into v_pending
    from public.live_reservation_requests r
    where r.live_item_id = v_row.live_item_id
      and r.status = 'pending'
      and r.source = 'fleaber_live';

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'live_item_id', v_row.live_item_id,
      'status', coalesce(v_row.item_status, 'unknown'),
      'available_qty', coalesce((v_stock->>'available_qty')::int, 0),
      'pending_queue_count', v_pending,
      'is_last_unit',
        coalesce((v_stock->>'total_qty')::int, 1) >= 2
        and coalesce((v_stock->>'available_qty')::int, 0) = 1,
      'display_reserved_qty',
        coalesce((v_stock->>'reserved_accepted_qty')::int, 0)
        + coalesce((v_stock->>'pending_bag_qty')::int, 0)
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live.id,
    'viewer_count', coalesce(v_live.viewer_count, 0),
    'live_status', v_live.status,
    'is_active', v_live.is_active,
    'items', v_items
  );
end;
$$;

revoke all on function public.batata_hub_live_fomo_snapshot(uuid) from public;
grant execute on function public.batata_hub_live_fomo_snapshot(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
