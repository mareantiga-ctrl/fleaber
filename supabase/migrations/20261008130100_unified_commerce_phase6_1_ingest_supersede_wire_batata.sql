-- Phase 6.1: wire ingest supersede to safe helper (no guaranteed mutation / no TTL refresh)
-- Replaces the supersede block inside batata_ingest_ocr_reservation_v2 by redefining
-- only via a thin shim: we patch by replacing the function's supersede section through
-- full recreate of the post-resolve reserve path using the helper.

-- Strategy: create batata_ingest_ocr_reservation_v2_supersede_hook used... 
-- Simpler: UPDATE the live function via search_replace equivalent — full CREATE OR REPLACE
-- of ingest is large; instead override by wrapping find+update through the helper
-- using a trigger-less approach: replace batata_ps_find_open_reservation when called
-- from ingest is unsafe. Wire by replacing the supersede section with a SQL patch function
-- that ingest already can call if we redefine ingest's supersede to call try_supersede.

-- Minimal approach: monkey-patch via replacing batata_ps_find_open_reservation behavior
-- for supersede-only is wrong. Full ingest recreate of supersede block:

create or replace function public.batata_commerce_ps_ingest_after_resolve_reserve(
  p_live_id uuid,
  p_seller_id uuid,
  p_item_id uuid,
  p_qty integer,
  p_buyer_ref text,
  p_external_display_name text,
  p_idem text,
  p_detected_at timestamptz,
  p_ocr_raw_line text,
  p_chat_sequence integer,
  p_avatar_phash text,
  p_channel text,
  p_ingest_status text,
  p_parser_intent text,
  p_device_id text,
  p_ocr_confidence numeric,
  p_parser_confidence numeric,
  p_identity_confidence numeric,
  p_item_conf numeric,
  p_final_conf numeric,
  p_resolved_ref_slug text,
  p_match_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sup jsonb;
  v_created jsonb;
begin
  v_sup := public.batata_commerce_ps_try_supersede_qty(
    p_live_id,
    p_item_id,
    p_buyer_ref,
    p_external_display_name,
    p_qty,
    p_idem,
    p_ocr_raw_line,
    p_detected_at,
    p_chat_sequence,
    p_ocr_confidence,
    p_parser_confidence,
    p_identity_confidence,
    p_final_conf,
    p_ingest_status,
    p_parser_intent,
    p_resolved_ref_slug,
    p_match_type
  );

  if (v_sup->>'action') = 'superseded' then
    update public.commerce_ps_event_ledger
    set reservation_id = nullif(v_sup->>'request_id', '')::uuid,
        outcome = 'superseded',
        result = v_sup
    where event_key = p_idem;
    return v_sup || jsonb_build_object(
      'final_confidence', p_final_conf,
      'via', 'phase6_1_supersede_safe'
    );
  end if;

  if (v_sup->>'action') = 'supersede_blocked_guaranteed' then
    update public.commerce_ps_event_ledger
    set reservation_id = nullif(v_sup->>'request_id', '')::uuid,
        outcome = 'supersede_blocked_guaranteed',
        result = v_sup
    where event_key = p_idem;
    return v_sup || jsonb_build_object('via', 'phase6_1_supersede_safe');
  end if;

  -- no safe supersede target → create via engine
  v_created := public.batata_commerce_reserve_from_ps_event(
    p_seller_id,
    p_live_id,
    p_item_id,
    p_qty,
    p_buyer_ref,
    p_external_display_name,
    p_idem,
    p_detected_at,
    p_ocr_raw_line,
    p_chat_sequence,
    p_avatar_phash,
    p_channel,
    p_ingest_status,
    p_parser_intent,
    p_device_id,
    p_ocr_confidence,
    p_parser_confidence,
    p_identity_confidence,
    p_item_conf,
    p_final_conf,
    p_resolved_ref_slug,
    p_match_type
  );

  update public.commerce_ps_event_ledger
  set reservation_id = nullif(v_created->>'request_id', '')::uuid,
      outcome = coalesce(v_created->>'action', v_created->>'outcome'),
      result = v_created
  where event_key = p_idem;

  if coalesce((v_created->>'ok')::boolean, false) = true
     and coalesce(v_created->>'action', '') = 'created'
     and nullif(v_created->>'request_id', '') is not null then
    perform public.batata_recompact_reservation_queue(p_item_id);
  end if;

  return v_created || jsonb_build_object(
    'live_item_id', p_item_id,
    'match_type', p_match_type,
    'final_confidence', p_final_conf,
    'ingest_status', p_ingest_status,
    'event_key', p_idem,
    'via', 'phase6_1_canonical'
  );
end;
$$;

revoke all on function public.batata_commerce_ps_ingest_after_resolve_reserve(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) from public;
grant execute on function public.batata_commerce_ps_ingest_after_resolve_reserve(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) to service_role;
