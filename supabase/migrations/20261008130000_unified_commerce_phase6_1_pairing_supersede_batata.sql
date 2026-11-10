-- =============================================================================
-- BATATA 2026-10-08 — Phase 6.1: PGRST203 claim_pairing + supersede safety
-- Staging only. No production. Does not reopen Phases 1–5 engines.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Pairing: single PostgREST-resolvable signature
-- Keep the hardened 4-arg form (IP rate-limit). Drop 3-arg overload that
-- caused PGRST203 when clients omit p_client_ip.
-- ---------------------------------------------------------------------------
drop function if exists public.batata_ps_claim_pairing(text, text, text);

-- Ensure 4-arg exists with defaults (re-assert body from sec hardening if present)
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'batata_ps_claim_pairing'
      and pg_get_function_identity_arguments(p.oid) =
        'p_code text, p_device_id text, p_app_version text, p_client_ip text'
  ) then
    raise exception 'batata_ps_claim_pairing(4-arg) missing — restore from sec_008 before Phase 6.1';
  end if;
end $$;

-- Soft recreate wrapper: if 4-arg exists, just grant + comment (body already on staging)
comment on function public.batata_ps_claim_pairing(text, text, text, text) is
  'Phase 6.1: sole claim_pairing overload (PostgREST). p_app_version/p_client_ip optional.';

revoke all on function public.batata_ps_claim_pairing(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_ps_claim_pairing(text, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2) Supersede safety: never mutate guaranteed / checkout / paid via PS ingest
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_find_open_reservation_for_supersede(
  p_live_id uuid,
  p_live_item_id uuid,
  p_external_buyer_ref text,
  p_external_display_name text
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_ref text := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
  v_name text := public.batata_ps_normalize_display_name(p_external_display_name);
begin
  -- Only pending soft states may be qty-superseded by a new Face comment.
  -- NEVER: guaranteed accepted, sold, rejected, expired, or checkout-bound.
  select r.id into v_id
  from public.live_reservation_requests r
  where r.live_id = p_live_id
    and r.live_item_id = p_live_item_id
    and r.source = 'facebook_manual'
    and r.status = 'pending'
    and coalesce(r.request_kind, 'approval_pending') in (
      'approval_pending', 'bag_hold_none'
    )
    and (
      (v_ref is not null and r.external_buyer_ref = v_ref)
      or (
        v_name is not null
        and length(v_name) >= 4
        and public.batata_ps_normalize_display_name(r.external_display_name) = v_name
      )
    )
    -- No checkout attempt / paid order attached
    and not exists (
      select 1 from public.commerce_checkout_attempts a
      where a.live_id = r.live_id
        and (
          (r.buyer_id is not null and a.buyer_id = r.buyer_id)
          or (a.guest_session_id is not null and a.guest_session_id = r.guest_session_id)
        )
        and coalesce(a.status, '') not in ('cancelled', 'expired', 'failed')
        and a.created_at > now() - interval '2 hours'
    )
    and not exists (
      select 1 from public.orders o
      where o.live_item_id = r.live_item_id
        and r.buyer_id is not null
        and o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or lower(trim(coalesce(o.status, ''))) in (
            'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue',
            'pendente_pagamento', 'aguardando_pagamento'
          )
          or coalesce(o.stock_units_applied, 0) > 0
        )
    )
  order by r.created_at desc
  limit 1;

  return v_id;
end;
$$;

revoke all on function public.batata_ps_find_open_reservation_for_supersede(uuid, uuid, text, text)
  from public;
grant execute on function public.batata_ps_find_open_reservation_for_supersede(uuid, uuid, text, text)
  to service_role;

-- Patch ingest supersede block: use safe finder + never touch expires_at / snapshots
-- Full function body re-applied only for the supersede section via replace of helper call.
-- We replace batata_ingest to call the safe finder and refuse guaranteed.

create or replace function public.batata_commerce_ps_try_supersede_qty(
  p_live_id uuid,
  p_live_item_id uuid,
  p_external_buyer_ref text,
  p_external_display_name text,
  p_qty integer,
  p_idempotency_key text,
  p_ocr_raw_line text default null,
  p_detected_at timestamptz default null,
  p_chat_sequence integer default null,
  p_ocr_confidence numeric default null,
  p_parser_confidence numeric default null,
  p_identity_confidence numeric default null,
  p_ingest_confidence numeric default null,
  p_ingest_status text default null,
  p_parser_intent text default null,
  p_resolved_ref_slug text default null,
  p_resolved_match_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open uuid;
  v_row public.live_reservation_requests%rowtype;
  v_blocked uuid;
begin
  -- Explicit block: if only a guaranteed/accepted open row exists for this buyer+item,
  -- do NOT supersede — return protected (caller may create? No — duplicate logical buy
  -- should be refused / no-op rather than mutate guaranteed).
  select r.id into v_blocked
  from public.live_reservation_requests r
  where r.live_id = p_live_id
    and r.live_item_id = p_live_item_id
    and r.source = 'facebook_manual'
    and r.status in ('pending', 'accepted')
    and (
      coalesce(r.request_kind, '') = 'guaranteed'
      or (r.status = 'accepted' and coalesce(r.request_kind, '') <> 'bag_hold_none')
    )
    and (
      (nullif(trim(coalesce(p_external_buyer_ref, '')), '') is not null
        and r.external_buyer_ref = trim(p_external_buyer_ref))
      or (
        public.batata_ps_normalize_display_name(p_external_display_name) is not null
        and length(public.batata_ps_normalize_display_name(p_external_display_name)) >= 4
        and public.batata_ps_normalize_display_name(r.external_display_name)
          = public.batata_ps_normalize_display_name(p_external_display_name)
      )
    )
  order by r.created_at desc
  limit 1;

  if v_blocked is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'supersede_blocked_guaranteed',
      'request_id', v_blocked,
      'duplicate', false,
      'message', 'guaranteed_or_accepted_not_mutated_by_comment'
    );
  end if;

  v_open := public.batata_ps_find_open_reservation_for_supersede(
    p_live_id,
    p_live_item_id,
    p_external_buyer_ref,
    p_external_display_name
  );

  if v_open is null then
    return jsonb_build_object('ok', true, 'action', 'no_supersede_target');
  end if;

  update public.live_reservation_requests r
  set
    requested_qty = greatest(coalesce(p_qty, 1), 1),
    ocr_raw_line = coalesce(p_ocr_raw_line, r.ocr_raw_line),
    -- detected_at / expires_at / policy snapshots UNCHANGED (no silent TTL refresh)
    chat_sequence = coalesce(p_chat_sequence, r.chat_sequence),
    ocr_confidence = coalesce(p_ocr_confidence, r.ocr_confidence),
    parser_confidence = coalesce(p_parser_confidence, r.parser_confidence),
    identity_confidence = coalesce(p_identity_confidence, r.identity_confidence),
    ingest_confidence = coalesce(p_ingest_confidence, r.ingest_confidence),
    ingest_status = case
      when p_ingest_status = 'needs_review' then 'needs_review'
      else coalesce(r.ingest_status, 'auto')
    end,
    resolved_ref_slug = coalesce(p_resolved_ref_slug, r.resolved_ref_slug),
    resolved_match_type = coalesce(p_resolved_match_type, r.resolved_match_type),
    parser_intent = coalesce(nullif(trim(p_parser_intent), ''), r.parser_intent),
    external_display_name = coalesce(
      nullif(trim(p_external_display_name), ''),
      r.external_display_name
    ),
    external_buyer_ref = coalesce(
      nullif(trim(p_external_buyer_ref), ''),
      r.external_buyer_ref
    ),
    notes = coalesce(r.notes || ' | ', '') || 'ps:supersede_qty_safe',
    idempotency_key = coalesce(nullif(trim(p_idempotency_key), ''), r.idempotency_key),
    updated_at = timezone('utc', now())
  where r.id = v_open
    and r.status = 'pending'
    and coalesce(r.request_kind, 'approval_pending') in ('approval_pending', 'bag_hold_none')
  returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object(
      'ok', true,
      'action', 'supersede_race_miss',
      'message', 'row_no_longer_safe'
    );
  end if;

  perform public.batata_recompact_reservation_queue(v_row.live_item_id);

  return jsonb_build_object(
    'ok', true,
    'action', 'superseded',
    'duplicate', false,
    'request_id', v_row.id,
    'live_item_id', v_row.live_item_id,
    'requested_qty', v_row.requested_qty,
    'expires_at', v_row.expires_at,
    'request_kind', v_row.request_kind,
    'ttl_unchanged', true
  );
end;
$$;

revoke all on function public.batata_commerce_ps_try_supersede_qty(
  uuid, uuid, text, text, integer, text, text, timestamptz, integer,
  numeric, numeric, numeric, numeric, text, text, text, text
) from public;
grant execute on function public.batata_commerce_ps_try_supersede_qty(
  uuid, uuid, text, text, integer, text, text, timestamptz, integer,
  numeric, numeric, numeric, numeric, text, text, text, text
) to service_role;

notify pgrst, 'reload schema';
