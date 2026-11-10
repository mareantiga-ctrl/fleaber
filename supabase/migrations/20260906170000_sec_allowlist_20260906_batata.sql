-- Allowlist estrutural 2026-09-06 (pós CJCO)
-- Objectivo: saturar famílias denylist (rails/FOMO/scripts) sem chase infinito.
-- BATATA: não remove cards; restringe texto hostil. production_touched:false · fase4:false

-- ===========================================================================
-- 1) Notes/label ALLOWLIST (em vez de só denylist de rails)
-- ===========================================================================
create or replace function public.batata_chat_client_notes_allowed(p_text text)
returns boolean
language sql
immutable
as $$
  select
    length(trim(coalesce(p_text, ''))) = 0
    or lower(trim(p_text)) in (
      'stripe_paid_direct',
      'ok',
      'paguei',
      'pago',
      'comprovativo',
      'comprovativo anexo'
    )
    or (
      char_length(trim(p_text)) <= 120
      and p_text !~ '[€$£¥]'
      and public.batata_chat_normalize_lie_text(p_text)
            !~* '(\d+\s*(€|eur|euros?)|(€|eur|euros?)\s*\d)'
      and not public.batata_chat_payment_lie_text(p_text)
    );
$$;

create or replace function public.batata_chat_seguro_label_allowed(p_text text)
returns boolean
language sql
immutable
as $$
  select
    length(trim(coalesce(p_text, ''))) = 0
    or public.batata_chat_normalize_lie_text(p_text) in (
      'seguro fleaber',
      'compra paga pelo seguro fleaber',
      'seguro fleaber pago',
      'compra paga'
    );
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select
    public.batata_chat_payment_lie_text(p_text)
    or (
      length(trim(coalesce(p_text, ''))) > 0
      and not public.batata_chat_client_notes_allowed(p_text)
      and (
        public.batata_chat_normalize_lie_text(p_text)
          ~* '(\d+\s*(€|eur|euros?)|(€|eur|euros?)\s*\d|confirmado|aprovado|recebi|paguei|transfer|pagamento|pago)'
        or public.batata_chat_normalize_lie_text(p_text)
          ~* '(pay|mb|pix|wise|revolut|paypal|klarna|iban|wallet|cash|gift|sepa|bonifico|uberweisung|wechat|upi|skrill)'
      )
    );
$$;

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
    if v_notes ~ '[<>]' or not public.batata_chat_client_notes_allowed(v_notes) then
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
      if v_buyer is null or position(v_prefix in v_path) = 0 then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if v_path !~ ('fleaber_private/order_proofs/' || v_buyer::text || '/' || v_order::text || '/') then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind = 'seguro_fleaber_paid' then
    v_label := coalesce(v_json->>'label', '');
    if not public.batata_chat_seguro_label_allowed(v_label) then
      raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'cancel_request_outcome' then
    v_display := coalesce(v_json->>'display', '');
    if public.batata_chat_payment_lie_text(v_display)
       or not public.batata_chat_client_notes_allowed(v_display) then
      raise exception 'chat_system_card_display_forbidden' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ===========================================================================
-- 2) FOMO — stems compactos (multi-língua) em vez de lista infinita
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

  -- Stems multi-língua (PT/EN/ES/IT/DE/FR + FOMO genérico). Compra = só broadcast pago.
  if v_compact ~
     '(compr|bought|purchas|levou|levar|esgot|esaur|vend|sold|snap|grab|claim|gone|mine|reserv|stock|taken|last|left|piece|pezzo|stuck|ausver|verkauf|epuis|agot|dueno|embora|dono|acab|final|call|going|encom|unit|disponib|einer|lager|pris|preso|saurit|nouvenc|nomore|outof|semstock|jatem|foiembora|ultim|nurnoch|plusde|dejapris|giaven|nonce|schonweg|keinla)'
     or v_body like '%🛒%'
     or (v_body like '%✅%' and v_compact ~
         '(compr|levou|sold|vend|esgot|claim|snap|grab|gone|acab|stock|taken|mine|last|reserv|dono|embora|esaur|ausver|epuis|pezzo)')
     or (v_compact ~ '\d' and v_compact ~ '(left|piece|pezzo|unit|stock|stuck|disponib)') then
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

notify pgrst, 'reload schema';
