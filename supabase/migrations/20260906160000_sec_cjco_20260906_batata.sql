-- POS_CDCI CJ–CO fecho 2026-09-06
-- CONTAGEM: P0:0 P1:4 P2:7 P3:0 TOTAL:11
-- REGRESSÃO CDCI: chr(0) no regexp_replace → 54000 (CK/CO)
-- production_touched:false · fase4:false · BATATA

-- ===========================================================================
-- REGRESSÃO — canonical sem NUL no padrão regex
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
  -- Nunca usar chr(0): Postgres rejeita NUL mesmo como argumento de replace.
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
    v := regexp_replace(v, '%ef%bc%bc', '/', 'gi');
    v := regexp_replace(v, '%u002e', '.', 'gi');
    v := regexp_replace(v, '%u002f', '/', 'gi');
    v := regexp_replace(v, '%u005c', '/', 'gi');
    v := regexp_replace(v, '%u2215', '/', 'gi');
    v := regexp_replace(v, '%u2216', '/', 'gi');
    v := regexp_replace(v, '%00', '', 'gi');
    v := regexp_replace(v, '%25252e', '%252e', 'gi');
    v := regexp_replace(v, '%25252f', '%252f', 'gi');
    v := regexp_replace(v, '%25255c', '%255c', 'gi');
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
-- CJ — claim: sem overwrite de claiming alheio; futuro = órfão; verify hold
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
  v_skew_ms bigint := 60000;
  v_updated int := 0;
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
          -- futuro (além skew) ou passado além TTL → reclaim
          if v_ms > v_now_ms + v_skew_ms then
            v_expired := true;
          elsif v_now_ms - v_ms > v_ttl_ms then
            v_expired := true;
          end if;
        exception when others then
          v_expired := true;
        end;
      else
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

  -- NÃO sobrescrever claiming: alheio (CJ P1 overlap 4∥2)
  update public.orders
  set stripe_checkout_session_id = trim(p_claim_token)
  where id = any(v_ids)
    and (
      stripe_checkout_session_id is null
      or nullif(trim(stripe_checkout_session_id), '') is null
      or stripe_checkout_session_id = trim(p_claim_token)
    );
  get diagnostics v_updated = row_count;

  if v_updated < cardinality(v_ids) then
    -- overlap: outro conjunto já claimou parte
    for r in
      select stripe_checkout_session_id as sid
      from public.orders
      where id = any(v_ids)
        and stripe_checkout_session_id is not null
        and stripe_checkout_session_id is distinct from trim(p_claim_token)
    loop
      if trim(r.sid) like 'cs_%' then
        return jsonb_build_object(
          'ok', true, 'action', 'reuse', 'session_id', trim(r.sid)
        );
      end if;
    end loop;
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
    );
  end if;

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
-- CK — rails PaysafeCash / PicPay / gift / NFC / IT/DE + inbox
-- ===========================================================================
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_normalize_lie_text(p_text) ~*
      '(seguro fleaber|seguro|compra paga|mb[\s\-]*way|mbway|pix|p[ií]x|pic\s*pay|picpay|paysafe\s*cash|paysafecash|affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|venmo|payoneer|western\s*union|\mwu\M|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|crypto|coinbase|binance|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|pay\s*pa[li1ı]|paypal|bizum|iban|wise|revolut|rev0lut|apple\s*pay|apple\s*cash|google\s*pay|samsung\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|cash\s*tag|\$[a-z0-9]|m[\s\-]*pesa|swish|kakao\s*pay|kakaopay|line\s*pay|grabpay|blik|vipps|paynow|pay\s*id|payid|osko|dana|momo|touch\s*n\s*go|wallet|vanilla|gift\s*card|money\s*order|cashier|tap\s*to\s*cash|nfc|bonifico|uberweisung|überweisung|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb[\s\-]*way|mbway|pix|pic\s*pay|picpay|paysafe\s*cash|paysafecash|p[ií]x|affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|rev0lut|apple\s*pay|apple\s*cash|google\s*pay|samsung\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|\$[a-z0-9]|m[\s\-]*pesa|swish|kakao|line\s*pay|grabpay|blik|vipps|paynow|payid|osko|dana|momo|touch\s*n\s*go|wallet|vanilla|gift\s*card|money\s*order|tap\s*to\s*cash|nfc|bonifico|uberweisung|überweisung|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶|received|prova)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|apple\s*cash|samsung\s*pay|paypal|pay\s*pa[li1ı]|wise|revolut|rev0lut|mb[\s\-]*way|affirm|cash\s*app|clearpay|wechat|upi|unionpay|cashtag|picpay|paysafecash|bonifico|uberweisung|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|bitcoin|usdt|tether|paytm|mercado\s*pago|mercadopago|skrill|neteller|paysafecard|paysafe\s*cash|paysafecash|moneygram|gcash|perfect\s*money|enviado\s*mb|klarna|sofort|ideal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|venmo|sepa|mbnet|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|rev0lut|apple\s*pay|apple\s*cash|google\s*pay|samsung\s*pay|mb[\s\-]*way|mbway|pix|picpay|pic\s*pay|m[\s\-]*pesa|swish|kakaopay|grabpay|blik|vipps|paynow|payid|osko|dana|momo|wallet|vanilla|gift\s*card|tap\s*to\s*cash|bonifico|uberweisung)\M'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(enviado\s*mb|ja\s*transferi\s*mb|pago\s*por\s*transfer[eê]ncia|envia\s*para\s*esta\s*wallet|tap\s*to\s*cash)\M'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wechat|微信支付|支付宝|alipay|upi|unionpay|cashtag|\$[a-z]|m[\s\-]*pesa|swish|kakao|grabpay|blik|vipps|paynow|payid|osko|dana|momo|touch\s*n\s*go|wallet|mb[\s\-]*way|pay\s*pa[li1ı]|picpay|paysafecash|paysafe\s*cash|apple\s*cash|samsung\s*pay|vanilla|gift\s*card|bonifico|uberweisung|rev0lut)'
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|rev0lut|apple\s*pay|apple\s*cash|google\s*pay|samsung\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|wechat|upi|unionpay|cashtag|venmo|sepa|mbnet|paypal|pay\s*pa[li1ı]|bizum|mb[\s\-]*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|skrill|neteller|paysafecard|paysafecash|paysafe\s*cash|moneygram|gcash|perfect\s*money|enviado\s*mb|pix|picpay|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o|wallet|vanilla|gift|tap\s*to\s*cash|nfc|bonifico|uberweisung).{0,40}(confirmado|aprovado|processado|feito|caiu|received|€|eur|💶|\d|prova)'
$$;

-- refresh seguro label list (same rails)
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
       '(affirm|cash\s*app|cashapp|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|paysafecash|paysafe\s*cash|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|bitcoin|usdt|paytm|mercado\s*pago|mercadopago|klarna|sofort|ideal|twint|afterpay|alipay|支付宝|wechat|微信支付|unionpay|upi|cashtag|\$[a-z]|m[\s\-]*pesa|swish|kakao|grabpay|blik|vipps|paynow|payid|osko|dana|momo|wallet|vanilla|gift\s*card|tap\s*to\s*cash|nfc|bonifico|uberweisung|picpay|pic\s*pay|venmo|sepa|mbnet|pay\s*pa[li1ı]|paypal|bizum|wise|revolut|rev0lut|apple|google|samsung|mb[\s\-]*way|mbway|pix|multibanco|ja\s*transferi|transferi\s*mb|pago\s*por\s*transfer)' then
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
       '(wise|revolut|rev0lut|apple|google|samsung|klarna|sofort|ideal|twint|afterpay|alipay|wechat|upi|unionpay|cashtag|venmo|sepa|mbnet|paypal|pay\s*pa[li1ı]|bizum|mb[\s\-]*way|mbway|pix|picpay|paysafecash|paysafe\s*cash|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|skrill|neteller|paysafecard|moneygram|gcash|perfect\s*money|enviado\s*mb|payoneer|western\s*union|interac|btc|usdt|paytm|mercado\s*pago|seguro|pago no mb|transfer|cart[aã]o|multibanco|wallet|vanilla|gift|tap\s*to\s*cash|nfc|bonifico|uberweisung)' then
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
-- CL — FOMO IT/DE/FR
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
    E'áàâãäéèêëíìîïóòôõöúùûüç0оОаАсСſօოäöüß'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucooaassoaoouss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  v_norm := regexp_replace(v_norm, '[^a-z0-9€🛒✅\s]', '', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');
  v_compact := regexp_replace(v_norm, '\s+', '', 'g');

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|esgotado|esgotada|esgotados|vendido|vendida|sold|sold out|adquiriu|encomenda|c0mprou|snapped|snap up|claimed|claiming|grabbed|took it|its gone|it s gone|its mine|it s mine|that s mine|thats mine|mine now|mine|reserved for|reserved|reservado|gone|acabou|out of stock|outofstock|no more|taken|it s taken|its taken|last one|last 1|last piece|last available|1 left|only one left|ja nao ha|nao ha mais|ja nao existe|fora de stock|sem stock|stock 0|zero stock|unavailable|off sale|ja saiu|no quedan|ultima unidade|foi embora|ja tem dono|acaba de sair|agotado|se fue|ya tiene dueno|final piece|levado|going once|final call|quase a acabar|ultimo pezzo|esaurito|gia venduto|non ce piu|preso|letztes stuck|ausverkauft|schon weg|kein lager|verkauft|dernier article|epuise|plus de stock|deja pris|vendu|ultimo disponibile|nur noch einer)'
     or v_compact ~ '(lastone|last1|minenow|itsmine|foiembora|jatemdono|acabadesair|semstock|outofstock|nomore|soldout|claiming|agotado|sefue|yatiene|finalpiece|goingonce|reservado|levado|finalcall|quaseaacabar|ultimopezzo|esaurito|giavenduto|noncepiu|preso|letztesstuck|ausverkauft|schonweg|keinlager|verkauft|dernierarticle|epuise|plusdestock|dejapris|vendu|ultimodisponibile|nurnocheiner)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab|stock|taken|mine|last|reserved|dono|embora|esaur|ausver|epuis|pezzo)') then
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

-- ===========================================================================
-- CM — follows: alvo existe + hub_published; raffle só se published;
--       favorites: produto listável + hub_published
-- ===========================================================================
drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own
  on public.follows
  for insert
  to authenticated
  with check (
    follower_id = auth.uid()
    and following_id is distinct from auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = following_id
        and coalesce(p.hub_published, false) = true
    )
  );

create or replace function public.batata_live_raffle_on_follow_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle_id uuid;
  v_award jsonb;
  v_hub boolean := false;
begin
  if new.follower_id is null or new.following_id is null then
    return new;
  end if;
  if new.follower_id = new.following_id then
    return new;
  end if;

  select coalesce(p.hub_published, false) into v_hub
  from public.profiles p where p.id = new.following_id;
  if not coalesce(v_hub, false) then
    return new;
  end if;

  if exists (
    select 1
    from public.live_raffle_lifetime_grants g
    where g.user_id = new.follower_id
      and g.seller_id = new.following_id
      and g.grant_type = 'follow_seller'
  ) then
    return new;
  end if;

  select r.id into v_raffle_id
  from public.live_raffles r
  where r.seller_id = new.following_id
    and r.status = 'active'
  order by r.created_at desc, r.id desc
  limit 1;

  if v_raffle_id is null then
    return new;
  end if;

  v_award := public.batata_award_live_raffle_tickets(
    v_raffle_id,
    new.follower_id,
    'follow',
    1,
    'follow_lifetime:' || new.following_id::text
  );

  if coalesce(v_award->>'ok', 'false') <> 'true' then
    return new;
  end if;

  insert into public.live_raffle_lifetime_grants (
    user_id, seller_id, grant_type, first_raffle_id
  ) values (
    new.follower_id, new.following_id, 'follow_seller', v_raffle_id
  )
  on conflict (user_id, seller_id, grant_type) do nothing;

  perform public.batata_live_raffle_audit(
    v_raffle_id,
    'follow_lifetime_awarded',
    jsonb_build_object(
      'user_id', new.follower_id,
      'seller_id', new.following_id,
      'ticket_balance', v_award->'ticket_balance',
      'duplicate', coalesce(v_award->>'duplicate', 'false') = 'true'
    )
  );

  return new;
end;
$$;

drop policy if exists favorites_insert_own on public.favorites;
create policy favorites_insert_own
  on public.favorites
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.products pr
      join public.profiles p on p.id = pr.seller_id
      where pr.id = product_id
        and coalesce(p.hub_published, false) = true
        and coalesce(pr.list_on_marketplace, false) = true
        and coalesce(pr.is_sold, false) = false
        and coalesce(pr.quantity, 0) > 0
    )
  );

notify pgrst, 'reload schema';
