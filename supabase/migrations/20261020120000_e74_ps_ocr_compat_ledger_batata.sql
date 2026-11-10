-- =============================================================================
-- E74 — PS Reader / ledger COMPATÍVEL com OCR de produção
-- NÃO substitui batata_ingest_ocr_reservation_v2 nem v1.
-- NÃO activa Meta. Idempotente (IF NOT EXISTS / OR REPLACE de helpers novos).
-- =============================================================================

-- 1) Ledger + qty events (additivo)
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
  'E74: idempotência PS/OCR/Face. OCR v2 de produção permanece intacto; bridge grava pós-ingest.';

alter table public.commerce_ps_event_ledger enable row level security;
revoke all on table public.commerce_ps_event_ledger from public, anon, authenticated;
grant select, insert, update, delete on table public.commerce_ps_event_ledger to service_role;

create table if not exists public.commerce_ps_qty_events (
  id uuid primary key default gen_random_uuid(),
  live_id uuid not null,
  seller_id uuid not null,
  reservation_id uuid null,
  event_key text null,
  requested_qty integer not null default 1,
  outcome text null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists commerce_ps_qty_events_live_idx
  on public.commerce_ps_qty_events (live_id, created_at desc);

alter table public.commerce_ps_qty_events enable row level security;
revoke all on table public.commerce_ps_qty_events from public, anon, authenticated;
grant all on table public.commerce_ps_qty_events to service_role;

-- Unique LRR idempotency (safe if already present)
create unique index if not exists live_reservation_requests_idempotency_key_uidx
  on public.live_reservation_requests (idempotency_key)
  where idempotency_key is not null and length(trim(idempotency_key)) > 0;

-- 2) Event key helper (novo/idempotente)
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

-- 3) Bridge pós-OCR: grava ledger SEM alterar OCR v2
-- Chamado pela Edge após batata_ingest_ocr_reservation(_v2) com ok=true.
create or replace function public.batata_commerce_ps_after_ocr_ingest(
  p_live_id uuid,
  p_seller_id uuid,
  p_ocr_line_hash text,
  p_comment_id text default null,
  p_reservation_id uuid default null,
  p_outcome text default null,
  p_result jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_existing public.commerce_ps_event_ledger%rowtype;
  v_outcome text := coalesce(nullif(trim(p_outcome), ''), 'ocr_ok');
begin
  if p_live_id is null or p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  v_key := public.batata_commerce_ps_event_key(p_live_id, p_ocr_line_hash, p_comment_id);
  if v_key is null then
    return jsonb_build_object('ok', false, 'error', 'missing_event_key');
  end if;

  begin
    insert into public.commerce_ps_event_ledger (
      event_key, live_id, seller_id, reservation_id, outcome, result
    ) values (
      v_key, p_live_id, p_seller_id, p_reservation_id, v_outcome,
      coalesce(p_result, '{}'::jsonb) || jsonb_build_object('bridge', 'e74_after_ocr')
    );
  exception
    when unique_violation then
      select * into v_existing
      from public.commerce_ps_event_ledger
      where event_key = v_key;
      -- Heal reservation_id/outcome if prior claim was incomplete
      if v_existing.reservation_id is null and p_reservation_id is not null then
        update public.commerce_ps_event_ledger
        set reservation_id = p_reservation_id,
            outcome = coalesce(v_outcome, outcome),
            result = coalesce(result, '{}'::jsonb) || coalesce(p_result, '{}'::jsonb)
        where event_key = v_key;
      end if;
      return jsonb_build_object(
        'ok', true,
        'deduped', true,
        'event_key', v_key,
        'reservation_id', coalesce(v_existing.reservation_id, p_reservation_id)
      );
  end;

  return jsonb_build_object(
    'ok', true,
    'inserted', true,
    'event_key', v_key,
    'reservation_id', p_reservation_id
  );
end;
$$;

revoke all on function public.batata_commerce_ps_after_ocr_ingest(
  uuid, uuid, text, text, uuid, text, jsonb
) from public;
grant execute on function public.batata_commerce_ps_after_ocr_ingest(
  uuid, uuid, text, text, uuid, text, jsonb
) to service_role;

-- 4) Reserva PS/Face independente (não passa por OCR v2)
-- Usa motor canónico batata_reserve_with_policy quando disponível.
create or replace function public.batata_commerce_reserve_from_ps_event(
  p_live_id uuid,
  p_seller_id uuid,
  p_live_item_id uuid,
  p_requested_qty integer default 1,
  p_external_display_name text default null,
  p_external_buyer_ref text default null,
  p_buyer_id uuid default null,
  p_ocr_line_hash text default null,
  p_comment_id text default null,
  p_event_channel text default 'ps_face'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_qty int := greatest(coalesce(p_requested_qty, 1), 1);
  v_reserve jsonb;
  v_rid uuid;
  v_ledger jsonb;
begin
  if p_live_id is null or p_seller_id is null or p_live_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if v_qty < 1 or v_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;

  v_key := public.batata_commerce_ps_event_key(p_live_id, p_ocr_line_hash, p_comment_id);
  if v_key is null then
    -- synthetic key for PS without OCR hash
    v_key := 'ps:' || p_live_id::text || ':' || p_live_item_id::text || ':' ||
             coalesce(nullif(trim(p_external_buyer_ref), ''), gen_random_uuid()::text);
  end if;

  -- Claim ledger first (idempotência)
  begin
    insert into public.commerce_ps_event_ledger (event_key, live_id, seller_id, result)
    values (v_key, p_live_id, p_seller_id, jsonb_build_object('phase', 'claimed', 'channel', p_event_channel));
  exception
    when unique_violation then
      select reservation_id into v_rid
      from public.commerce_ps_event_ledger where event_key = v_key;
      return jsonb_build_object(
        'ok', true,
        'deduped', true,
        'event_key', v_key,
        'reservation_id', v_rid
      );
  end;

  -- Motor canónico (assinatura prod E73):
  -- (seller, buyer, live, live_item, qty, source, guest_session, identity_linked, notes, actor_mode)
  begin
    v_reserve := public.batata_reserve_with_policy(
      p_seller_id,
      p_buyer_id,
      p_live_id,
      p_live_item_id,
      v_qty,
      coalesce(nullif(trim(p_event_channel), ''), 'ps_face'),
      null, -- guest_session_id
      (p_buyer_id is not null), -- identity_linked
      left(trim(coalesce(p_external_display_name, '') || ' ' || coalesce(p_external_buyer_ref, '')), 200),
      'ps_face'
    );
  exception
    when undefined_function then
      update public.commerce_ps_event_ledger
      set outcome = 'error',
          result = jsonb_build_object('error', 'reserve_with_policy_missing')
      where event_key = v_key;
      return jsonb_build_object('ok', false, 'error', 'reserve_with_policy_missing');
    when others then
      update public.commerce_ps_event_ledger
      set outcome = 'error',
          result = jsonb_build_object('error', SQLERRM)
      where event_key = v_key;
      return jsonb_build_object('ok', false, 'error', SQLERRM);
  end;

  if coalesce((v_reserve->>'ok')::boolean, false) is not true then
    update public.commerce_ps_event_ledger
    set outcome = 'rejected',
        result = coalesce(v_reserve, '{}'::jsonb)
    where event_key = v_key;
    return v_reserve;
  end if;

  v_rid := nullif(v_reserve->>'request_id', '')::uuid;
  if v_rid is null then
    v_rid := nullif(v_reserve->>'reservation_id', '')::uuid;
  end if;

  update public.commerce_ps_event_ledger
  set reservation_id = v_rid,
      outcome = 'reserved',
      result = coalesce(v_reserve, '{}'::jsonb)
  where event_key = v_key;

  insert into public.commerce_ps_qty_events (
    live_id, seller_id, reservation_id, event_key, requested_qty, outcome, result
  ) values (
    p_live_id, p_seller_id, v_rid, v_key, v_qty, 'reserved', coalesce(v_reserve, '{}'::jsonb)
  );

  return jsonb_build_object(
    'ok', true,
    'event_key', v_key,
    'reservation_id', v_rid,
    'reserve', v_reserve,
    'channel', p_event_channel
  );
end;
$$;

revoke all on function public.batata_commerce_reserve_from_ps_event(
  uuid, uuid, uuid, integer, text, text, uuid, text, text, text
) from public;
grant execute on function public.batata_commerce_reserve_from_ps_event(
  uuid, uuid, uuid, integer, text, text, uuid, text, text, text
) to service_role;

notify pgrst, 'reload schema';

comment on function public.batata_commerce_ps_after_ocr_ingest is
  'E74 bridge: ledger após OCR. Não altera batata_ingest_ocr_reservation_v2.';
comment on function public.batata_commerce_reserve_from_ps_event is
  'E74: caminho PS/Face independente do OCR v2 de produção.';
