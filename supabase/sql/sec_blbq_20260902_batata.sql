-- POS_BFBK BL–BQ fecho 2026-09-02 (5 reports; BL em falta no disco)
-- production_touched: false · fase4: false · BATATA

-- ===========================================================================
-- BO — lives SELECT: só broadcasting / ended+hub / scheduled; sem OR is_active solto
-- ===========================================================================
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
    )
    or (
      lower(trim(coalesce(status, ''))) = 'ended'
      and exists (
        select 1 from public.profiles p
        where p.id = coalesce(seller_id, vendedor_id)
          and coalesce(p.hub_published, false) = true
      )
    )
    or lower(trim(coalesce(status, ''))) = 'scheduled'
  );

-- Anon não lê colunas Mux (CDN bypass); authenticated mantém (studio vendedor)
revoke select (mux_playback_id, mux_vod_playback_id, mux_asset_id, mux_stream_key)
  on public.lives from anon;

-- hub_lives_public: live exige is_active
create or replace view public.hub_lives_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  hp.handle as seller_handle,
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
join public.hub_profiles_public hp
  on hp.id = coalesce(l.seller_id, l.vendedor_id)
where (
    lower(trim(coalesce(l.status, ''))) = 'scheduled'
  )
  or (
    lower(trim(coalesce(l.status, ''))) = 'live'
    and coalesce(l.is_active, false) = true
  )
  or (
    lower(trim(coalesce(l.status, ''))) = 'ended'
  );

grant select on public.hub_lives_public to anon, authenticated, service_role;

-- hub items: sem RPC broadcasting (anon 401); inline live+active; marketplace qty NULL OK
create or replace view public.hub_live_items_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_public hl on hl.id = li.live_id
where coalesce(li.is_active, false) = true
  and lower(trim(coalesce(hl.status, ''))) = 'live'
  and coalesce(hl.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

grant select on public.hub_live_items_public to anon, authenticated;

create or replace view public.hub_live_items_discovery_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_discovery_public hl on hl.id = li.live_id
where coalesce(li.is_active, false) = true
  and lower(trim(coalesce(hl.status, ''))) = 'live'
  and coalesce(hl.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

grant select on public.hub_live_items_discovery_public to anon, authenticated;

-- ===========================================================================
-- BM — normalize + rails Clearpay/Shop Pay/Strike/… + proof path canónico
-- ===========================================================================
create or replace function public.batata_chat_normalize_lie_text(p_text text)
returns text
language sql
immutable
as $$
  select lower(
    translate(
      -- NFKC via regexp strip fullwidth range approx: convert common fullwidth A-Z a-z 0-9
      convert_from(
        convert_to(
          public.batata_chat_strip_format_controls(coalesce(p_text, '')),
          'UTF8'
        ),
        'UTF8'
      ),
      -- cirílico + grego lookalike + NBSP + fullwidth digits/letters common
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
      '(seguro fleaber|seguro|compra paga|mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|venmo|transfer[eê]ncia|pagamento|reembolso|refund|estorno|devolu[cç][aã]o|remboursement|chargeback|paypal|bizum|iban|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|sepa|mbnet|cart[aã]o|recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|eur|euros?|💶)|€\s*\d+|\d+\s*€|\d+\s*eur|💶)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(mb\s*way|mbway|pix|p[ií]x|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|i\s*deal|twint|afterpay|alipay|multibanco|venmo|sepa|mbnet|reembolso|refund|estorno|cart[aã]o).*(\d|confirmado|banco|recebido|aprovado|processado|feito|caiu|pago|€|eur|💶|received)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(\d+[,.]?\d*\s*(€|eur|💶)|€\s*\d+|💶).{0,40}(klarna|sofort|ideal|twint|afterpay|alipay|google\s*pay|apple\s*pay|paypal|wise|revolut|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|confirmado|aprovado|pago)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(refund|estorno|remboursement|chargeback|devolu[cç][aã]o|reembolso).*\d'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple\s*pay|google\s*pay|mb\s*way|mbway|pix)\M';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text)
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '(wise|revolut|apple\s*pay|google\s*pay|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|pix|reembolso|refund|estorno|pagamento|transfer|recebi|cart[aã]o).{0,40}(confirmado|aprovado|processado|feito|caiu|received|€|eur|💶|\d)'
    or public.batata_chat_normalize_lie_text(p_text) ~*
      '\m(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|klarna|sofort|ideal|twint|afterpay|pix|paypal)\M';
$$;

-- proof_url: path canónico, sem ..
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
    v_url := lower(trim(coalesce(v_json->>'url', '')));
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
    -- BM7-P3: sem chaves soltas (meta/rail) no card de sistema
    if v_json ? 'meta' or v_json ? 'rail' or v_json ? 'status' then
      raise exception 'chat_system_card_payload_forbidden' using errcode = '23514';
    end if;
    v_notes := coalesce(v_json->>'notes', '');
    if v_notes ~ '[<>]' or public.batata_chat_payment_lie_text(v_notes) then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    if public.batata_chat_normalize_lie_text(v_notes) ~*
       '(affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|wise|revolut|apple|google|mb\s*way|mbway|pix|multibanco)' then
      raise exception 'chat_system_card_notes_forbidden' using errcode = '23514';
    end if;
    begin
      v_order := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
    exception when others then
      v_order := null;
    end;
    v_url := lower(trim(coalesce(v_json->>'proof_url', '')));
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
      v_path := split_part(split_part(v_url, '?', 1), '#', 1);
      -- canónico: …/fleaber_private/order_proofs/{buyer}/{order}/…
      v_prefix := 'fleaber_private/order_proofs/' || coalesce(v_buyer::text, '')
        || '/' || v_order::text || '/';
      if v_buyer is null
         or position(v_prefix in v_path) = 0
         or v_path not like '%/' || v_prefix || '%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      -- rejeitar prefixo extra antes de order_proofs (other/.../order_proofs)
      if v_path !~ ('fleaber_private/order_proofs/' || v_buyer::text || '/' || v_order::text || '/') then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if position('/order_proofs/' in v_path) <>
         position(('/order_proofs/' || v_buyer::text || '/' || v_order::text || '/') in v_path) then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if public.batata_chat_normalize_lie_text(v_label) ~*
       '(wise|revolut|apple|google|klarna|sofort|ideal|twint|afterpay|alipay|venmo|sepa|mbnet|paypal|bizum|mb\s*way|mbway|pix|affirm|cash\s*app|clearpay|shop\s*pay|strike|sezzle|bancontact|zelle|seguro|pago no mb|transfer|cart[aã]o|multibanco)' then
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
-- BQ — replies proof: path-only + host storage + sem ..
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
    select lower(trim(coalesce(elem, '')))
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
    v_path := split_part(split_part(v_url, '?', 1), '#', 1);
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

-- Dispute proof_photos: reject ..
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
        select lower(trim(coalesce(elem, '')))
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
        v_path := split_part(split_part(v_url, '?', 1), '#', 1);
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
    v_url := lower(trim(NEW.return_label_url));
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%/object/public/%'
       or v_url like '%..%' then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
    v_path := split_part(split_part(v_url, '?', 1), '#', 1);
    if v_needle is null or position(v_needle in v_path) = 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- BN — FOMO alargado + accept_broadcast só seller/staff + logical_item cross
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
  -- colapsar espaços mas manter letras juntas (não partir fullwidth já traduzido)
  v_norm := regexp_replace(v_norm, '[^a-z0-9€🛒✅\s]', '', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');

  if v_norm ~ '(comprou|compraram|purchased|bought|levou|levaram|esgotou|vendido|sold|adquiriu|encomenda|c0mprou|snapped|snap up|claimed|grabbed|took it|its gone|it s gone|mine now|reserved for)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_norm ~ '(compr|levou|sold|vend|esgot|claim|snap|grab)') then
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
  if p_live_id is null or p_buyer_id is null or p_live_item_id is null then
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
      and r.buyer_id = p_buyer_id
      and r.live_item_id = p_live_item_id
      and r.status = 'accepted'
  ) into v_has_accept;
  if not coalesce(v_has_accept, false) then
    return false;
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Comprador') into v_name
  from public.profiles where id = p_buyer_id;

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
  values (p_live_id, coalesce(v_uid, p_buyer_id), 'system', v_body, 'Sistema');
  return true;
end;
$$;

revoke all on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer) from public;
grant execute on function public.batata_live_reservation_accept_broadcast(uuid, uuid, uuid, integer)
  to authenticated, service_role;

-- Stock: cross-hold por logical_item_id (BN-P1)
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

  if not coalesce(v_staff, false) then
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

  -- BN-P1: mesma linhagem logical_item_id (refs distintas)
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

-- BO-P3: resolve unpublished só se há live descoberta (scheduled / live+active / ended)
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
  v_has_live boolean := false;
begin
  if v_in = '' then
    return jsonb_build_object(
      'found', false, 'error', 'not_found', 'http_status', 404
    );
  end if;

  select p.id, p.handle, p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where p.handle = v_in
  limit 1;

  if v_profile_id is not null and v_published is true then
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
    select exists (
      select 1 from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = v_profile_id
        and (
          lower(trim(coalesce(l.status, ''))) = 'scheduled'
          or (
            lower(trim(coalesce(l.status, ''))) = 'live'
            and coalesce(l.is_active, false) = true
          )
          or lower(trim(coalesce(l.status, ''))) = 'ended'
        )
    ) into v_has_live;
    if coalesce(v_has_live, false) then
      return jsonb_build_object(
        'found', true,
        'profile_id', v_profile_id,
        'handle', v_handle,
        'hub_published', false,
        'redirect_to', null,
        'http_status', 200
      );
    end if;
    return jsonb_build_object(
      'found', false, 'error', 'not_found', 'http_status', 404
    );
  end if;

  select
    p.id,
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name),
    p.hub_published
  into v_profile_id, v_handle, v_published
  from public.profiles p
  where public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name) = v_in
  limit 1;

  if v_profile_id is not null then
    if coalesce(v_published, false) then
      return jsonb_build_object(
        'found', true,
        'profile_id', v_profile_id,
        'handle', v_handle,
        'hub_published', true,
        'redirect_to', null,
        'http_status', 200
      );
    end if;
    select exists (
      select 1 from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = v_profile_id
        and (
          lower(trim(coalesce(l.status, ''))) = 'scheduled'
          or (
            lower(trim(coalesce(l.status, ''))) = 'live'
            and coalesce(l.is_active, false) = true
          )
          or lower(trim(coalesce(l.status, ''))) = 'ended'
        )
    ) into v_has_live;
    if coalesce(v_has_live, false) then
      return jsonb_build_object(
        'found', true,
        'profile_id', v_profile_id,
        'handle', v_handle,
        'hub_published', false,
        'redirect_to', null,
        'http_status', 200
      );
    end if;
    return jsonb_build_object(
      'found', false, 'error', 'not_found', 'http_status', 404
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
      'profile_id', (
        select p.id from public.profiles p where p.handle = v_redirect limit 1
      ),
      'handle', v_redirect,
      'redirect_to', v_redirect,
      'hub_published', (
        select p.hub_published from public.profiles p where p.handle = v_redirect limit 1
      ),
      'http_status', 301
    );
  end if;

  return jsonb_build_object(
    'found', false, 'error', 'not_found', 'http_status', 404
  );
end;
$$;

notify pgrst, 'reload schema';
