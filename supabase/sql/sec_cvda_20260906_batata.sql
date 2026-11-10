-- POS_CPCU CV–DA fecho 2026-09-06
-- CONTAGEM: P0:0 P1:2 P2:4 P3:0 TOTAL:6
-- CW+CZ saturados 0. DA = REGRESSÃO // em https://
-- production_touched:false · fase4:false · BATATA

-- ===========================================================================
-- DA REGRESSÃO — // só no path (não no scheme https://)
-- ===========================================================================
create or replace function public.batata_dispute_proof_url_ok(
  p_url text,
  p_buyer uuid,
  p_oid uuid
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_url text := public.batata_storage_url_path_canonical(coalesce(p_url, ''));
  v_after_host text;
  v_needle text;
begin
  if v_url = '' then
    return true;
  end if;
  if p_buyer is null or p_oid is null then
    return false;
  end if;
  -- Path-only: ignora o // do scheme https://
  v_after_host := regexp_replace(v_url, '^https://[^/?#]+', '');
  if position('//' in v_after_host) > 0 then
    return false;
  end if;
  if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%..%'
     or position('%2e%2e' in v_url) > 0
     or v_url like '%/object/public/%' then
    return false;
  end if;
  if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
    return false;
  end if;
  if v_url not like '%/object/sign/fleaber_private/%'
     and v_url not like '%/object/authenticated/fleaber_private/%' then
    return false;
  end if;
  v_needle := 'fleaber_private/order_disputes/' || p_buyer::text || '/' || p_oid::text || '/';
  if v_url !~ (v_needle || '[^/]+$') then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function public.batata_dispute_proof_url_ok(text, uuid, uuid) from public, anon;
grant execute on function public.batata_dispute_proof_url_ok(text, uuid, uuid)
  to authenticated, service_role;

create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_arr jsonb;
  v_buyer uuid;
  v_oid uuid := NEW.order_id;
  v_after_host text;
begin
  select buyer_id into v_buyer from public.orders where id = v_oid;

  if NEW.proof_photos is not null then
    begin
      v_arr := to_jsonb(NEW.proof_photos);
    exception when others then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end;
    if jsonb_typeof(v_arr) = 'array' then
      for v_url in
        select coalesce(elem, '')
        from jsonb_array_elements_text(v_arr) as t(elem)
      loop
        if not public.batata_dispute_proof_url_ok(v_url, v_buyer, v_oid) then
          raise exception 'dispute_proof_url_denied' using errcode = '23514';
        end if;
      end loop;
    end if;
  end if;

  if NEW.return_label_url is not null
     and nullif(trim(NEW.return_label_url), '') is not null then
    v_url := public.batata_storage_url_path_canonical(NEW.return_label_url);
    v_after_host := regexp_replace(v_url, '^https://[^/?#]+', '');
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url like '%/object/public/%'
       or v_url like '%..%' or position('//' in v_after_host) > 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
    if v_buyer is null or v_oid is null
       or position(
            'order_disputes/' || v_buyer::text || '/' || v_oid::text || '/'
            in v_url
          ) = 0 then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- CY — follows/favorites: hub_published via SECURITY DEFINER (buyer não vê profiles)
-- ===========================================================================
create or replace function public.batata_profile_is_hub_published(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.hub_published from public.profiles p where p.id = p_id),
    false
  );
$$;

create or replace function public.batata_product_is_favorite_allowed(p_product_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.products pr
    join public.profiles p on p.id = pr.seller_id
    where pr.id = p_product_id
      and coalesce(p.hub_published, false) = true
      and coalesce(pr.list_on_marketplace, false) = true
      and coalesce(pr.is_sold, false) = false
      and coalesce(pr.quantity, 0) > 0
  );
$$;

revoke all on function public.batata_profile_is_hub_published(uuid) from public, anon;
grant execute on function public.batata_profile_is_hub_published(uuid)
  to authenticated, service_role;
revoke all on function public.batata_product_is_favorite_allowed(uuid) from public, anon;
grant execute on function public.batata_product_is_favorite_allowed(uuid)
  to authenticated, service_role;

drop policy if exists follows_insert_own on public.follows;
create policy follows_insert_own
  on public.follows
  for insert
  to authenticated
  with check (
    follower_id = auth.uid()
    and following_id is distinct from auth.uid()
    and public.batata_profile_is_hub_published(following_id)
  );

drop policy if exists favorites_insert_own on public.favorites;
create policy favorites_insert_own
  on public.favorites
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.batata_product_is_favorite_allowed(product_id)
  );

-- ===========================================================================
-- CV — off-platform: fold grego/small-caps/NFD/tags + compact
-- ===========================================================================
create or replace function public.batata_normalize_payment_method(p_method text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_method, '');
begin
  v := lower(normalize(v, NFKC));
  -- NFD leftovers / combining marks
  v := normalize(v, NFD);
  v := regexp_replace(v, E'[\u0300-\u036f]', '', 'g');
  v := lower(normalize(v, NFC));
  -- Format / tags / invisíveis
  v := regexp_replace(v,
    E'[\u200b\u200c\u200d\ufeff\u00ad\u2800-\u28ff\u2060\u3164\u202a-\u202e\ue000-\uf8ff]',
    '', 'g');
  v := regexp_replace(v, E'[\u0009\u000a\u000d\u00a0\u2028\u2029]+', ' ', 'g');
  -- Homoglyphs: cirílico + grego μ + small-caps fonéticos
  v := translate(v,
    E'аеорсухіїАЕОРСУХІЇмМԝԜμΜᴀʙᴄᴅᴇғɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢ',
    E'aeopcyxiiAEOPCYXIImmwwmmabcdefghijklmnopqrstuvwxyz');
  v := replace(v, E'㎆', 'mb');
  v := regexp_replace(v, '\s+', ' ', 'g');
  return trim(v);
end;
$$;

create or replace function public.batata_payment_method_compact(p_method text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    public.batata_normalize_payment_method(p_method),
    '[^a-z0-9]',
    '',
    'g'
  );
$$;

create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_normalize_payment_method(p_method) in (
      'mb way', 'mb_way', 'mb-way', 'mbway',
      'transferencia', 'transferência', 'transfer', 'transf',
      'pagamento directo', 'pagamento direto',
      'pagamento_directo', 'pagamento_direto',
      'directo', 'direto',
      'entrega em mao', 'entrega em mão', 'em mao', 'em mão',
      'levantamento', 'combinado', 'combinada',
      'pagamento direto ao vendedor (mb way/transf)',
      'pagamento directo ao vendedor (mb way/transf)'
    )
    or public.batata_payment_method_compact(p_method) in (
      'mbway',
      'transferencia', 'transfer', 'transf',
      'pagamentodirecto', 'pagamentodireto',
      'directo', 'direto',
      'entregaemmao', 'emmao',
      'levantamento', 'combinado', 'combinada',
      'pagamentodiretoaovendedormbwaytransf',
      'pagamentodirectoaovendedormbwaytransf'
    );
$$;

-- ===========================================================================
-- CV — bag claim: advisory lock por buyer (anti 4∥2 dual Session)
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
  v_buyer uuid;
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

  select buyer_id into v_buyer
  from public.orders
  where id = v_ids[1];

  -- Serializa checkouts do mesmo comprador (4∥2 / 3∥1)
  if v_buyer is not null then
    perform pg_advisory_xact_lock(
      ('x' || substr(md5('batata_bag_claim:' || v_buyer::text), 1, 16))::bit(64)::bigint
    );
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
          if v_ms > v_now_ms + v_skew_ms then
            v_expired := true;
          elsif v_now_ms - v_ms > v_ttl_ms then
            v_expired := true;
          else
            v_any_other_claim := true;
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
    );
  get diagnostics v_updated = row_count;

  if v_updated < cardinality(v_ids) then
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
    'ok', true, 'action', 'create', 'session_id', null
  );
end;
$$;

revoke all on function public.batata_bag_checkout_claim(uuid[], text) from public, anon;
grant execute on function public.batata_bag_checkout_claim(uuid[], text)
  to service_role;

-- ===========================================================================
-- CX — FOMO: strip noise antes de stem; 🔥 sempre; stems novos
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
  v_stem text;
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
  v_norm := regexp_replace(v_norm, E'[\u200b\u200c\u200d\ufeff\u2800-\u28ff\u00ad\u2060]', '', 'g');
  -- Tirar dígitos ANTES do fold 0→o (anti es0aurito → esoaurito)
  v_norm := regexp_replace(v_norm, '[0-9]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüçоОаАсСſօოäöüß'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucoaassoaoouss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  -- Remover ✅ e resto do stem
  v_stem := regexp_replace(v_norm, '[^a-z€🛒\s]', '', 'g');
  v_stem := regexp_replace(v_stem, '\s+', '', 'g');
  v_norm := regexp_replace(v_norm, '[^a-z€🛒✅\s]', '', 'g');
  v_norm := regexp_replace(v_norm, '\s+', ' ', 'g');
  v_compact := regexp_replace(v_norm, '\s+', '', 'g');

  if v_body like '%🔥%'
     or v_stem ~
     '(compr|bought|purchas|levou|levar|esgot|esaur|vend|sold|snap|grab|claim|gone|mine|reserv|stock|taken|last|left|piece|pezzo|stuck|ausver|verkauf|epuis|agot|dueno|embora|dono|acab|final|call|going|encom|unit|disponib|einer|lager|pris|preso|saurit|nouvenc|nomore|outof|semstock|jatem|foiembora|ultim|nurnoch|plusde|dejapris|giaven|nonce|schonweg|keinla|jafoi|quedapoco|uitverkocht|ostatni|numaie|ficpouco|correutudo|pouco|verkocht|scarce|hurry|rapido|sumiu|sobra|selling|bijna|wyprzed|restam|fast|nada)'
     or v_compact ~
     '(compr|bought|purchas|levou|levar|esgot|esaur|vend|sold|snap|grab|claim|gone|mine|reserv|stock|taken|last|left|piece|pezzo|stuck|ausver|verkauf|epuis|agot|dueno|embora|dono|acab|final|call|going|encom|unit|disponib|einer|lager|pris|preso|saurit|nouvenc|nomore|outof|semstock|jatem|foiembora|ultim|nurnoch|plusde|dejapris|giaven|nonce|schonweg|keinla|jafoi|quedapoco|uitverkocht|ostatni|numaie|ficpouco|correutudo|pouco|verkocht|scarce|hurry|rapido|sumiu|sobra|selling|bijna|wyprzed|restam|fast)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_stem ~
         '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab|stock|taken|mine|last|reserv|dono|embora|esaur|ausver|epuis|pezzo)')
     or (v_stem ~ '\d' and v_stem ~ '(left|piece|pezzo|unit|stock|stuck|disponib|pouco|last|ultim|restam|sobra)') then
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
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
