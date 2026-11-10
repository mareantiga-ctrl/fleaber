-- PS: cancel/supersede por nome normalizado + fallback 1 reserva FB pendente (stock correcto)

create or replace function public.batata_ps_normalize_display_name(p_name text)
returns text
language sql
immutable
as $$
  select nullif(
    lower(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'))),
    ''
  );
$$;

create or replace function public.batata_ps_find_open_reservation(
  p_live_id uuid,
  p_live_item_id uuid,
  p_buyer_ref text,
  p_display_name text,
  p_allow_single_fallback boolean default true
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_cnt int;
  v_norm text := public.batata_ps_normalize_display_name(p_display_name);
  v_ref text := nullif(trim(coalesce(p_buyer_ref, '')), '');
begin
  if v_ref is not null then
    select r.id into v_id
    from public.live_reservation_requests r
    where r.live_id = p_live_id
      and (p_live_item_id is null or r.live_item_id = p_live_item_id)
      and r.external_buyer_ref = v_ref
      and r.status = 'pending'
    order by r.detected_at desc nulls last, r.created_at desc
    limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  if v_norm is not null
     and length(v_norm) >= 4
     and v_norm not in (
       'facebook', 'cliente', 'comprador', 'teste', 'afinal', 'so', 'só',
       'ja', 'já', 'nao', 'não', 'quero', 'py', 'ocr', 'ref', 'saco'
     ) then
    select r.id into v_id
    from public.live_reservation_requests r
    where r.live_id = p_live_id
      and (p_live_item_id is null or r.live_item_id = p_live_item_id)
      and public.batata_ps_normalize_display_name(r.external_display_name) = v_norm
      and r.status = 'pending'
    order by r.detected_at desc nulls last, r.created_at desc
    limit 1;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  if p_allow_single_fallback and p_live_item_id is not null then
    -- BATATA 2026-07-21: NÃO roubar reserva de outra pessoa.
    -- Fallback «1 pending no artigo» só quando não há nome fiável (OCR anónimo).
    -- Com «Marta» + 1 pending da «Lara» → NULL → INSERT novo (não supersede).
    if v_norm is null or length(v_norm) < 4 then
      select count(*)::int into v_cnt
      from public.live_reservation_requests r
      where r.live_id = p_live_id
        and r.live_item_id = p_live_item_id
        and r.source = 'facebook_manual'
        and r.status = 'pending'
        and r.created_at > now() - interval '45 minutes';

      if v_cnt = 1 then
        select r.id into v_id
        from public.live_reservation_requests r
        where r.live_id = p_live_id
          and r.live_item_id = p_live_item_id
          and r.source = 'facebook_manual'
          and r.status = 'pending'
          and r.created_at > now() - interval '45 minutes'
        order by r.detected_at desc nulls last, r.created_at desc
        limit 1;
        return v_id;
      end if;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function public.batata_ps_normalize_display_name(text) from public;
revoke all on function public.batata_ps_find_open_reservation(uuid, uuid, text, text, boolean) from public;
grant execute on function public.batata_ps_normalize_display_name(text) to authenticated, service_role;
grant execute on function public.batata_ps_find_open_reservation(uuid, uuid, text, text, boolean) to service_role;

-- Patch ingest v2: usar batata_ps_find_open_reservation em cancel + supersede
-- (copiar de ps_supersede_cancel_batata.sql e substituir selects manuais)

create or replace function public.batata_ingest_ocr_reservation_v2(
  p_device_token text,
  p_live_id uuid,
  p_external_display_name text,
  p_external_buyer_ref text,
  p_ocr_raw_line text,
  p_ocr_line_hash text,
  p_detected_at timestamptz,
  p_ref_slug text default null,
  p_public_slot int default null,
  p_ref_number int default null,
  p_requested_qty int default 1,
  p_title_hint text default null,
  p_chat_sequence int default null,
  p_avatar_phash text default null,
  p_ocr_confidence numeric default null,
  p_parser_confidence numeric default null,
  p_identity_confidence numeric default null,
  p_parser_intent text default null,
  p_device_id text default null,
  p_force_needs_review boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_resolve jsonb;
  v_item_id uuid;
  v_match_type text;
  v_item_conf numeric(4, 3);
  v_final_conf numeric(4, 3);
  v_ingest_status text;
  v_idem text;
  v_existing uuid;
  v_open_id uuid;
  v_row public.live_reservation_requests%rowtype;
  v_qty int;
  v_buyer_ref text;
  v_intent text;
  v_cnt int;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;
  v_qty := greatest(coalesce(p_requested_qty, 1), 1);
  v_buyer_ref := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
  v_intent := lower(trim(coalesce(p_parser_intent, '')));

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if coalesce(v_live.seller_id, v_live.vendedor_id) is distinct from v_seller_id then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if coalesce(v_live.status, '') in ('ended', 'cancelled') then
    return jsonb_build_object('ok', false, 'error', 'live_ended');
  end if;

  v_idem := 'ocr:' || trim(coalesce(p_ocr_line_hash, ''));
  if length(v_idem) <= 4 then
    return jsonb_build_object('ok', false, 'error', 'missing_line_hash');
  end if;

  select r.id into v_existing
  from public.live_reservation_requests r
  where r.idempotency_key = v_idem
  limit 1;

  if v_existing is not null then
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'request_id', v_existing
    );
  end if;

  v_resolve := public.batata_resolve_live_item_ref_v2(
    p_live_id,
    p_ref_slug,
    p_public_slot,
    p_ref_number,
    p_title_hint
  );

  if coalesce((v_resolve->>'ok')::boolean, false) is not true then
    if (v_resolve->>'error') = 'ambiguous_title' then
      v_item_id := null;
      v_match_type := 'ambiguous';
      v_item_conf := 0.3;
    elsif v_intent = 'cancel' and (v_buyer_ref is not null or nullif(trim(p_external_display_name), '') is not null) then
      v_item_id := null;
      v_match_type := 'cancel_no_ref';
      v_item_conf := 0.5;
    else
      return jsonb_build_object(
        'ok', false,
        'error', coalesce(v_resolve->>'error', 'item_not_found'),
        'resolve', v_resolve
      );
    end if;
  else
    v_item_id := (v_resolve->>'live_item_id')::uuid;
    v_match_type := v_resolve->>'match_type';
    v_item_conf := coalesce((v_resolve->>'confidence')::numeric, 0.8);
  end if;

  if v_intent = 'cancel' then
    with cancelled as (
      update public.live_reservation_requests r
      set
        status = 'rejected',
        ingest_status = 'rejected',
        notes = coalesce(r.notes || ' | ', '') || 'ps:auto_cancel',
        ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
        external_display_name = coalesce(
          nullif(trim(p_external_display_name), ''),
          r.external_display_name
        ),
        updated_at = now()
      where r.id in (
        select r2.id
        from public.live_reservation_requests r2
        where r2.live_id = p_live_id
          and (v_item_id is null or r2.live_item_id = v_item_id)
          and r2.status = 'pending'
          and (
            (v_buyer_ref is not null and r2.external_buyer_ref = v_buyer_ref)
            or (
              public.batata_ps_normalize_display_name(p_external_display_name) is not null
              and length(public.batata_ps_normalize_display_name(p_external_display_name)) >= 4
              and public.batata_ps_normalize_display_name(r2.external_display_name)
                = public.batata_ps_normalize_display_name(p_external_display_name)
            )
            or (
              -- Fallback OCR anónimo: só 1 pending neste artigo.
              -- NUNCA com nome fiável (Marta não pode cancelar o AM1 da Lara).
              v_item_id is not null
              and r2.live_item_id = v_item_id
              and r2.source = 'facebook_manual'
              and (
                public.batata_ps_normalize_display_name(p_external_display_name) is null
                or length(public.batata_ps_normalize_display_name(p_external_display_name)) < 4
              )
              and (
                select count(*)::int
                from public.live_reservation_requests r3
                where r3.live_id = p_live_id
                  and r3.live_item_id = v_item_id
                  and r3.source = 'facebook_manual'
                  and r3.status = 'pending'
                  and r3.created_at > now() - interval '45 minutes'
              ) = 1
            )
          )
      )
      returning r.*
    )
    select count(*)::int,
           (array_agg(id order by updated_at desc nulls last, created_at desc))[1]
    into v_cnt, v_open_id
    from cancelled;

    if coalesce(v_cnt, 0) = 0 then
      return jsonb_build_object(
        'ok', true,
        'action', 'cancel_noop',
        'message', 'no_open_reservation'
      );
    end if;

    select * into v_row
    from public.live_reservation_requests
    where id = v_open_id;

    perform public.batata_recompact_reservation_queue(v_row.live_item_id);

    return jsonb_build_object(
      'ok', true,
      'action', 'cancelled',
      'request_id', v_row.id,
      'live_item_id', v_row.live_item_id,
      'ingest_status', v_row.ingest_status,
      'cancelled_count', v_cnt
    );
  end if;

  v_final_conf := least(
    0.99,
    coalesce(p_ocr_confidence, 0.7) * 0.35
    + coalesce(p_parser_confidence, 0.7) * 0.35
    + coalesce(v_item_conf, 0.5) * 0.2
    + coalesce(p_identity_confidence, 0.7) * 0.1
  );

  if p_force_needs_review
     or v_item_id is null
     or v_match_type = 'ambiguous'
     or v_final_conf < 0.85 then
    v_ingest_status := 'needs_review';
  else
    v_ingest_status := 'auto';
  end if;

  if v_item_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'needs_review_no_item',
      'ingest_status', 'needs_review',
      'confidence', v_final_conf
    );
  end if;

  -- Supersede: só mesma pessoa (buyer_ref / nome). Sem fallback cross-buyer.
  v_open_id := public.batata_ps_find_open_reservation(
    p_live_id,
    v_item_id,
    v_buyer_ref,
    p_external_display_name,
    false
  );

  if v_open_id is not null then
    update public.live_reservation_requests r
    set
      requested_qty = v_qty,
      ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
      detected_at = coalesce(p_detected_at, r.detected_at),
      chat_sequence = coalesce(p_chat_sequence, r.chat_sequence),
      ocr_confidence = coalesce(p_ocr_confidence, r.ocr_confidence),
      parser_confidence = coalesce(p_parser_confidence, r.parser_confidence),
      identity_confidence = coalesce(p_identity_confidence, r.identity_confidence),
      ingest_confidence = v_final_conf,
      ingest_status = case
        when v_ingest_status = 'needs_review' then 'needs_review'
        else 'auto'
      end,
      resolved_ref_slug = coalesce(p_ref_slug, p_public_slot::text, p_ref_number::text),
      resolved_match_type = v_match_type,
      parser_intent = coalesce(nullif(trim(p_parser_intent), ''), r.parser_intent),
      external_display_name = coalesce(
        nullif(trim(p_external_display_name), ''),
        r.external_display_name
      ),
      external_buyer_ref = coalesce(v_buyer_ref, r.external_buyer_ref),
      notes = coalesce(r.notes || ' | ', '') || 'ps:supersede_qty',
      idempotency_key = v_idem,
      updated_at = now()
    where r.id = v_open_id
    returning * into v_row;

    perform public.batata_recompact_reservation_queue(v_row.live_item_id);

    return jsonb_build_object(
      'ok', true,
      'action', 'superseded',
      'duplicate', false,
      'request_id', v_row.id,
      'live_item_id', v_row.live_item_id,
      'queue_position', v_row.queue_position,
      'ingest_status', v_row.ingest_status,
      'requested_qty', v_row.requested_qty,
      'final_confidence', v_final_conf
    );
  end if;

  insert into public.live_reservation_requests (
    live_id,
    live_item_id,
    seller_id,
    buyer_id,
    requested_qty,
    source,
    status,
    notes,
    detected_at,
    external_display_name,
    external_buyer_ref,
    chat_sequence,
    avatar_phash,
    ocr_raw_line,
    ingest_channel,
    ingest_confidence,
    ocr_confidence,
    parser_confidence,
    item_match_confidence,
    identity_confidence,
    resolved_ref_slug,
    resolved_match_type,
    parser_intent,
    device_id,
    ingest_status,
    idempotency_key
  ) values (
    p_live_id,
    v_item_id,
    v_seller_id,
    null,
    v_qty,
    'facebook_manual',
    'pending',
    'ps:ocr:v2',
    p_detected_at,
    nullif(trim(coalesce(p_external_display_name, '')), ''),
    v_buyer_ref,
    p_chat_sequence,
    nullif(trim(coalesce(p_avatar_phash, '')), ''),
    nullif(trim(coalesce(p_ocr_raw_line, '')), ''),
    'ocr',
    v_final_conf,
    p_ocr_confidence,
    p_parser_confidence,
    v_item_conf,
    p_identity_confidence,
    coalesce(p_ref_slug, p_public_slot::text, p_ref_number::text),
    v_match_type,
    nullif(trim(coalesce(p_parser_intent, '')), ''),
    nullif(trim(coalesce(p_device_id, '')), ''),
    v_ingest_status,
    v_idem
  )
  returning * into v_row;

  perform public.batata_recompact_reservation_queue(v_row.live_item_id);

  select * into v_row
  from public.live_reservation_requests
  where id = v_row.id;

  return jsonb_build_object(
    'ok', true,
    'action', 'created',
    'duplicate', false,
    'request_id', v_row.id,
    'live_item_id', v_row.live_item_id,
    'queue_position', v_row.queue_position,
    'ingest_status', v_row.ingest_status,
    'requested_qty', v_row.requested_qty,
    'effective_at', v_row.effective_at,
    'match_type', v_match_type,
    'final_confidence', v_final_conf
  );
end;
$$;

notify pgrst, 'reload schema';
