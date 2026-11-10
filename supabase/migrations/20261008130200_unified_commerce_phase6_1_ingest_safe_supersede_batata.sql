-- Phase 6.1 ingest wire to safe supersede
create or replace function public.batata_ingest_ocr_reservation_v2(
  p_device_token text,
  p_live_id uuid,
  p_external_display_name text,
  p_external_buyer_ref text,
  p_ocr_raw_line text,
  p_ocr_line_hash text,
  p_detected_at timestamptz,
  p_ref_slug text default null,
  p_public_slot integer default null,
  p_ref_number integer default null,
  p_requested_qty integer default 1,
  p_title_hint text default null,
  p_chat_sequence integer default null,
  p_avatar_phash text default null,
  p_ocr_confidence numeric default null,
  p_parser_confidence numeric default null,
  p_identity_confidence numeric default null,
  p_parser_intent text default null,
  p_device_id text default null,
  p_force_needs_review boolean default false,
  p_comment_id text default null,
  p_event_channel text default null
)
returns jsonb
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
  v_ledger_ins boolean := false;
  v_created jsonb;
  v_channel text;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;
  v_buyer_ref := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
  v_intent := lower(trim(coalesce(p_parser_intent, '')));
  v_channel := coalesce(
    nullif(trim(p_event_channel), ''),
    'ocr'
  );

  -- Non-purchase intents must not create reservations
  if v_intent in ('chat', 'ambiguous', 'tech', 'unknown') then
    return jsonb_build_object(
      'ok', true,
      'action', 'ignored_non_purchase',
      'parser_intent', v_intent
    );
  end if;

  if p_requested_qty is not null and (p_requested_qty < 1 or p_requested_qty > 99) then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  v_qty := greatest(coalesce(p_requested_qty, 1), 1);

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

  v_idem := public.batata_commerce_ps_event_key(p_live_id, p_ocr_line_hash, p_comment_id);
  if v_idem is null then
    return jsonb_build_object('ok', false, 'error', 'missing_line_hash');
  end if;

  -- Ledger claim (persistent + concurrent)
  begin
    insert into public.commerce_ps_event_ledger (event_key, live_id, seller_id, result)
    values (v_idem, p_live_id, v_seller_id, jsonb_build_object('phase', 'claimed'));
    v_ledger_ins := true;
  exception
    when unique_violation then
      select l.reservation_id, l.result
      into v_existing, v_created
      from public.commerce_ps_event_ledger l
      where l.event_key = v_idem;
      if v_existing is not null then
        return jsonb_build_object(
          'ok', true,
          'duplicate', true,
          'request_id', v_existing,
          'action', 'duplicate',
          'ledger', true
        );
      end if;
      -- LRR fallback
      select r.id into v_existing
      from public.live_reservation_requests r
      where r.idempotency_key = v_idem
      limit 1;
      if v_existing is not null then
        return jsonb_build_object(
          'ok', true,
          'duplicate', true,
          'request_id', v_existing,
          'action', 'duplicate'
        );
      end if;
      -- In-flight claim without reservation yet â€” treat as duplicate soft
      return jsonb_build_object(
        'ok', true,
        'duplicate', true,
        'request_id', null,
        'action', 'duplicate_inflight',
        'prior', coalesce(v_created, '{}'::jsonb)
      );
  end;

  select r.id into v_existing
  from public.live_reservation_requests r
  where r.idempotency_key = v_idem
  limit 1;
  if v_existing is not null then
    update public.commerce_ps_event_ledger
    set reservation_id = v_existing,
        outcome = 'duplicate',
        result = jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_existing)
    where event_key = v_idem;
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'request_id', v_existing,
      'action', 'duplicate'
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
      update public.commerce_ps_event_ledger
      set outcome = 'resolve_failed',
          result = jsonb_build_object('ok', false, 'error', coalesce(v_resolve->>'error', 'item_not_found'))
      where event_key = v_idem;
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

  -- CANCEL path (preserved contract â€” frees open pending/accepted unpaid)
  if v_intent = 'cancel' then
    with cancelled as (
      update public.live_reservation_requests r
      set
        status = 'rejected',
        ingest_status = 'rejected',
        notes = coalesce(r.notes || ' | ', '') || case
          when r.status = 'accepted' then 'ps:auto_cancel_accepted'
          else 'ps:auto_cancel'
        end,
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
          and r2.status in ('pending', 'accepted')
          and not exists (
            select 1 from public.orders o
            where (
              (r2.buyer_id is not null and o.buyer_id = r2.buyer_id)
              or (r2.buyer_id is null and false)
            )
              and o.live_item_id = r2.live_item_id
              and (
                public.batata_order_status_is_sold_fulfilled(o.status)
                or lower(trim(coalesce(o.status, ''))) in (
                  'pago', 'paid', 'enviado', 'concluido', 'concluÃ­do', 'entregue'
                )
                or coalesce(o.stock_units_applied, 0) > 0
              )
          )
          and (
            (v_buyer_ref is not null and r2.external_buyer_ref = v_buyer_ref)
            or (
              public.batata_ps_normalize_display_name(p_external_display_name) is not null
              and length(public.batata_ps_normalize_display_name(p_external_display_name)) >= 4
              and public.batata_ps_normalize_display_name(r2.external_display_name)
                = public.batata_ps_normalize_display_name(p_external_display_name)
            )
            or (
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
                  and r3.status in ('pending', 'accepted')
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
      update public.commerce_ps_event_ledger
      set outcome = 'cancel_noop',
          result = jsonb_build_object('ok', true, 'action', 'cancel_noop')
      where event_key = v_idem;
      return jsonb_build_object(
        'ok', true,
        'action', 'cancel_noop',
        'message', 'no_open_reservation'
      );
    end if;

    select * into v_row from public.live_reservation_requests where id = v_open_id;
    perform public.batata_recompact_reservation_queue(v_row.live_item_id);
    begin
      perform public.batata_recompute_live_item_status(v_row.live_item_id);
    exception when others then
      null;
    end;

    begin
      insert into public.live_messages (live_id, user_id, kind, body, sender_label, channel)
      values (
        v_row.live_id,
        coalesce(v_row.buyer_id, v_row.seller_id),
        'system',
        'â†© ' || coalesce(nullif(trim(v_row.external_display_name), ''), 'Comprador')
          || ' cancelou a reserva de ' || public.batata_live_item_chat_label(v_row.live_item_id),
        'Sistema',
        'fleaber'
      );
    exception when others then
      null;
    end;

    update public.commerce_ps_event_ledger
    set reservation_id = v_row.id,
        outcome = 'cancelled',
        result = jsonb_build_object('ok', true, 'action', 'cancelled', 'request_id', v_row.id)
    where event_key = v_idem;

    return jsonb_build_object(
      'ok', true,
      'action', 'cancelled',
      'request_id', v_row.id,
      'live_item_id', v_row.live_item_id,
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
    update public.commerce_ps_event_ledger
    set outcome = 'needs_review_no_item',
        result = jsonb_build_object('ok', false, 'error', 'needs_review_no_item')
    where event_key = v_idem;
    return jsonb_build_object(
      'ok', false,
      'error', 'needs_review_no_item',
      'ingest_status', 'needs_review',
      'confidence', v_final_conf
    );
  end if;

    -- Phase 6.1: safe supersede (pending only) or canonical create
  return public.batata_commerce_ps_ingest_after_resolve_reserve(
    p_live_id,
    v_seller_id,
    v_item_id,
    v_qty,
    v_buyer_ref,
    p_external_display_name,
    v_idem,
    p_detected_at,
    p_ocr_raw_line,
    p_chat_sequence,
    p_avatar_phash,
    v_channel,
    v_ingest_status,
    p_parser_intent,
    p_device_id,
    p_ocr_confidence,
    p_parser_confidence,
    p_identity_confidence,
    v_item_conf,
    v_final_conf,
    coalesce(p_ref_slug, p_public_slot::text, p_ref_number::text),
    v_match_type
  );
end;
$$;

revoke all on function public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, integer, integer, integer, text, integer, text,
  numeric, numeric, numeric, text, text, boolean, text, text
) from public;
grant execute on function public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, integer, integer, integer, text, integer, text,
  numeric, numeric, numeric, text, text, boolean, text, text
) to service_role;

notify pgrst, 'reload schema';
