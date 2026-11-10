-- =============================================================================
-- BATATA 2026-10-08 — Phase 6: PS Reader → motor canónico + idempotência persistente
-- Staging only (repo migration). Does NOT rewrite Phases 1–5 engines.
-- PS Reader remains an event origin; stock/policy/trust stay in batata_reserve_with_policy.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Persistent event ledger (concurrent same-event → one row)
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_ps_event_ledger (
  event_key text primary key,
  live_id uuid not null,
  seller_id uuid not null,
  reservation_id uuid null,
  outcome text null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists commerce_ps_event_ledger_live_idx
  on public.commerce_ps_event_ledger (live_id, created_at desc);

comment on table public.commerce_ps_event_ledger is
  'Phase 6: durable idempotency for PS/OCR/Face comment events. Key is origin-stable.';

alter table public.commerce_ps_event_ledger enable row level security;
revoke all on table public.commerce_ps_event_ledger from public, anon, authenticated;
grant select, insert, update, delete on table public.commerce_ps_event_ledger to service_role;

-- Unique on LRR idempotency_key (race-safe second insert fails cleanly)
create unique index if not exists live_reservation_requests_idempotency_key_uidx
  on public.live_reservation_requests (idempotency_key)
  where idempotency_key is not null and length(trim(idempotency_key)) > 0;

-- ---------------------------------------------------------------------------
-- 2) Stable event key builder (comment_id preferred; else OCR hash)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_event_key(
  p_live_id uuid,
  p_ocr_line_hash text,
  p_comment_id text default null
)
returns text
language plpgsql
immutable
as $$
declare
  v_cmt text := nullif(trim(coalesce(p_comment_id, '')), '');
  v_hash text := nullif(trim(coalesce(p_ocr_line_hash, '')), '');
begin
  if p_live_id is null then
    return null;
  end if;
  if v_cmt is not null and length(v_cmt) >= 4 then
    return 'fb_cmt:' || p_live_id::text || ':' || v_cmt;
  end if;
  if v_hash is not null and length(v_hash) >= 8 then
    return 'ocr:' || v_hash;
  end if;
  return null;
end;
$$;

revoke all on function public.batata_commerce_ps_event_key(uuid, text, text) from public;
grant execute on function public.batata_commerce_ps_event_key(uuid, text, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Resolve securely linked Fleaber buyer from Face comment id (map only)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_ps_resolve_linked_buyer(
  p_external_buyer_ref text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ref text := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
  v_digits text;
  v_uid uuid;
begin
  if v_ref is null then
    return jsonb_build_object('linked', false, 'buyer_id', null);
  end if;

  -- fb:{digits} from DOM — only claim via verified map (never by display name)
  if v_ref ~* '^fb:[0-9]{5,}$' then
    v_digits := substring(v_ref from 4);
    select m.user_id into v_uid
    from public.batata_facebook_id_map m
    where m.comment_fb_id = v_digits
    limit 1;
    if v_uid is not null then
      return jsonb_build_object(
        'linked', true,
        'buyer_id', v_uid,
        'via', 'facebook_id_map'
      );
    end if;
  end if;

  return jsonb_build_object('linked', false, 'buyer_id', null, 'via', 'none');
end;
$$;

revoke all on function public.batata_commerce_ps_resolve_linked_buyer(text) from public;
grant execute on function public.batata_commerce_ps_resolve_linked_buyer(text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 4) Canonical reserve for PS/Face event (wraps decide + engine insert + metadata)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_reserve_from_ps_event(
  p_seller_id uuid,
  p_live_id uuid,
  p_live_item_id uuid,
  p_qty integer,
  p_external_buyer_ref text,
  p_external_display_name text,
  p_idempotency_key text,
  p_detected_at timestamptz default null,
  p_ocr_raw_line text default null,
  p_chat_sequence integer default null,
  p_avatar_phash text default null,
  p_ingest_channel text default 'ocr',
  p_ingest_status text default 'auto',
  p_parser_intent text default null,
  p_device_id text default null,
  p_ocr_confidence numeric default null,
  p_parser_confidence numeric default null,
  p_identity_confidence numeric default null,
  p_item_match_confidence numeric default null,
  p_ingest_confidence numeric default null,
  p_resolved_ref_slug text default null,
  p_resolved_match_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_link jsonb;
  v_buyer uuid;
  v_linked boolean := false;
  v_reserve jsonb;
  v_rid uuid;
  v_outcome text;
  v_channel text := coalesce(nullif(trim(p_ingest_channel), ''), 'ocr');
begin
  if p_seller_id is null or p_live_id is null or p_live_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 then
    return jsonb_build_object('ok', false, 'error', 'missing_idempotency_key');
  end if;
  if coalesce(p_qty, 0) < 1 or coalesce(p_qty, 0) > 99 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;

  -- Already stamped on LRR?
  select r.id into v_rid
  from public.live_reservation_requests r
  where r.idempotency_key = trim(p_idempotency_key)
  limit 1;
  if v_rid is not null then
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'request_id', v_rid,
      'action', 'duplicate'
    );
  end if;

  v_link := public.batata_commerce_ps_resolve_linked_buyer(p_external_buyer_ref);
  v_linked := coalesce((v_link->>'linked')::boolean, false);
  v_buyer := nullif(v_link->>'buyer_id', '')::uuid;

  -- Unlinked Face → never invent Fleaber buyer; never apply trust benefit
  v_reserve := public.batata_reserve_with_policy(
    p_seller_id,
    v_buyer,
    p_live_id,
    p_live_item_id,
    p_qty,
    'facebook_manual',
    null,
    v_linked,
    'ps:phase6:engine'
  );

  if coalesce((v_reserve->>'ok')::boolean, false) = false then
    return v_reserve || jsonb_build_object('action', 'engine_error');
  end if;

  v_outcome := v_reserve->>'outcome';
  if v_outcome = 'UNAVAILABLE' then
    return jsonb_build_object(
      'ok', true,
      'action', 'unavailable',
      'duplicate', false,
      'outcome', 'UNAVAILABLE',
      'request_id', null,
      'decision', v_reserve->'decision',
      'reason', coalesce(v_reserve->>'reason', 'insufficient_stock')
    );
  end if;

  v_rid := nullif(v_reserve->>'request_id', '')::uuid;
  if v_rid is null then
    return jsonb_build_object('ok', false, 'error', 'engine_no_request_id', 'engine', v_reserve);
  end if;

  update public.live_reservation_requests r
  set
    external_display_name = coalesce(
      nullif(trim(coalesce(p_external_display_name, '')), ''),
      r.external_display_name
    ),
    external_buyer_ref = coalesce(
      nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
      r.external_buyer_ref
    ),
    detected_at = coalesce(p_detected_at, r.detected_at),
    ocr_raw_line = coalesce(nullif(trim(coalesce(p_ocr_raw_line, '')), ''), r.ocr_raw_line),
    chat_sequence = coalesce(p_chat_sequence, r.chat_sequence),
    avatar_phash = coalesce(nullif(trim(coalesce(p_avatar_phash, '')), ''), r.avatar_phash),
    ingest_channel = v_channel,
    ingest_status = coalesce(nullif(trim(p_ingest_status), ''), r.ingest_status, 'auto'),
    parser_intent = coalesce(nullif(trim(p_parser_intent), ''), r.parser_intent),
    device_id = coalesce(nullif(trim(p_device_id), ''), r.device_id),
    ocr_confidence = coalesce(p_ocr_confidence, r.ocr_confidence),
    parser_confidence = coalesce(p_parser_confidence, r.parser_confidence),
    identity_confidence = coalesce(p_identity_confidence, r.identity_confidence),
    item_match_confidence = coalesce(p_item_match_confidence, r.item_match_confidence),
    ingest_confidence = coalesce(p_ingest_confidence, r.ingest_confidence),
    resolved_ref_slug = coalesce(p_resolved_ref_slug, r.resolved_ref_slug),
    resolved_match_type = coalesce(p_resolved_match_type, r.resolved_match_type),
    idempotency_key = trim(p_idempotency_key),
    notes = case
      when coalesce(r.notes, '') = '' then 'ps:phase6:engine'
      when position('ps:phase6:engine' in r.notes) > 0 then r.notes
      else r.notes || ' | ps:phase6:engine'
    end,
    updated_at = timezone('utc', now())
  where r.id = v_rid;

  return jsonb_build_object(
    'ok', true,
    'action', 'created',
    'duplicate', false,
    'outcome', v_outcome,
    'request_id', v_rid,
    'status', v_reserve->>'status',
    'request_kind', v_reserve->>'request_kind',
    'expires_at', v_reserve->>'expires_at',
    'identity_linked', v_linked,
    'engine', v_reserve
  );
exception
  when unique_violation then
    select r.id into v_rid
    from public.live_reservation_requests r
    where r.idempotency_key = trim(p_idempotency_key)
    limit 1;
    return jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'request_id', v_rid,
      'action', 'duplicate_race'
    );
end;
$$;

revoke all on function public.batata_commerce_reserve_from_ps_event(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) from public;
grant execute on function public.batata_commerce_reserve_from_ps_event(
  uuid, uuid, uuid, integer, text, text, text, timestamptz, text, integer, text,
  text, text, text, text, numeric, numeric, numeric, numeric, numeric, text, text
) to service_role;

-- ---------------------------------------------------------------------------
-- 5) Seller-initiated Facebook/manual reserve via same engine (Studio «Mais»)
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_seller_manual_reserve_with_policy(
  p_live_id uuid,
  p_live_item_id uuid,
  p_buyer_id uuid,
  p_qty integer default 1,
  p_source text default 'facebook_manual',
  p_notes text default null,
  p_external_display_name text default null,
  p_client_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_live public.lives%rowtype;
  v_seller uuid;
  v_src text := lower(trim(coalesce(p_source, 'facebook_manual')));
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_reserve jsonb;
  v_rid uuid;
  v_idem text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_live_id is null or p_live_item_id is null or p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if v_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  if v_src not in ('facebook_manual', 'helper_manual') then
    return jsonb_build_object('ok', false, 'error', 'invalid_source');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null or v_seller is distinct from v_uid then
    if not public.batata_staff_has_permission(v_seller, 'can_manage_reservations') then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
  end if;

  v_idem := nullif(trim(coalesce(p_client_idempotency_key, '')), '');
  if v_idem is not null then
    select r.id into v_rid
    from public.live_reservation_requests r
    where r.idempotency_key = v_idem
    limit 1;
    if v_rid is not null then
      return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_rid);
    end if;
  end if;

  -- Linked Fleaber buyer → identity_linked true (trust may apply)
  v_reserve := public.batata_reserve_with_policy(
    v_seller,
    p_buyer_id,
    p_live_id,
    p_live_item_id,
    v_qty,
    v_src,
    null,
    true,
    coalesce(nullif(trim(p_notes), ''), 'seller:manual:' || v_src)
  );

  if coalesce((v_reserve->>'ok')::boolean, false) = false then
    return v_reserve;
  end if;
  if (v_reserve->>'outcome') = 'UNAVAILABLE' then
    return v_reserve || jsonb_build_object('action', 'unavailable');
  end if;

  v_rid := nullif(v_reserve->>'request_id', '')::uuid;
  if v_rid is not null then
    update public.live_reservation_requests r
    set
      external_display_name = coalesce(
        nullif(trim(coalesce(p_external_display_name, '')), ''),
        r.external_display_name
      ),
      idempotency_key = coalesce(v_idem, r.idempotency_key),
      ingest_channel = coalesce(r.ingest_channel, 'seller_studio'),
      updated_at = timezone('utc', now())
    where r.id = v_rid;
  end if;

  return v_reserve || jsonb_build_object('action', 'created', 'duplicate', false);
end;
$$;

revoke all on function public.batata_commerce_seller_manual_reserve_with_policy(
  uuid, uuid, uuid, integer, text, text, text, text
) from public;
grant execute on function public.batata_commerce_seller_manual_reserve_with_policy(
  uuid, uuid, uuid, integer, text, text, text, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Ingest v2 → ledger + cancel/supersede preserved + NEW rows via engine
-- ---------------------------------------------------------------------------
drop function if exists public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, int, int, int, text, int, text,
  numeric, numeric, numeric, text, text, boolean
);

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
      -- In-flight claim without reservation yet — treat as duplicate soft
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

  -- CANCEL path (preserved contract — frees open pending/accepted unpaid)
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
                  'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
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
        '↩ ' || coalesce(nullif(trim(v_row.external_display_name), ''), 'Comprador')
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

  -- Supersede qty on open row (same person) — preserve Face contract
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
        else coalesce(r.ingest_status, 'auto')
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

    update public.commerce_ps_event_ledger
    set reservation_id = v_row.id,
        outcome = 'superseded',
        result = jsonb_build_object('ok', true, 'action', 'superseded', 'request_id', v_row.id)
    where event_key = v_idem;

    return jsonb_build_object(
      'ok', true,
      'action', 'superseded',
      'duplicate', false,
      'request_id', v_row.id,
      'live_item_id', v_row.live_item_id,
      'requested_qty', v_row.requested_qty,
      'final_confidence', v_final_conf
    );
  end if;

  -- NEW row → canonical engine (policy + stock + trust rules)
  v_created := public.batata_commerce_reserve_from_ps_event(
    v_seller_id,
    p_live_id,
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

  update public.commerce_ps_event_ledger
  set reservation_id = nullif(v_created->>'request_id', '')::uuid,
      outcome = coalesce(v_created->>'action', v_created->>'outcome'),
      result = v_created
  where event_key = v_idem;

  if coalesce((v_created->>'ok')::boolean, false) = true
     and coalesce(v_created->>'action', '') = 'created'
     and nullif(v_created->>'request_id', '') is not null then
    perform public.batata_recompact_reservation_queue(v_item_id);
  end if;

  return v_created || jsonb_build_object(
    'live_item_id', v_item_id,
    'match_type', v_match_type,
    'final_confidence', v_final_conf,
    'ingest_status', v_ingest_status,
    'event_key', v_idem,
    'via', 'phase6_canonical'
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
