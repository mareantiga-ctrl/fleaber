-- SEC-008 (parcial) + SEC-009 + SEC-010 + SEC-020 + SEC-021
-- Staging 2026-08-04 — BATATA (não toca Stripe webhook/checkout amounts/profiles PII)
--
-- SEC-009/010: RPCs internas de rifa — só service_role (chamadas aninhadas DEFINER OK)
-- SEC-020: rate limit mensagens sistema + revoke broadcast rifa directo do cliente
-- SEC-021: recompact/recompute só seller/staff OU participante da fila OU service_role
-- SEC-008: rate limit claim PS por device (código 6 dígitos mantém-se — residual documentado)

-- =============================================================================
-- Tabelas de rate limit (idempotente)
-- =============================================================================

create table if not exists public.batata_rpc_rate_limits (
  uid uuid not null,
  rpc text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (uid, rpc, window_start)
);

create table if not exists public.batata_anon_rate_limits (
  rate_key text not null,
  rpc text not null,
  window_start timestamptz not null,
  hits int not null default 0,
  primary key (rate_key, rpc, window_start)
);

-- =============================================================================
-- SEC-009 — create_raffle_prize_order: sem EXECUTE authenticated
-- =============================================================================

revoke all on function public.batata_create_raffle_prize_order(uuid, uuid, int) from public, anon, authenticated;
grant execute on function public.batata_create_raffle_prize_order(uuid, uuid, int) to service_role;

-- =============================================================================
-- SEC-010 — award_live_raffle_tickets: sem EXECUTE authenticated
-- =============================================================================

revoke all on function public.batata_award_live_raffle_tickets(uuid, uuid, text, int, text, jsonb) from public, anon, authenticated;
grant execute on function public.batata_award_live_raffle_tickets(uuid, uuid, text, int, text, jsonb) to service_role;

-- Broadcast rifa: só via RPCs DEFINER internas (join/share/tip) — não do cliente
revoke all on function public.batata_live_raffle_social_broadcast(uuid, text) from public, anon, authenticated;
grant execute on function public.batata_live_raffle_social_broadcast(uuid, text) to service_role;

-- =============================================================================
-- SEC-020 — system message: auth + body cap + rate limit (60/h)
-- Mantém comprador/vendedor (FOMO, saco, studio) — não restringe a seller.
-- =============================================================================

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
  v_live public.lives%rowtype;
  v_body text := trim(coalesce(p_body, ''));
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

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_live_system_message', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 60 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    v_uid,
    'system',
    v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text) from public, anon, authenticated;
grant execute on function public.batata_live_system_message(uuid, text, text) to authenticated, service_role;

-- =============================================================================
-- SEC-021 helper — pode tocar ops de fila neste live_item?
-- =============================================================================

create or replace function public.batata_can_ops_live_item(p_live_item_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_seller uuid;
begin
  if v_role = 'service_role' then
    return true;
  end if;
  if v_uid is null or p_live_item_id is null then
    return false;
  end if;

  select coalesce(l.seller_id, l.vendedor_id)
  into v_seller
  from public.live_items li
  join public.lives l on l.id = li.live_id
  where li.id = p_live_item_id;

  if v_seller is null then
    return false;
  end if;

  if v_seller = v_uid then
    return true;
  end if;

  if public.batata_staff_has_permission(v_seller, 'can_manage_reservations') then
    return true;
  end if;

  -- Participante da fila deste artigo (inclui rejected após bag_remove)
  if exists (
    select 1
    from public.live_reservation_requests r
    where r.live_item_id = p_live_item_id
      and r.buyer_id = v_uid
  ) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.batata_can_ops_live_item(uuid) from public, anon, authenticated;
grant execute on function public.batata_can_ops_live_item(uuid) to authenticated, service_role;

-- =============================================================================
-- SEC-021 — recompact (corpo = ps_recompact_window_hotfix + authz)
-- =============================================================================

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

  if not public.batata_can_ops_live_item(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
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
  with_lag as (
    select
      b.*,
      lag(b.eff) over (order by b.eff, b.created_at, b.id) as prev_eff
    from base b
  ),
  with_break as (
    select
      w.*,
      case
        when w.prev_eff is null then 1
        when extract(epoch from (w.eff - w.prev_eff)) > v_ambiguity_secs then 1
        else 0
      end as is_new_cluster
    from with_lag w
  ),
  clustered as (
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
    from clustered
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
    from clustered c
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

revoke all on function public.batata_recompact_reservation_queue(uuid) from public, anon, authenticated;
grant execute on function public.batata_recompact_reservation_queue(uuid) to authenticated, service_role;

-- =============================================================================
-- SEC-021 — recompute status com authz (corpo = live_ops_hotfix)
-- =============================================================================

create or replace function public.batata_recompute_live_item_status(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_stock jsonb;
  v_total int;
  v_available int;
  v_blocked int;
  v_reserved int;
  v_converted int;
  v_next_status text;
begin
  if not public.batata_can_ops_live_item(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  select * into v_li
  from public.live_items
  where id = p_live_item_id
  for update;

  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  v_stock := public.batata_live_item_stock(p_live_item_id);
  if coalesce((v_stock->>'ok')::boolean, false) is not true then
    return v_stock;
  end if;

  v_total := coalesce((v_stock->>'total_qty')::int, 1);
  v_available := coalesce((v_stock->>'available_qty')::int, 0);
  v_blocked := coalesce((v_stock->>'blocked_qty')::int, 0);
  v_reserved := coalesce((v_stock->>'reserved_accepted_qty')::int, 0);
  v_converted := coalesce((v_stock->>'sold_converted_qty')::int, 0);

  v_next_status := case
    when v_converted >= greatest(v_total, 1) then 'sold'
    when v_reserved >= greatest(v_total, 1) then 'reserved_full'
    when v_reserved > 0 then 'reserved_partial'
    when v_blocked > 0 and v_available <= 0 then 'reserved_full'
    else 'available'
  end;

  if coalesce(v_li.status, '') is distinct from v_next_status then
    update public.live_items
    set status = v_next_status, updated_at = now()
    where id = v_li.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'item_status', v_next_status,
    'total_qty', v_total,
    'available_qty', v_available,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved
  );
end;
$$;

revoke all on function public.batata_recompute_live_item_status(uuid) from public, anon, authenticated;
grant execute on function public.batata_recompute_live_item_status(uuid) to authenticated, service_role;

-- =============================================================================
-- SEC-008 parcial — claim pairing: rate limit por device (40/hora)
-- =============================================================================

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
  v_device text := coalesce(nullif(trim(coalesce(p_device_id, '')), ''), 'ps-reader-pc');
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_rate_key text := 'ps_claim:' || lower(v_device);
begin
  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 40 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

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

revoke all on function public.batata_ps_claim_pairing(text, text, text) from public, anon, authenticated;
grant execute on function public.batata_ps_claim_pairing(text, text, text) to service_role;

-- Garantir que anon/PUBLIC não ficam com EXECUTE residual (Supabase)
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'batata_create_raffle_prize_order',
        'batata_award_live_raffle_tickets',
        'batata_live_raffle_social_broadcast',
        'batata_ps_claim_pairing'
      )
  loop
    execute format('revoke all on function %s from public', r.sig);
    execute format('revoke all on function %s from anon', r.sig);
    execute format('revoke all on function %s from authenticated', r.sig);
  end loop;
end $$;

grant execute on function public.batata_create_raffle_prize_order(uuid, uuid, int) to service_role;
grant execute on function public.batata_award_live_raffle_tickets(uuid, uuid, text, int, text, jsonb) to service_role;
grant execute on function public.batata_live_raffle_social_broadcast(uuid, text) to service_role;
grant execute on function public.batata_ps_claim_pairing(text, text, text) to service_role;

notify pgrst, 'reload schema';
