-- Fleaber PS Reader v2 — pairing, refs alfanuméricas, contexto live, heartbeat.
-- Depende de: live_cross_channel_ingest_batata.sql
-- Spec: docs/ps/PLAN.md

-- ---------------------------------------------------------------------------
-- 1) Slot público opcional por artigo (anunciado «comenta 1»)
-- ---------------------------------------------------------------------------
alter table public.live_items
  add column if not exists public_slot int;

comment on column public.live_items.public_slot is
  'Código público anunciado na live (ex. 1, 2). NULL = ordinal no catálogo.';

-- ---------------------------------------------------------------------------
-- 2) Confianças separadas + metadados parser
-- ---------------------------------------------------------------------------
alter table public.live_reservation_requests
  add column if not exists ocr_confidence numeric(4, 3),
  add column if not exists parser_confidence numeric(4, 3),
  add column if not exists item_match_confidence numeric(4, 3),
  add column if not exists identity_confidence numeric(4, 3),
  add column if not exists resolved_ref_slug text,
  add column if not exists resolved_match_type text,
  add column if not exists parser_intent text,
  add column if not exists device_id text;

-- ---------------------------------------------------------------------------
-- 3) Emparelhamento PS (código 6 dígitos)
-- ---------------------------------------------------------------------------
create table if not exists public.ps_pairing_sessions (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  live_id uuid not null references public.lives (id) on delete cascade,
  code text not null,
  device_token_plain text,
  device_id_hint text,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_device_id text,
  created_at timestamptz not null default now(),
  constraint ps_pairing_sessions_code_len check (char_length(code) = 6)
);

create unique index if not exists ps_pairing_sessions_code_open_uidx
  on public.ps_pairing_sessions (code)
  where claimed_at is null;

create index if not exists ps_pairing_sessions_seller_live_idx
  on public.ps_pairing_sessions (seller_id, live_id, created_at desc);

alter table public.ps_pairing_sessions enable row level security;

drop policy if exists ps_pairing_sessions_owner_select on public.ps_pairing_sessions;
create policy ps_pairing_sessions_owner_select
  on public.ps_pairing_sessions
  for select
  to authenticated
  using (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 4) Heartbeat Reader
-- ---------------------------------------------------------------------------
create table if not exists public.ps_reader_heartbeats (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  live_id uuid references public.lives (id) on delete set null,
  device_id text not null,
  status text not null default 'online',
  app_version text,
  last_error text,
  roi_ok boolean,
  paired_at timestamptz,
  last_seen_at timestamptz not null default now(),
  unique (seller_id, device_id)
);

create index if not exists ps_reader_heartbeats_live_idx
  on public.ps_reader_heartbeats (live_id, last_seen_at desc);

alter table public.ps_reader_heartbeats enable row level security;

drop policy if exists ps_reader_heartbeats_owner_select on public.ps_reader_heartbeats;
create policy ps_reader_heartbeats_owner_select
  on public.ps_reader_heartbeats
  for select
  to authenticated
  using (
    seller_id = auth.uid()
    or public.batata_staff_has_permission(seller_id, 'can_view_live_dashboard')
  );

-- ---------------------------------------------------------------------------
-- 5) Resolver referência v2 (alfanumérica + slot + título)
-- ---------------------------------------------------------------------------
create or replace function public.batata_resolve_live_item_ref_v2(
  p_live_id uuid,
  p_ref_slug text default null,
  p_public_slot int default null,
  p_ref_number int default null,
  p_title_hint text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text;
  v_item_id uuid;
  v_match_type text;
  v_conf numeric(4, 3) := 0;
  v_title_norm text;
  v_count int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  -- 1) Referência completa exacta (normalizada)
  if nullif(trim(coalesce(p_ref_slug, '')), '') is not null then
    v_norm := public.batata_normalize_ref(p_ref_slug);

    if v_norm <> '' then
      select li.id into v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and public.batata_normalize_ref(li.ref_code) = v_norm
        and coalesce(li.status, '') <> 'sold'
      order by li.is_active desc, li.created_at asc
      limit 1;

      if v_item_id is not null then
        return jsonb_build_object(
          'ok', true,
          'live_item_id', v_item_id,
          'match_type', 'ref_exact',
          'confidence', 0.98,
          'resolved_ref_slug', v_norm
        );
      end if;

      -- Display exact (case-insensitive, com #)
      select li.id into v_item_id
      from public.live_items li
      where li.live_id = p_live_id
        and lower(trim(coalesce(li.ref_code, ''))) = lower(trim(p_ref_slug))
        and coalesce(li.status, '') <> 'sold'
      order by li.is_active desc, li.created_at asc
      limit 1;

      if v_item_id is not null then
        return jsonb_build_object(
          'ok', true,
          'live_item_id', v_item_id,
          'match_type', 'ref_display',
          'confidence', 0.96,
          'resolved_ref_slug', v_norm
        );
      end if;
    end if;
  end if;

  -- 2) Slot público exacto (coluna ou legado ref_number)
  if coalesce(p_public_slot, p_ref_number) is not null
     and coalesce(p_public_slot, p_ref_number) >= 1 then
    select li.id into v_item_id
    from public.live_items li
    where li.live_id = p_live_id
      and li.public_slot = coalesce(p_public_slot, p_ref_number)
      and coalesce(li.status, '') <> 'sold'
    order by li.is_active desc, li.created_at asc
    limit 1;

    if v_item_id is not null then
      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'match_type', 'public_slot',
        'confidence', 0.94,
        'resolved_ref_slug', coalesce(p_public_slot, p_ref_number)::text
      );
    end if;

    -- Ordinal catálogo (posição N)
    select x.id into v_item_id
    from (
      select
        li.id,
        row_number() over (order by li.created_at asc)::int as ord
      from public.live_items li
      where li.live_id = p_live_id
        and coalesce(li.status, '') <> 'sold'
    ) x
    where x.ord = coalesce(p_public_slot, p_ref_number)
    limit 1;

    if v_item_id is not null then
      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'match_type', 'catalog_ordinal',
        'confidence', 0.88,
        'resolved_ref_slug', coalesce(p_public_slot, p_ref_number)::text
      );
    end if;
  end if;

  -- 3) Título único (hint)
  if nullif(trim(coalesce(p_title_hint, '')), '') is not null then
    v_title_norm := lower(regexp_replace(trim(p_title_hint), '\s+', ' ', 'g'));

    select count(*)::int, min(li.id)
    into v_count, v_item_id
    from public.live_items li
    where li.live_id = p_live_id
      and coalesce(li.status, '') <> 'sold'
      and lower(trim(coalesce(li.title, ''))) like '%' || v_title_norm || '%';

    if v_count = 1 and v_item_id is not null then
      return jsonb_build_object(
        'ok', true,
        'live_item_id', v_item_id,
        'match_type', 'title_unique',
        'confidence', 0.75,
        'resolved_ref_slug', v_title_norm
      );
    end if;

    if v_count > 1 then
      return jsonb_build_object(
        'ok', false,
        'error', 'ambiguous_title',
        'match_count', v_count
      );
    end if;
  end if;

  return jsonb_build_object('ok', false, 'error', 'item_not_found');
end;
$$;

revoke all on function public.batata_resolve_live_item_ref_v2(uuid, text, int, int, text) from public;
grant execute on function public.batata_resolve_live_item_ref_v2(uuid, text, int, int, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Contexto live para parser PS
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_live_context(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_live public.lives%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_active uuid;
  v_ord int := 0;
  v_row record;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  select li.id into v_active
  from public.live_items li
  where li.live_id = p_live_id and li.is_active = true
  order by li.updated_at desc nulls last
  limit 1;

  for v_row in
    select
      li.id,
      li.ref_code,
      li.title,
      li.is_active,
      li.public_slot,
      li.quantity,
      li.status,
      li.clothing_size,
      li.photo_url,
      public.batata_normalize_ref(li.ref_code) as ref_norm,
      row_number() over (order by li.created_at asc)::int as catalog_ord
    from public.live_items li
    where li.live_id = p_live_id
      and coalesce(li.status, '') <> 'sold'
    order by li.created_at asc
  loop
    v_ord := v_ord + 1;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'live_item_id', v_row.id,
      'ref_code', v_row.ref_code,
      'ref_norm', v_row.ref_norm,
      'title', v_row.title,
      'is_active', coalesce(v_row.is_active, false),
      'public_slot', coalesce(v_row.public_slot, v_row.catalog_ord),
      'catalog_ordinal', v_row.catalog_ord,
      'quantity', coalesce(v_row.quantity, 1),
      'status', coalesce(v_row.status, 'available'),
      'variant', nullif(trim(coalesce(v_row.clothing_size, '')), '')
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live.id,
    'live_title', coalesce(v_live.title, 'Live'),
    'live_status', v_live.status,
    'seller_id', coalesce(v_live.seller_id, v_live.vendedor_id),
    'active_item_id', v_active,
    'items', v_items
  );
end;
$$;

revoke all on function public.batata_ps_live_context(uuid) from public;
grant execute on function public.batata_ps_live_context(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) Criar emparelhamento (Studio)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_create_pairing(
  p_live_id uuid,
  p_device_id_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_live public.lives%rowtype;
  v_code text;
  v_token text;
  v_hash text;
  v_device text := coalesce(nullif(trim(p_device_id_hint), ''), 'ps-reader-pc');
  v_attempt int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if coalesce(v_live.seller_id, v_live.vendedor_id) is distinct from v_uid
     and not public.batata_staff_has_permission(
       coalesce(v_live.seller_id, v_live.vendedor_id),
       'can_manage_reservations'
     ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.ps_pairing_sessions s
      where s.code = v_code
        and s.claimed_at is null
        and s.expires_at > now()
    );
    exit when v_attempt > 20;
  end loop;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (seller_id, device_id, token_hash, label)
  values (
    v_uid,
    v_device,
    v_hash,
    'PS Reader ' || to_char(now(), 'YYYY-MM-DD HH24:MI')
  )
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    revoked_at = null,
    created_at = now();

  insert into public.ps_pairing_sessions (
    seller_id, live_id, code, device_token_plain, device_id_hint, expires_at
  ) values (
    v_uid,
    p_live_id,
    v_code,
    v_token,
    v_device,
    now() + interval '10 minutes'
  );

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expires_at', (now() + interval '10 minutes'),
    'live_id', p_live_id,
    'live_title', coalesce(v_live.title, 'Live'),
    'device_id', v_device
  );
end;
$$;

revoke all on function public.batata_ps_create_pairing(uuid, text) from public;
grant execute on function public.batata_ps_create_pairing(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8) Claim emparelhamento (Edge / anon com código)
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_claim_pairing(
  p_code text,
  p_device_id text,
  p_app_version text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ps_pairing_sessions%rowtype;
  v_ctx jsonb;
  v_supabase_url text := current_setting('app.settings.supabase_url', true);
begin
  select * into v_row
  from public.ps_pairing_sessions s
  where s.code = trim(coalesce(p_code, ''))
    and s.claimed_at is null
    and s.expires_at > now()
  for update skip locked
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_or_expired_code');
  end if;

  update public.ps_pairing_sessions
  set
    claimed_at = now(),
    claimed_device_id = nullif(trim(coalesce(p_device_id, '')), '')
  where id = v_row.id;

  v_ctx := public.batata_ps_live_context(v_row.live_id);

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, paired_at, last_seen_at
  ) values (
    v_row.seller_id,
    v_row.live_id,
    coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint, 'ps-reader-pc'),
    'paired',
    nullif(trim(coalesce(p_app_version, '')), ''),
    now(),
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = excluded.live_id,
    status = 'paired',
    app_version = excluded.app_version,
    paired_at = now(),
    last_seen_at = now();

  return jsonb_build_object(
    'ok', true,
    'live_id', v_row.live_id,
    'device_token', v_row.device_token_plain,
    'device_id', coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint),
    'seller_id', v_row.seller_id,
    'live_context', v_ctx
  );
end;
$$;

revoke all on function public.batata_ps_claim_pairing(text, text, text) from public;
grant execute on function public.batata_ps_claim_pairing(text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 9) Heartbeat
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_reader_heartbeat(
  p_device_token text,
  p_live_id uuid,
  p_device_id text,
  p_status text default 'online',
  p_app_version text default null,
  p_last_error text default null,
  p_roi_ok boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, last_error, roi_ok, last_seen_at
  ) values (
    v_seller_id,
    p_live_id,
    trim(coalesce(p_device_id, '')),
    coalesce(nullif(trim(p_status), ''), 'online'),
    nullif(trim(coalesce(p_app_version, '')), ''),
    nullif(trim(coalesce(p_last_error, '')), ''),
    p_roi_ok,
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = coalesce(excluded.live_id, ps_reader_heartbeats.live_id),
    status = excluded.status,
    app_version = coalesce(excluded.app_version, ps_reader_heartbeats.app_version),
    last_error = excluded.last_error,
    roi_ok = excluded.roi_ok,
    last_seen_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_ps_reader_heartbeat(text, uuid, text, text, text, text, boolean) from public;
grant execute on function public.batata_ps_reader_heartbeat(text, uuid, text, text, text, text, boolean)
  to service_role;

-- ---------------------------------------------------------------------------
-- 10) Ingest OCR v2
-- ---------------------------------------------------------------------------
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
  v_row public.live_reservation_requests%rowtype;
  v_qty int;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;
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

  if v_item_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'needs_review_no_item',
      'ingest_status', 'needs_review',
      'confidence', v_final_conf
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
    nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
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
    'duplicate', false,
    'request_id', v_row.id,
    'live_item_id', v_row.live_item_id,
    'queue_position', v_row.queue_position,
    'ingest_status', v_row.ingest_status,
    'effective_at', v_row.effective_at,
    'match_type', v_match_type,
    'final_confidence', v_final_conf
  );
end;
$$;

revoke all on function public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, int, int, int, text, int, text,
  numeric, numeric, numeric, text, text, boolean
) from public;
grant execute on function public.batata_ingest_ocr_reservation_v2(
  text, uuid, text, text, text, text, timestamptz,
  text, int, int, int, text, int, text,
  numeric, numeric, numeric, text, text, boolean
) to service_role;

-- Confirm v2 com ref_slug
create or replace function public.batata_confirm_ps_reservation_v2(
  p_request_id uuid,
  p_action text,
  p_ref_slug text default null,
  p_public_slot int default null,
  p_requested_qty int default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_resolve jsonb;
  v_item_id uuid;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if not (
    auth.uid() = v_req.seller_id
    or public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if p_action not in ('confirm', 'reject', 'correct_ref') then
    return jsonb_build_object('ok', false, 'error', 'invalid_action');
  end if;

  if p_action = 'reject' then
    update public.live_reservation_requests
    set
      status = 'rejected',
      ingest_status = 'rejected',
      notes = coalesce(notes || ' | ', '') || 'ps:rejected',
      updated_at = now()
    where id = v_req.id;

    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
    return jsonb_build_object('ok', true, 'action', 'reject');
  end if;

  if p_action = 'correct_ref' then
    v_resolve := public.batata_resolve_live_item_ref_v2(
      v_req.live_id,
      p_ref_slug,
      p_public_slot,
      null,
      null
    );
    if coalesce((v_resolve->>'ok')::boolean, false) is not true then
      return jsonb_build_object(
        'ok', false,
        'error', coalesce(v_resolve->>'error', 'item_not_found')
      );
    end if;
    v_item_id := (v_resolve->>'live_item_id')::uuid;

    update public.live_reservation_requests
    set
      live_item_id = v_item_id,
      requested_qty = greatest(coalesce(p_requested_qty, requested_qty, 1), 1),
      ingest_status = 'seller_confirmed',
      resolved_ref_slug = coalesce(p_ref_slug, p_public_slot::text),
      resolved_match_type = v_resolve->>'match_type',
      notes = coalesce(notes || ' | ', '') || 'ps:correct_ref',
      updated_at = now()
    where id = v_req.id;

    perform public.batata_recompact_reservation_queue(v_item_id);
    if v_item_id is distinct from v_req.live_item_id then
      perform public.batata_recompact_reservation_queue(v_req.live_item_id);
    end if;
    return jsonb_build_object('ok', true, 'action', 'correct_ref', 'live_item_id', v_item_id);
  end if;

  update public.live_reservation_requests
  set
    ingest_status = 'seller_confirmed',
    requested_qty = greatest(coalesce(p_requested_qty, requested_qty, 1), 1),
    notes = coalesce(notes || ' | ', '') || 'ps:confirmed',
    updated_at = now()
  where id = v_req.id;

  perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  return jsonb_build_object('ok', true, 'action', 'confirm');
end;
$$;

revoke all on function public.batata_confirm_ps_reservation_v2(uuid, text, text, int, int) from public;
grant execute on function public.batata_confirm_ps_reservation_v2(uuid, text, text, int, int)
  to authenticated;

notify pgrst, 'reload schema';
