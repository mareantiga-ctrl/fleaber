-- =============================================================================
-- Phase 8 — Meta / Facebook integration (staging). PS Reader + Graph coexistence.
-- Does NOT weaken RLS or reservation policy. Graph ingest = service_role + linked Page.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Page linkage (no plaintext tokens — tokens live in Edge secrets)
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_meta_page_connections (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null,
  page_id text not null,
  page_name text null,
  ingest_enabled boolean not null default true,
  messaging_enabled boolean not null default false,
  permissions_granted jsonb not null default '[]'::jsonb,
  linked_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz null,
  unique (page_id)
);

create index if not exists commerce_meta_page_connections_seller_idx
  on public.commerce_meta_page_connections (seller_id)
  where revoked_at is null;

comment on table public.commerce_meta_page_connections is
  'Phase 8: Fleaber seller ↔ Meta Page id. Page tokens are NOT stored here.';

alter table public.commerce_meta_page_connections enable row level security;
revoke all on table public.commerce_meta_page_connections from public, anon;
grant select, insert, update on table public.commerce_meta_page_connections to authenticated;
grant all on table public.commerce_meta_page_connections to service_role;

create policy commerce_meta_page_connections_seller_select
  on public.commerce_meta_page_connections
  for select
  to authenticated
  using (seller_id = auth.uid() and revoked_at is null);

create policy commerce_meta_page_connections_seller_insert
  on public.commerce_meta_page_connections
  for insert
  to authenticated
  with check (seller_id = auth.uid());

create policy commerce_meta_page_connections_seller_update
  on public.commerce_meta_page_connections
  for update
  to authenticated
  using (seller_id = auth.uid())
  with check (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) Live ↔ Meta Live Video binding
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_meta_live_video_bindings (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null references public.lives (id) on delete cascade,
  seller_id uuid not null,
  page_id text not null,
  meta_live_video_id text not null,
  meta_post_id text null,
  created_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz null,
  unique (meta_live_video_id),
  unique (live_id)
);

create index if not exists commerce_meta_live_video_bindings_page_idx
  on public.commerce_meta_live_video_bindings (page_id, created_at desc)
  where revoked_at is null;

alter table public.commerce_meta_live_video_bindings enable row level security;
revoke all on table public.commerce_meta_live_video_bindings from public, anon;
grant select, insert, update on table public.commerce_meta_live_video_bindings to authenticated;
grant all on table public.commerce_meta_live_video_bindings to service_role;

create policy commerce_meta_live_video_bindings_seller_select
  on public.commerce_meta_live_video_bindings
  for select
  to authenticated
  using (seller_id = auth.uid() and revoked_at is null);

create policy commerce_meta_live_video_bindings_seller_write
  on public.commerce_meta_live_video_bindings
  for insert
  to authenticated
  with check (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Webhook delivery idempotency + poll cursors
-- ---------------------------------------------------------------------------
create table if not exists public.commerce_meta_webhook_deliveries (
  delivery_key text primary key,
  page_id text not null,
  seller_id uuid null,
  live_id uuid null,
  status text not null default 'claimed',
  payload jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz null
);

create index if not exists commerce_meta_webhook_deliveries_page_idx
  on public.commerce_meta_webhook_deliveries (page_id, created_at desc);

alter table public.commerce_meta_webhook_deliveries enable row level security;
revoke all on table public.commerce_meta_webhook_deliveries from public, anon, authenticated;
grant all on table public.commerce_meta_webhook_deliveries to service_role;

create table if not exists public.commerce_meta_poll_cursors (
  page_id text not null,
  live_id uuid not null,
  meta_live_video_id text not null,
  last_polled_at timestamptz null,
  last_comment_count integer null,
  primary key (page_id, live_id)
);

revoke all on table public.commerce_meta_poll_cursors from public, anon, authenticated;
grant all on table public.commerce_meta_poll_cursors to service_role;

create table if not exists public.commerce_meta_messenger_outbound_log (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null,
  page_id text not null,
  comment_id text null,
  eligible boolean not null,
  sent boolean not null default false,
  skip_reason text null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists commerce_meta_messenger_outbound_log_seller_idx
  on public.commerce_meta_messenger_outbound_log (seller_id, created_at desc);

revoke all on table public.commerce_meta_messenger_outbound_log from public, anon, authenticated;
grant all on table public.commerce_meta_messenger_outbound_log to service_role;

-- ---------------------------------------------------------------------------
-- 4) Helpers (service_role)
-- ---------------------------------------------------------------------------
create or replace function public.batata_meta_assert_service_caller()
returns void
language plpgsql
stable
as $$
begin
  if current_user::text not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'not_allowed';
  end if;
end;
$$;

revoke all on function public.batata_meta_assert_service_caller() from public;
grant execute on function public.batata_meta_assert_service_caller() to service_role;

create or replace function public.batata_meta_resolve_live_for_page(
  p_page_id text,
  p_meta_post_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_post text := nullif(trim(coalesce(p_meta_post_id, '')), '');
  v_live_id uuid;
  v_seller_id uuid;
begin
  perform public.batata_meta_assert_service_caller();
  if v_page is null then
    return jsonb_build_object('ok', false, 'error', 'missing_page_id');
  end if;

  select c.seller_id into v_seller_id
  from public.commerce_meta_page_connections c
  where c.page_id = v_page
    and c.revoked_at is null
    and c.ingest_enabled = true
  limit 1;

  if v_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'page_not_linked');
  end if;

  if v_post is not null then
    select b.live_id into v_live_id
    from public.commerce_meta_live_video_bindings b
    join public.lives l on l.id = b.live_id
    where b.page_id = v_page
      and b.revoked_at is null
      and b.meta_post_id = v_post
      and coalesce(l.status, '') not in ('ended', 'cancelled')
    order by b.created_at desc
    limit 1;
  end if;

  if v_live_id is null then
    select b.live_id into v_live_id
    from public.commerce_meta_live_video_bindings b
    join public.lives l on l.id = b.live_id
    where b.page_id = v_page
      and b.revoked_at is null
      and coalesce(l.status, '') not in ('ended', 'cancelled')
    order by b.created_at desc
    limit 1;
  end if;

  if v_live_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'no_live_binding',
      'seller_id', v_seller_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live_id,
    'seller_id', v_seller_id
  );
end;
$$;

revoke all on function public.batata_meta_resolve_live_for_page(text, text) from public;
grant execute on function public.batata_meta_resolve_live_for_page(text, text) to service_role;

create or replace function public.batata_meta_webhook_claim_delivery(
  p_delivery_key text,
  p_page_id text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := nullif(trim(coalesce(p_delivery_key, '')), '');
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_seller_id uuid;
  v_live_id uuid;
  v_res jsonb;
  v_post text;
begin
  perform public.batata_meta_assert_service_caller();
  if v_key is null or v_page is null then
    return jsonb_build_object('ok', false, 'error', 'missing_delivery_key');
  end if;

  begin
    insert into public.commerce_meta_webhook_deliveries (delivery_key, page_id, payload, status)
    values (v_key, v_page, coalesce(p_payload, '{}'::jsonb), 'claimed');
  exception
    when unique_violation then
      return jsonb_build_object('ok', true, 'duplicate', true, 'delivery_key', v_key);
  end;

  select c.seller_id into v_seller_id
  from public.commerce_meta_page_connections c
  where c.page_id = v_page
    and c.revoked_at is null
    and c.ingest_enabled = true
  limit 1;

  if v_seller_id is null then
    update public.commerce_meta_webhook_deliveries
    set status = 'rejected',
        result = jsonb_build_object('error', 'page_not_authorized'),
        processed_at = now()
    where delivery_key = v_key;
    return jsonb_build_object('ok', false, 'error', 'page_not_authorized');
  end if;

  v_post := nullif(trim(coalesce(p_payload->>'postId', p_payload->>'post_id', '')), '');
  v_res := public.batata_meta_resolve_live_for_page(v_page, v_post);
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    update public.commerce_meta_webhook_deliveries
    set seller_id = v_seller_id,
        status = 'skipped',
        result = v_res,
        processed_at = now()
    where delivery_key = v_key;
    return jsonb_build_object(
      'ok', true,
      'live_id', null,
      'seller_id', v_seller_id,
      'warning', coalesce(v_res->>'error', 'no_live')
    );
  end if;

  v_live_id := (v_res->>'live_id')::uuid;
  update public.commerce_meta_webhook_deliveries
  set seller_id = v_seller_id,
      live_id = v_live_id
  where delivery_key = v_key;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live_id,
    'seller_id', v_seller_id
  );
end;
$$;

revoke all on function public.batata_meta_webhook_claim_delivery(text, text, jsonb) from public;
grant execute on function public.batata_meta_webhook_claim_delivery(text, text, jsonb) to service_role;

create or replace function public.batata_meta_webhook_finish_delivery(
  p_delivery_key text,
  p_status text,
  p_result jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := nullif(trim(coalesce(p_delivery_key, '')), '');
begin
  perform public.batata_meta_assert_service_caller();
  if v_key is null then
    return jsonb_build_object('ok', false, 'error', 'missing_delivery_key');
  end if;
  update public.commerce_meta_webhook_deliveries
  set status = coalesce(nullif(trim(p_status), ''), 'processed'),
      result = coalesce(p_result, '{}'::jsonb),
      processed_at = timezone('utc', now())
  where delivery_key = v_key;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_meta_webhook_finish_delivery(text, text, jsonb) from public;
grant execute on function public.batata_meta_webhook_finish_delivery(text, text, jsonb) to service_role;

create or replace function public.batata_meta_poll_cursor_update(
  p_page_id text,
  p_live_id uuid,
  p_meta_live_video_id text,
  p_last_polled_at timestamptz,
  p_comment_count integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.batata_meta_assert_service_caller();
  insert into public.commerce_meta_poll_cursors (
    page_id, live_id, meta_live_video_id, last_polled_at, last_comment_count
  )
  values (
    trim(p_page_id),
    p_live_id,
    trim(p_meta_live_video_id),
    p_last_polled_at,
    p_comment_count
  )
  on conflict (page_id, live_id) do update
  set meta_live_video_id = excluded.meta_live_video_id,
      last_polled_at = excluded.last_polled_at,
      last_comment_count = excluded.last_comment_count;
end;
$$;

revoke all on function public.batata_meta_poll_cursor_update(text, uuid, text, timestamptz, integer) from public;
grant execute on function public.batata_meta_poll_cursor_update(text, uuid, text, timestamptz, integer) to service_role;

create or replace function public.batata_commerce_messenger_evaluate_outbound(
  p_seller_id uuid,
  p_page_id text,
  p_comment_id text,
  p_kind text default 'private_reply'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_page text := nullif(trim(coalesce(p_page_id, '')), '');
  v_cmt text := nullif(trim(coalesce(p_comment_id, '')), '');
  v_kind text := lower(trim(coalesce(p_kind, 'private_reply')));
  v_row public.commerce_meta_page_connections%rowtype;
begin
  perform public.batata_meta_assert_service_caller();
  if p_seller_id is null or v_page is null or v_cmt is null then
    return jsonb_build_object('eligible', false, 'reason', 'missing_params');
  end if;

  select * into v_row
  from public.commerce_meta_page_connections c
  where c.page_id = v_page
    and c.seller_id = p_seller_id
    and c.revoked_at is null
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('eligible', false, 'reason', 'page_not_linked');
  end if;

  if v_row.messaging_enabled is not true then
    return jsonb_build_object(
      'eligible', false,
      'reason', 'messaging_not_enabled',
      'note', 'Enable after App Review / pages_messaging'
    );
  end if;

  if v_kind <> 'private_reply' then
    return jsonb_build_object('eligible', false, 'reason', 'unsupported_kind');
  end if;

  if length(v_cmt) < 4 then
    return jsonb_build_object('eligible', false, 'reason', 'invalid_comment_id');
  end if;

  return jsonb_build_object(
    'eligible', true,
    'reason', null,
    'kind', v_kind
  );
end;
$$;

revoke all on function public.batata_commerce_messenger_evaluate_outbound(uuid, text, text, text) from public;
grant execute on function public.batata_commerce_messenger_evaluate_outbound(uuid, text, text, text) to service_role;

create or replace function public.batata_commerce_messenger_log_outbound(
  p_seller_id uuid,
  p_page_id text,
  p_comment_id text,
  p_eligible boolean,
  p_sent boolean,
  p_skip_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.batata_meta_assert_service_caller();
  insert into public.commerce_meta_messenger_outbound_log (
    seller_id, page_id, comment_id, eligible, sent, skip_reason
  )
  values (
    p_seller_id,
    trim(p_page_id),
    nullif(trim(coalesce(p_comment_id, '')), ''),
    coalesce(p_eligible, false),
    coalesce(p_sent, false),
    nullif(trim(coalesce(p_skip_reason, '')), '')
  );
end;
$$;

revoke all on function public.batata_commerce_messenger_log_outbound(uuid, text, text, boolean, boolean, text) from public;
grant execute on function public.batata_commerce_messenger_log_outbound(uuid, text, text, boolean, boolean, text) to service_role;

-- ---------------------------------------------------------------------------
-- 5) Graph auth path on existing ingest v2 (Page id replaces device token)
-- ---------------------------------------------------------------------------
drop function if exists public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, integer, integer, integer, text, integer, text,
  numeric, numeric, numeric, text, text, boolean, text, text
);

-- Phase 6.1 body + Phase 8 optional p_meta_page_id (service_role only)
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
  p_event_channel text default null,
  p_meta_page_id text default null
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
  v_meta_page text := nullif(trim(coalesce(p_meta_page_id, '')), '');
begin
  if v_meta_page is not null then
    perform public.batata_meta_assert_service_caller();
    select c.seller_id into v_seller_id
    from public.commerce_meta_page_connections c
    where c.page_id = v_meta_page
      and c.revoked_at is null
      and c.ingest_enabled = true
    limit 1;
    if v_seller_id is null then
      return jsonb_build_object('ok', false, 'error', 'page_not_linked');
    end if;
    v_auth := jsonb_build_object('ok', true, 'seller_id', v_seller_id, 'via', 'meta_page');
  else
    v_auth := public.batata_validate_seller_device_token(p_device_token);
    if coalesce((v_auth->>'ok')::boolean, false) is not true then
      return v_auth;
    end if;
    v_seller_id := (v_auth->>'seller_id')::uuid;
  end if;

  v_buyer_ref := nullif(trim(coalesce(p_external_buyer_ref, '')), '');
  v_intent := lower(trim(coalesce(p_parser_intent, '')));
  v_channel := coalesce(
    nullif(trim(p_event_channel), ''),
    case when v_meta_page is not null then 'graph' else 'ocr' end
  );

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

  begin
    insert into public.commerce_ps_event_ledger (event_key, live_id, seller_id, result)
    values (v_idem, p_live_id, v_seller_id, jsonb_build_object('phase', 'claimed', 'channel', v_channel));
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
  numeric, numeric, numeric, text, text, boolean, text, text, text
) from public;
grant execute on function public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, integer, integer, integer, text, integer, text,
  numeric, numeric, numeric, text, text, boolean, text, text, text
) to service_role;

notify pgrst, 'reload schema';
