-- Fleaber PS (Projecto Spy) — fila unificada cross-canal + ingest OCR Facebook.
-- Spec: docs/live-cross-channel-ingest-spec.md
-- Depende de: live_reservation_requests_batata.sql, live_ops_hotfix_batata.sql

-- ---------------------------------------------------------------------------
-- 1) Colunas ingest + idempotência
-- ---------------------------------------------------------------------------
alter table public.live_reservation_requests
  add column if not exists effective_at timestamptz,
  add column if not exists detected_at timestamptz,
  add column if not exists external_display_name text,
  add column if not exists external_buyer_ref text,
  add column if not exists chat_sequence int,
  add column if not exists avatar_phash text,
  add column if not exists ocr_raw_line text,
  add column if not exists ingest_channel text,
  add column if not exists ingest_confidence numeric(4, 3),
  add column if not exists ingest_status text,
  add column if not exists idempotency_key text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_ingest_channel_chk'
      and conrelid = 'public.live_reservation_requests'::regclass
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_ingest_channel_chk
      check (
        ingest_channel is null
        or ingest_channel in ('ocr', 'manual', 'graph', 'helper')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_ingest_status_chk'
      and conrelid = 'public.live_reservation_requests'::regclass
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_ingest_status_chk
      check (
        ingest_status is null
        or ingest_status in (
          'auto', 'needs_review', 'seller_confirmed', 'rejected'
        )
      );
  end if;
end $$;

create unique index if not exists live_reservation_requests_idempotency_uidx
  on public.live_reservation_requests (idempotency_key)
  where idempotency_key is not null;

create index if not exists live_reservation_requests_item_pending_eff_idx
  on public.live_reservation_requests (live_item_id, status, effective_at);

-- Buffer OCR por seller (override opcional)
alter table public.profiles
  add column if not exists ocr_latency_buffer_ms int not null default 3000;

-- ---------------------------------------------------------------------------
-- 2) Device tokens (agente Fleaber Reader no PC da seller)
-- ---------------------------------------------------------------------------
create table if not exists public.seller_device_tokens (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  device_id text not null,
  token_hash text not null,
  label text,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (seller_id, device_id)
);

alter table public.seller_device_tokens enable row level security;

drop policy if exists seller_device_tokens_owner_select on public.seller_device_tokens;
create policy seller_device_tokens_owner_select
  on public.seller_device_tokens
  for select
  to authenticated
  using (seller_id = auth.uid());

drop policy if exists seller_device_tokens_owner_update on public.seller_device_tokens;
create policy seller_device_tokens_owner_update
  on public.seller_device_tokens
  for update
  to authenticated
  using (seller_id = auth.uid())
  with check (seller_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) Helpers internos (prioridade §7 — não expor na UI)
-- ---------------------------------------------------------------------------
create or replace function public.batata_reservation_source_priority(p_source text)
returns int
language sql
immutable
as $$
  select case coalesce(p_source, '')
    when 'fleaber_live' then 0
    when 'helper_manual' then 1
    when 'facebook_manual' then 2
    else 3
  end;
$$;

comment on function public.batata_reservation_source_priority(text) is
  'PS tiebreak interno — menor = primeiro em cluster de ambiguidade.';

create or replace function public.batata_reservation_effective_at(
  p_source text,
  p_ingest_channel text,
  p_created_at timestamptz,
  p_detected_at timestamptz,
  p_seller_id uuid
) returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  v_buffer_ms int := 3000;
begin
  if p_source = 'fleaber_live' then
    return coalesce(p_created_at, now());
  end if;

  if p_source = 'helper_manual' then
    return coalesce(p_created_at, now());
  end if;

  if p_source = 'facebook_manual' and coalesce(p_ingest_channel, '') = 'manual' then
    return coalesce(p_created_at, now());
  end if;

  if p_detected_at is not null then
    select coalesce(p.ocr_latency_buffer_ms, 3000)
    into v_buffer_ms
    from public.profiles p
    where p.id = p_seller_id;

    return p_detected_at - make_interval(secs => greatest(v_buffer_ms, 0)::double precision / 1000.0);
  end if;

  return coalesce(p_created_at, now());
end;
$$;

-- Resolve ref_number (1..999) → live_item_id na live.
create or replace function public.batata_resolve_live_item_ref(
  p_live_id uuid,
  p_ref_number int
) returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_ref text := trim(coalesce(p_ref_number::text, ''));
begin
  if p_live_id is null or p_ref_number is null or p_ref_number < 1 then
    return null;
  end if;

  select li.id into v_item_id
  from public.live_items li
  where li.live_id = p_live_id
    and li.is_active = true
    and (
      trim(coalesce(li.ref_code, '')) = v_ref
      or trim(coalesce(li.ref_code, '')) ~ ('^0*' || v_ref || '$')
    )
  order by li.created_at asc
  limit 1;

  if v_item_id is not null then
    return v_item_id;
  end if;

  select li.id into v_item_id
  from public.live_items li
  where li.live_id = p_live_id
    and trim(coalesce(li.ref_code, '')) = v_ref
  order by li.is_active desc, li.created_at asc
  limit 1;

  if v_item_id is not null then
    return v_item_id;
  end if;

  select x.id into v_item_id
  from (
    select li.id, row_number() over (order by li.created_at asc)::int as ord
    from public.live_items li
    where li.live_id = p_live_id
      and coalesce(li.status, '') <> 'sold'
  ) x
  where x.ord = p_ref_number
  limit 1;

  return v_item_id;
end;
$$;

revoke all on function public.batata_resolve_live_item_ref(uuid, int) from public;
grant execute on function public.batata_resolve_live_item_ref(uuid, int)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Fila unificada — recompact (todos os sources pending)
-- ---------------------------------------------------------------------------
create or replace function public.batata_recompact_reservation_queue(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
  v_ambiguity_secs int := 10;
begin
  if p_live_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_item_id');
  end if;

  with base as (
    select
      r.id,
      coalesce(r.effective_at, r.created_at) as eff,
      public.batata_reservation_source_priority(r.source) as src_pri,
      r.created_at,
      coalesce(r.chat_sequence, 2147483647) as chat_seq
    from public.live_reservation_requests r
    where r.live_item_id = p_live_item_id
      and r.status = 'pending'
      and coalesce(r.ingest_status, '') <> 'rejected'
  ),
  clustered as (
    select
      b.*,
      lag(b.eff) over (order by b.eff, b.created_at, b.id) as prev_eff
    from base b
  ),
  with_break as (
    select
      c.*,
      case
        when c.prev_eff is null then 1
        when extract(
          epoch from (c.eff - c.prev_eff)
        ) > v_ambiguity_secs then 1
        else 0
      end as is_new_cluster
    from clustered c
  ),
  numbered as (
    select
      wb.*,
      sum(wb.is_new_cluster) over (
        order by wb.eff, wb.created_at, wb.id
        rows between unbounded preceding and current row
      ) as cluster_id
    from with_break wb
  ),
  cluster_bounds as (
    select cluster_id, min(eff) as cluster_eff
    from numbered
    group by cluster_id
  ),
  ranked as (
    select
      c.id,
      row_number() over (
        order by
          cb.cluster_eff,
          c.src_pri,
          c.eff,
          c.chat_seq,
          c.created_at,
          c.id
      )::int as new_pos
    from numbered c
    join cluster_bounds cb on cb.cluster_id = c.cluster_id
  )
  update public.live_reservation_requests r
  set
    queue_position = ranked.new_pos,
    updated_at = now()
  from ranked
  where r.id = ranked.id
    and coalesce(r.queue_position, -1) is distinct from ranked.new_pos;

  get diagnostics v_updated = row_count;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', p_live_item_id,
    'reassigned', v_updated
  );
end;
$$;

revoke all on function public.batata_recompact_reservation_queue(uuid) from public;
grant execute on function public.batata_recompact_reservation_queue(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Trigger BEFORE INSERT — effective_at + defaults
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    new.requested_qty := greatest(coalesce(new.requested_qty, 1), 1);

    if new.source = 'facebook_manual' and new.ingest_channel is null then
      new.ingest_channel := 'manual';
    end if;

    if new.source = 'helper_manual' and new.ingest_channel is null then
      new.ingest_channel := 'helper';
    end if;

    if new.source = 'fleaber_live' and new.ingest_channel is null then
      new.ingest_channel := null;
    end if;

    if new.effective_at is null then
      new.effective_at := public.batata_reservation_effective_at(
        new.source,
        new.ingest_channel,
        coalesce(new.created_at, now()),
        new.detected_at,
        new.seller_id
      );
    end if;

    if new.source = 'facebook_manual'
      and new.ingest_channel = 'ocr'
      and new.ingest_status is null then
      if coalesce(new.ingest_confidence, 0) >= 0.85 then
        new.ingest_status := 'auto';
      else
        new.ingest_status := 'needs_review';
      end if;
    end if;

    if new.source = 'facebook_manual'
      and new.ingest_channel = 'manual'
      and new.ingest_status is null then
      new.ingest_status := 'seller_confirmed';
    end if;

    -- Posição atribuída pelo recompact pós-insert.
    new.queue_position := null;
  end if;

  if new.status = 'pending' and new.expires_at is null then
    new.expires_at := now() + interval '45 minutes';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.batata_live_reservation_after_insert_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'pending'
    and coalesce(new.ingest_status, '') <> 'rejected' then
    perform public.batata_recompact_reservation_queue(new.live_item_id);
  end if;
  return new;
end;
$$;

drop trigger if exists batata_live_reservation_after_insert_queue_tg
  on public.live_reservation_requests;
create trigger batata_live_reservation_after_insert_queue_tg
  after insert on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_after_insert_queue();

-- ---------------------------------------------------------------------------
-- 6) Device token RPCs (seller autenticada)
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_seller_device_token(
  p_device_id text,
  p_label text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_device text := trim(coalesce(p_device_id, ''));
  v_token text;
  v_hash text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if length(v_device) < 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_id');
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (seller_id, device_id, token_hash, label)
  values (v_uid, v_device, v_hash, nullif(trim(coalesce(p_label, '')), ''))
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    revoked_at = null,
    created_at = now();

  return jsonb_build_object(
    'ok', true,
    'device_id', v_device,
    'token', v_token,
    'label', nullif(trim(coalesce(p_label, '')), '')
  );
end;
$$;

revoke all on function public.batata_create_seller_device_token(text, text) from public;
grant execute on function public.batata_create_seller_device_token(text, text)
  to authenticated;

create or replace function public.batata_revoke_seller_device_token(p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  update public.seller_device_tokens
  set revoked_at = now()
  where seller_id = v_uid
    and device_id = trim(coalesce(p_device_id, ''));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_revoke_seller_device_token(text) from public;
grant execute on function public.batata_revoke_seller_device_token(text)
  to authenticated;

-- Valida token do agente OCR (service_role / edge function).
create or replace function public.batata_validate_seller_device_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_row public.seller_device_tokens%rowtype;
begin
  if trim(coalesce(p_token, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_token');
  end if;

  v_hash := encode(extensions.digest(trim(p_token), 'sha256'), 'hex');

  select * into v_row
  from public.seller_device_tokens t
  where t.token_hash = v_hash
    and t.revoked_at is null
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_token');
  end if;

  return jsonb_build_object(
    'ok', true,
    'seller_id', v_row.seller_id,
    'device_id', v_row.device_id
  );
end;
$$;

revoke all on function public.batata_validate_seller_device_token(text) from public;
grant execute on function public.batata_validate_seller_device_token(text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7) Ingest OCR + confirmação seller
-- ---------------------------------------------------------------------------
create or replace function public.batata_ingest_ocr_reservation(
  p_device_token text,
  p_live_id uuid,
  p_ref_number int,
  p_external_display_name text,
  p_external_buyer_ref text,
  p_ocr_raw_line text,
  p_ocr_line_hash text,
  p_detected_at timestamptz,
  p_chat_sequence int default null,
  p_avatar_phash text default null,
  p_ingest_confidence numeric default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_item_id uuid;
  v_idem text;
  v_existing uuid;
  v_row public.live_reservation_requests%rowtype;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if coalesce(v_live.seller_id, v_live.vendedor_id) is distinct from v_seller_id then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_item_id := public.batata_resolve_live_item_ref(p_live_id, p_ref_number);
  if v_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'item_ref_not_found');
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
    idempotency_key
  ) values (
    p_live_id,
    v_item_id,
    v_seller_id,
    null,
    1,
    'facebook_manual',
    'pending',
    'ps:ocr',
    p_detected_at,
    nullif(trim(coalesce(p_external_display_name, '')), ''),
    nullif(trim(coalesce(p_external_buyer_ref, '')), ''),
    p_chat_sequence,
    nullif(trim(coalesce(p_avatar_phash, '')), ''),
    nullif(trim(coalesce(p_ocr_raw_line, '')), ''),
    'ocr',
    p_ingest_confidence,
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
    'effective_at', v_row.effective_at
  );
end;
$$;

revoke all on function public.batata_ingest_ocr_reservation(
  text, uuid, int, text, text, text, text, timestamptz, int, text, numeric
) from public;
grant execute on function public.batata_ingest_ocr_reservation(
  text, uuid, int, text, text, text, text, timestamptz, int, text, numeric
) to service_role;

create or replace function public.batata_confirm_ps_reservation(
  p_request_id uuid,
  p_action text,
  p_ref_number int default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
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
    if p_ref_number is null or p_ref_number < 1 then
      return jsonb_build_object('ok', false, 'error', 'invalid_ref');
    end if;
    v_item_id := public.batata_resolve_live_item_ref(v_req.live_id, p_ref_number);
    if v_item_id is null then
      return jsonb_build_object('ok', false, 'error', 'item_ref_not_found');
    end if;
    update public.live_reservation_requests
    set
      live_item_id = v_item_id,
      ingest_status = 'seller_confirmed',
      notes = coalesce(notes || ' | ', '') || ('ps:correct_ref=' || p_ref_number::text),
      updated_at = now()
    where id = v_req.id;
    perform public.batata_recompact_reservation_queue(v_item_id);
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
    return jsonb_build_object('ok', true, 'action', 'correct_ref', 'live_item_id', v_item_id);
  end if;

  update public.live_reservation_requests
  set
    ingest_status = 'seller_confirmed',
    notes = coalesce(notes || ' | ', '') || 'ps:confirmed',
    updated_at = now()
  where id = v_req.id;

  perform public.batata_recompact_reservation_queue(v_req.live_item_id);

  return jsonb_build_object('ok', true, 'action', 'confirm');
end;
$$;

revoke all on function public.batata_confirm_ps_reservation(uuid, text, int) from public;
grant execute on function public.batata_confirm_ps_reservation(uuid, text, int)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8) FOMO Hub — fila unificada (todos pending)
-- ---------------------------------------------------------------------------
create or replace function public.batata_hub_live_fomo_snapshot(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_live public.hub_lives_public%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_row record;
  v_stock jsonb;
  v_pending int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select * into v_live
  from public.hub_lives_public hl
  where hl.id = p_live_id;

  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  for v_row in
    select li.id as live_item_id, li.status as item_status
    from public.hub_live_items_public li
    where li.live_id = p_live_id
    order by li.is_active desc, li.created_at asc
  loop
    v_stock := public.batata_live_item_stock(v_row.live_item_id);

    select coalesce(count(*)::int, 0) into v_pending
    from public.live_reservation_requests r
    where r.live_item_id = v_row.live_item_id
      and r.status = 'pending'
      and coalesce(r.ingest_status, '') <> 'rejected';

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'live_item_id', v_row.live_item_id,
      'status', coalesce(v_row.item_status, 'unknown'),
      'available_qty', coalesce((v_stock->>'available_qty')::int, 0),
      'pending_queue_count', v_pending,
      'is_last_unit',
        coalesce((v_stock->>'total_qty')::int, 1) >= 2
        and coalesce((v_stock->>'available_qty')::int, 0) = 1,
      'display_reserved_qty',
        coalesce((v_stock->>'reserved_accepted_qty')::int, 0)
        + coalesce((v_stock->>'pending_bag_qty')::int, 0)
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live.id,
    'viewer_count', coalesce(v_live.viewer_count, 0),
    'live_status', v_live.status,
    'is_active', v_live.is_active,
    'items', v_items
  );
end;
$$;

revoke all on function public.batata_hub_live_fomo_snapshot(uuid) from public;
grant execute on function public.batata_hub_live_fomo_snapshot(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
