-- POS_BXCC CD–CI fecho 2026-09-06
-- CONTAGEM: P0:0 P1:50 (1 classe rails) P2:10 P3:0 TOTAL:60
-- production_touched:false · fase4:false · BATATA

-- ===========================================================================
-- CD-P2 — claiming: órfão com TTL / reclaim
-- Token: claiming:<epoch_ms>:<uuid> | legado claiming:* → reclaim imediato
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
  v_expired boolean;
  v_ms bigint;
  v_now_ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_ttl_ms bigint := 90000;
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
      v_expired := false;
      if v_sid ~ '^claiming:[0-9]{10,13}:' then
        begin
          v_ms := substring(v_sid from '^claiming:([0-9]{10,13}):')::bigint;
          if v_now_ms - v_ms > v_ttl_ms then
            v_expired := true;
          end if;
        exception when others then
          v_expired := true;
        end;
      else
        -- legado / órfão sem timestamp → reclaim (CD-P2 DoS)
        v_expired := true;
      end if;
      if v_expired then
        update public.orders
        set stripe_checkout_session_id = null
        where id = r.id
          and stripe_checkout_session_id = v_sid;
      else
        v_any_other_claim := true;
      end if;
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
      or stripe_checkout_session_id like 'claiming:%'
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

-- ===========================================================================
-- CE-P1 — rails + normalize (WeChat/UPI/… + hífen + homógrafos + NFKC)
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
      || chr(8201) || chr(8202) || chr(8287) || chr(8192) || chr(8193)
      || chr(8194) || chr(8195) || chr(8196) || chr(8197) || chr(8198)
      || chr(12288) || chr(10240) || chr(6016) || ']+',
    '',
    'g'
  );
$$;

create or replace function public.batata_chat_normalize_lie_text(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    regexp_replace(
      lower(
        translate(
          normalize(
            public.batata_chat_strip_format_controls(coalesce(p_text, '')),
            NFKC
          ),
          E'еЕаАоОрРсСхХуУіІΜМмВвΑαΡρΟοΕεΙιΚκΤτΥυΧχЅѕօՕოſſ'
            || E'ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ'
            || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ'
            || E'０１２３４５６７８９',
          E'eeaaooppssxxyyiiMmmVvAaPpOoEeIiKkTtYyXxSsOoOss'
            || E'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
            || E'abcdefghijklmnopqrstuvwxyz'
            || E'0123456789'
        )
      ),
      '[-_./|]+',
      ' ',
      'g'
    ),
    '\s+',
    ' ',
    'g'
  );
$$;

create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb[\s\-]*way|mbway|pix|p[ií]x|affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|venmo|payoneer|western\s*union|\mwu\M|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|crypto|coinbase|binance|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|pay\s*pa[li1ı]|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|cash\s*tag|\$[a-z0-9]|m[\s\-]*pesa|swish|kakao\s*pay|kakaopay|line\s*pay|grabpay|blik|vipps|paynow|pay\s*id|payid|osko|dana|momo|touch\s*n\s*go|wallet|multibanco|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb[\s\-]*way|mbway|pix|p[ií]x|affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|\$[a-z0-9]|m[\s\-]*pesa|swish|kakao|line\s*pay|grabpay|blik|vipps|paynow|payid|osko|dana|momo|touch\s*n\s*go|wallet|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶|received)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|pay\s*pa[li1ı]|wise|revolut|mb[\s\-]*way|affirm|cash\s*app|clearpay|wechat|upi|unionpay|cashtag|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|klarna|sofort|ideal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|venmo|sepa|mbnet|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|mb[\s\-]*way|mbway|pix|m[\s\-]*pesa|swish|kakaopay|grabpay|blik|vipps|paynow|payid|osko|dana|momo|wallet)\M'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(enviado\s*mb|ja\s*transferi\s*mb|pago\s*por\s*transfer[eê]ncia|envia\s*para\s*esta\s*wallet)\M'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wechat|微信支付|支付宝|alipay|upi|unionpay|cashtag|\$[a-z]|m[\s\-]*pesa|swish|kakao|grabpay|blik|vipps|paynow|payid|osko|dana|momo|touch\s*n\s*go|wallet|mb[\s\-]*way|pay\s*pa[li1ı])'
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|wechat|upi|unionpay|cashtag|venmo|sepa|mbnet|paypal|pay\s*pa[li1ı]|bizum|mb[\s\-]*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|pix|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o|wallet).{0,40}(confirmado|aprovado|processado|feito|caiu|received|€|eur|💶|\d)'
$$;

-- refresh notes-only rail list inside guard (redefine full guard from BXCC + CE rails)
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
       '(affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|klarna|sofort|ideal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|\$[a-z]|m[\s\-]*pesa|swish|kakao|grabpay|blik|vipps|paynow|payid|osko|dana|momo|wallet|venmo|sepa|mbnet|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|apple|google|mb[\s\-]*way|mbway|pix|multibanco|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer)' then
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
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|wechat|upi|unionpay|cashtag|venmo|sepa|mbnet|paypal|pay\s*pa[li1ı]|bizum|mb[\s\-]*way|mbway|pix|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|seguro|pago no mb|transfer|cart[aã]o|multibanco|wallet)' then
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
-- CE/CI — canonical URL multi-pass (triple-encode, %u, UTF-8 slash, ZWSP, …)
-- ===========================================================================
create or replace function public.batata_storage_url_path_canonical(p_url text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_url, '');
  i int;
  prev text;
begin
  v := split_part(split_part(v, '?', 1), '#', 1);
  -- Nunca chr(0): Postgres 54000 mesmo em classe regex / replace.
  v := replace(v, chr(9), '');
  v := replace(v, chr(10), '');
  v := replace(v, chr(13), '');
  v := regexp_replace(v,
    '[' || chr(8206) || chr(8207) || chr(8234) || chr(8235) || chr(8236)
      || chr(8237) || chr(8238) || chr(8294) || chr(8295) || chr(8296)
      || chr(8297) || chr(8203) || chr(8204) || chr(8205) || chr(173)
      || ']+',
    '', 'g');
  for i in 1..10 loop
    prev := v;
    v := replace(v, E'／', '/');
    v := replace(v, E'＼', '/');
    v := replace(v, E'∕', '/');
    v := replace(v, E'⁄', '/');
    v := replace(v, E'⧸', '/');
    v := replace(v, E'∖', '/');
    v := replace(v, E'．', '.');
    v := replace(v, E'․', '.');
    v := replace(v, E'‥', '..');
    v := replace(v, chr(92), '/');
    v := replace(v, E'％', '%');
    v := regexp_replace(v, '%c0%ae', '.', 'gi');
    v := regexp_replace(v, '%c0%af', '/', 'gi');
    v := regexp_replace(v, '%c1%9c', '/', 'gi');
    v := regexp_replace(v, '%e0%80%ae', '.', 'gi');
    v := regexp_replace(v, '%e0%80%af', '/', 'gi');
    v := regexp_replace(v, '%f0%80%80%ae', '.', 'gi');
    v := regexp_replace(v, '%f0%80%80%af', '/', 'gi');
    v := regexp_replace(v, '%e2%88%95', '/', 'gi');
    v := regexp_replace(v, '%e2%a7%b8', '/', 'gi');
    v := regexp_replace(v, '%e2%81%84', '/', 'gi');
    v := regexp_replace(v, '%ef%bc%8f', '/', 'gi');
    v := regexp_replace(v, '%u002e', '.', 'gi');
    v := regexp_replace(v, '%u2215', '/', 'gi');
    v := regexp_replace(v, '%u2216', '/', 'gi');
    v := regexp_replace(v, '%00', '', 'gi');
    v := regexp_replace(v, '%25252e', '%252e', 'gi');
    v := regexp_replace(v, '%25252f', '%252f', 'gi');
    v := regexp_replace(v, '%252e', '.', 'gi');
    v := regexp_replace(v, '%252f', '/', 'gi');
    v := regexp_replace(v, '%255c', '/', 'gi');
    v := regexp_replace(v, '%25%2e', '.', 'gi');
    v := regexp_replace(v, '%25%2f', '/', 'gi');
    v := regexp_replace(v, '%2e', '.', 'gi');
    v := regexp_replace(v, '%2f', '/', 'gi');
    v := regexp_replace(v, '%5c', '/', 'gi');
    exit when v is not distinct from prev;
  end loop;
  return lower(v);
end;
$$;

-- ===========================================================================
-- CF-P2 — FOMO compact + sinonímia + sender_label chat
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
  v_compact text;
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

  v_norm := lower(normalize(v_body, NFKC));
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff\u2800-\u28ff\u00ad]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüç0оОаАсСſօო'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucooaassoo'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  v_norm := regexp_replace(v_norm, '[^a-z0-9€🛒✅\s]', '', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');
  v_compact := regexp_replace(v_norm, '\s+', '', 'g');

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|esgotado|esgotada|esgotados|vendido|vendida|sold|sold out|adquiriu|encomenda|c0mprou|snapped|snap up|claimed|claiming|grabbed|took it|its gone|it s gone|its mine|it s mine|that s mine|thats mine|mine now|mine|reserved for|reserved|reservado|gone|acabou|out of stock|outofstock|no more|taken|it s taken|its taken|last one|last 1|last piece|last available|1 left|only one left|ja nao ha|nao ha mais|ja nao existe|fora de stock|sem stock|stock 0|zero stock|unavailable|off sale|ja saiu|no quedan|ultima unidade|foi embora|ja tem dono|acaba de sair|agotado|se fue|ya tiene dueno|final piece|levado|going once)'
     or v_compact ~ '(lastone|last1|minenow|itsmine|foiembora|jatemdono|acabadesair|semstock|outofstock|nomore|soldout|claiming|agotado|sefue|yatiene|finalpiece|goingonce|reservado|levado)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab|stock|taken|mine|last|reserved|dono|embora)') then
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

create or replace function public.batata_live_messages_guard_sender_label()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label text := lower(trim(coalesce(NEW.sender_label, '')));
begin
  if lower(trim(coalesce(NEW.kind, ''))) = 'system' then
    return NEW;
  end if;
  if v_label in (
    'sistema', 'system', 'staff', 'admin', 'fleaber', 'moderador',
    'moderator', 'official', 'oficial', 'bot'
  ) then
    NEW.sender_label := null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_batata_live_messages_guard_sender_label on public.live_messages;
create trigger trg_batata_live_messages_guard_sender_label
  before insert or update of sender_label, kind
  on public.live_messages
  for each row
  execute function public.batata_live_messages_guard_sender_label();

-- ===========================================================================
-- CG — playback_id / livekit revoke; lives hub_published; products; resolve; stock
-- ===========================================================================
revoke select (playback_id, livekit_room_name)
  on public.lives from authenticated;
revoke select (playback_id, livekit_room_name)
  on public.lives from anon;

drop policy if exists "lives_select_feed_or_owner" on public.lives;
create policy "lives_select_feed_or_owner"
  on public.lives
  for select
  to anon, authenticated
  using (
    auth.uid() = seller_id
    or auth.uid() = vendedor_id
    or (
      lower(trim(coalesce(status, ''))) = 'live'
      and coalesce(is_active, false) = true
      and exists (
        select 1 from public.profiles p
        where p.id = coalesce(seller_id, vendedor_id)
          and coalesce(p.hub_published, false) = true
      )
    )
    or (
      lower(trim(coalesce(status, ''))) = 'ended'
      and exists (
        select 1 from public.profiles p
        where p.id = coalesce(seller_id, vendedor_id)
          and coalesce(p.hub_published, false) = true
      )
    )
    or (
      lower(trim(coalesce(status, ''))) = 'scheduled'
      and auth.uid() = coalesce(seller_id, vendedor_id)
    )
  );

drop policy if exists "products_select_marketplace_or_own" on public.products;
create policy "products_select_marketplace_or_own"
  on public.products
  for select
  to authenticated
  using (
    (
      list_on_marketplace = true
      and coalesce(is_sold, false) = false
      and coalesce(quantity, 0) > 0
      and exists (
        select 1 from public.profiles p
        where p.id = products.seller_id
          and coalesce(p.hub_published, false) = true
      )
    )
    or seller_id = auth.uid()
    or exists (
      select 1
      from public.orders o
      where o.product_id = products.id
        and o.buyer_id = auth.uid()
        and lower(trim(coalesce(o.status, ''))) not in (
          'cancelado', 'cancelled', 'canceled',
          'expirado', 'expired'
        )
    )
  );

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
    select p.id, p.handle, p.hub_published
    into v_profile_id, v_handle, v_published
    from public.profiles p
    where p.handle = v_redirect
    limit 1;
    if v_profile_id is not null and coalesce(v_published, false) then
      return jsonb_build_object(
        'found', true,
        'profile_id', v_profile_id,
        'handle', v_handle,
        'redirect_to', v_redirect,
        'hub_published', true,
        'http_status', 301
      );
    end if;
    return jsonb_build_object('found', false, 'error', 'not_found', 'http_status', 404);
  end if;

  return jsonb_build_object('found', false, 'error', 'not_found', 'http_status', 404);
end;
$$;

grant execute on function public.batata_resolve_handle(text) to anon, authenticated, service_role;

-- stock RPC: BLBQ body + gate hub_published para não-staff (CG)
create or replace function public.batata_live_item_stock(p_live_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_total integer;
  v_blocked integer := 0;
  v_blocked_orders integer := 0;
  v_blocked_cross_res integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_unit_price numeric;
  v_live_only boolean := false;
  v_uid uuid := auth.uid();
  v_staff boolean := false;
  v_lineage uuid;
  v_hub boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  v_lineage := coalesce(v_li.logical_item_id, v_li.id);

  if v_uid is not null and v_seller is not null then
    v_staff := public.batata_staff_has_permission(v_seller, 'can_manage_chat')
      or v_uid = v_seller;
  end if;

  select coalesce(p.hub_published, false) into v_hub
  from public.profiles p where p.id = v_seller;

  if not coalesce(v_staff, false) then
    if not coalesce(v_hub, false) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    if not public.batata_live_is_broadcasting(v_li.live_id)
       or lower(trim(coalesce(v_li.status, ''))) in (
         'paused', 'inactive', 'sold', 'reserved_full'
       ) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    if lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only'
       and coalesce(v_li.quantity, 0) <= 0 then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
  end if;

  v_live_only := lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only';
  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'pendente',
        'pedido_devolucao', 'em_devolucao'
      );

    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and lower(trim(li2.ref_code)) = lower(trim(v_li.ref_code))
      and coalesce(l2.seller_id, l2.vendedor_id) = v_seller;
  end if;

  if v_live_only and v_lineage is not null then
    select coalesce(v_blocked_cross_res, 0) + coalesce(sum(r.requested_qty), 0)::int
    into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.logical_item_id, li2.id) = v_lineage;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
        and (
          o.live_item_id = v_li.id
          or (
            o.live_id = v_li.live_id
            and v_product_id is not null
            and o.product_id = v_product_id
          )
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live'
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where (
      public.batata_order_status_is_sold_fulfilled(o.status)
      or coalesce(o.stock_units_applied, 0) > 0
    )
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;
  if v_available < 0 then v_available := 0; end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p where p.id = v_li.product_id;
  else
    v_unit_price := v_li.price;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'live_id', v_li.live_id,
    'item_kind', v_li.item_kind,
    'product_id', v_li.product_id,
    'checkout_product_id', v_li.checkout_product_id,
    'ref_code', v_li.ref_code,
    'total_qty', v_total,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved_accepted,
    'pending_bag_qty', v_pending_bag,
    'sold_converted_qty', v_sold_converted,
    'available_qty', v_available,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
