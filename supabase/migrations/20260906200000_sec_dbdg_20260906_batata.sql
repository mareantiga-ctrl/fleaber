-- POS_CVDA DB–DG fecho 2026-09-06
-- CONTAGEM: P0:0 P1:2 P2:2 P3:0 TOTAL:4
-- DC+DE+DF saturados. production_touched:false · fase4:false · BATATA

-- ===========================================================================
-- DB — mutex checkout por buyer (lock cobre claim→até cs_ escrito no Edge)
-- ===========================================================================
create table if not exists public.batata_checkout_mutex (
  buyer_id uuid primary key,
  claim_token text not null,
  order_ids uuid[] not null,
  expires_at timestamptz not null default (now() + interval '90 seconds')
);

revoke all on table public.batata_checkout_mutex from public, anon, authenticated;
grant select, insert, update, delete on table public.batata_checkout_mutex to service_role;

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
  v_mutex_token text;
  v_mutex_exp timestamptz;
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

  select buyer_id into v_buyer from public.orders where id = v_ids[1];
  if v_buyer is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5('batata_bag_claim:' || v_buyer::text), 1, 16))::bit(64)::bigint
  );

  -- Limpar mutex expirado
  delete from public.batata_checkout_mutex
  where buyer_id = v_buyer and expires_at < now();

  select claim_token, expires_at into v_mutex_token, v_mutex_exp
  from public.batata_checkout_mutex
  where buyer_id = v_buyer
  for update;

  if v_mutex_token is not null
     and v_mutex_token is distinct from trim(p_claim_token)
     and v_mutex_exp > now() then
    return jsonb_build_object(
      'ok', true, 'action', 'wait', 'session_id', null
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
    delete from public.batata_checkout_mutex where buyer_id = v_buyer;
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

  insert into public.batata_checkout_mutex (buyer_id, claim_token, order_ids, expires_at)
  values (v_buyer, trim(p_claim_token), v_ids, now() + interval '90 seconds')
  on conflict (buyer_id) do nothing;

  if not exists (
    select 1 from public.batata_checkout_mutex
    where buyer_id = v_buyer
      and claim_token = trim(p_claim_token)
  ) then
    -- Outro pedido segura o mutex
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

create or replace function public.batata_checkout_mutex_release(
  p_buyer_id uuid,
  p_claim_token text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_buyer_id is null then return; end if;
  if p_claim_token is null or length(trim(p_claim_token)) = 0 then
    delete from public.batata_checkout_mutex where buyer_id = p_buyer_id;
  else
    delete from public.batata_checkout_mutex
    where buyer_id = p_buyer_id
      and claim_token = trim(p_claim_token);
  end if;
end;
$$;

revoke all on function public.batata_checkout_mutex_release(uuid, text) from public, anon;
grant execute on function public.batata_checkout_mutex_release(uuid, text)
  to service_role;

-- ===========================================================================
-- DB — off-platform: após fold, qualquer non-ASCII restante = off (fail-closed)
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
  v := normalize(v, NFD);
  v := regexp_replace(v, E'[\u0300-\u036f]', '', 'g');
  v := lower(normalize(v, NFC));
  v := regexp_replace(v,
    E'[\u200b\u200c\u200d\ufeff\u00ad\u2800-\u28ff\u2060\u3164\u202a-\u202e\ue000-\uf8ff]',
    '', 'g');
  v := regexp_replace(v, E'[\u0009\u000a\u000d\u00a0\u2028\u2029]+', ' ', 'g');
  v := translate(v,
    E'аеорсухіїАЕОРСУХІЇмМԝԜμΜᴀʙᴄᴅᴇғɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢѕЅɓɑωΩⲙⲘβΒ',
    E'aeopcyxiiAEOPCYXIImmwwmmabcdefghijklmnopqrstuvwxyzssbbaaoommbB');
  v := replace(v, E'㎆', 'mb');
  -- Math bold / sans (surrogate pairs já NFKC em muitos casos; limpar resto)
  v := regexp_replace(v, '[^a-z0-9 _\-/().]', '', 'g');
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
language plpgsql
immutable
as $$
declare
  v_raw text := coalesce(p_method, '');
  v_norm text;
  v_compact text;
begin
  -- Qualquer non-ASCII no raw (após só format strip mínimo) → off fail-closed
  if v_raw ~ '[^\u0000-\u007f]' then
    -- Mas acentos PT legítimos: normalizar primeiro
    v_norm := public.batata_normalize_payment_method(v_raw);
    -- Se depois do fold ainda havia intenção off, ou compact casa allowlist
    v_compact := regexp_replace(v_norm, '[^a-z0-9]', '', 'g');
    if v_compact in (
      'mbway', 'transferencia', 'transfer', 'transf',
      'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
      'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
      'pagamentodiretoaovendedormbwaytransf',
      'pagamentodirectoaovendedormbwaytransf'
    ) then
      return true;
    end if;
    -- Ainda tem lixo unicode no original que não colapsou para ASCII puro de plataforma
    -- → tratar como off-platform (não abrir Stripe)
    if v_raw ~ '[^\u0000-\u007f]' and v_compact not in (
      'card', 'stripe', 'applepay', 'googlepay', 'paypal'
    ) then
      return true;
    end if;
  end if;

  v_norm := public.batata_normalize_payment_method(v_raw);
  if v_norm in (
    'mb way', 'mb_way', 'mb-way', 'mbway',
    'transferencia', 'transferência', 'transfer', 'transf',
    'pagamento directo', 'pagamento direto',
    'pagamento_directo', 'pagamento_direto',
    'directo', 'direto',
    'entrega em mao', 'entrega em mão', 'em mao', 'em mão',
    'levantamento', 'combinado', 'combinada',
    'pagamento direto ao vendedor (mb way/transf)',
    'pagamento directo ao vendedor (mb way/transf)'
  ) then
    return true;
  end if;
  v_compact := regexp_replace(v_norm, '[^a-z0-9]', '', 'g');
  return v_compact in (
    'mbway', 'transferencia', 'transfer', 'transf',
    'pagamentodirecto', 'pagamentodireto', 'directo', 'direto',
    'entregaemmao', 'emmao', 'levantamento', 'combinado', 'combinada',
    'pagamentodiretoaovendedormbwaytransf',
    'pagamentodirectoaovendedormbwaytransf'
  );
end;
$$;

-- ===========================================================================
-- DD — FOMO: ALLOWLIST operacional (fim chase sinónimos)
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
  v_stem text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_allowed boolean := false;
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
  v_norm := regexp_replace(v_norm, '[0-9]', '', 'g');
  v_norm := translate(
    v_norm,
    E'áàâãäéèêëíìîïóòôõöúùûüçоОаАсСſօოäöüßѕ'
      || E'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ',
    E'aaaaaeeeeiiiiooooouuuucoaassoaoousss'
      || E'abcdefghijklmnopqrstuvwxyz'
  );
  v_norm := regexp_replace(v_norm, '[-_./]+', ' ', 'g');
  v_stem := regexp_replace(v_norm, '[^a-z\s]', '', 'g');
  v_stem := regexp_replace(v_stem, '\s+', ' ', 'g');
  v_stem := trim(v_stem);

  -- Allowlist: welcome + mensagens operacionais da app (não FOMO)
  if v_stem ~ 'bem ?vindos'
     or v_stem ~ 'directo esta a comecar'
     or v_stem ~ 'o directo esta a comecar'
     or v_stem ~ 'recusaste o pedido'
     or v_stem ~ 'pedido de .+ aguarda'
     or v_stem ~ 'reservou( para o saco| )'
     or v_stem = 'sistema'
  then
    v_allowed := true;
  end if;

  if not v_allowed then
    return jsonb_build_object('ok', false, 'error', 'purchase_announce_via_broadcast_only');
  end if;

  -- Defesa extra: nunca 🔥/🛒 scarcity mesmo se texto parecer allow
  if v_body like '%🔥%' or v_body like '%🛒%' or v_body like '%💨%'
     or v_body like '%⚡%' or v_body like '%🧨%' then
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

-- ===========================================================================
-- DG — return_label_url: mesmo critério exacto 1 ficheiro que proof
-- ===========================================================================
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
    if not public.batata_dispute_proof_url_ok(NEW.return_label_url, v_buyer, v_oid) then
      raise exception 'order_dispute_label_url_denied' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
