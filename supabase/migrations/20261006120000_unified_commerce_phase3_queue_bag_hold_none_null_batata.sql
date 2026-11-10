-- BATATA 2026-10-06 — Phase 3 final: bag_hold_none never in approval queue.
-- Staging only until explicit prod approval.
--
-- Root cause: public.batata_recompact_reservation_queue ranked ALL status=pending
-- rows, so bag_hold_none received queue_position (e.g. 1) after recompact.
-- INSERT trigger batata_live_reservation_assign_queue already nulls bag_hold_none;
-- recompact overwrote that.
--
-- Fix:
-- 1) recompact only approval_pending pending rows; clear queue on bag_hold_none
-- 2) harden assign_queue (INSERT) to keep bag_hold_none out of queue
-- 3) BEFORE UPDATE: force queue_position NULL when request_kind = bag_hold_none
-- 4) one-shot normalize of legacy bad rows (queue only — no status/stock/trust)

-- ---------------------------------------------------------------------------
-- A) Recompact — approval_pending only
-- ---------------------------------------------------------------------------
create or replace function public.batata_recompact_reservation_queue(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
  v_cleared int := 0;
  v_ambiguity_secs int := 10;
begin
  if p_live_item_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_item_id');
  end if;

  if not public.batata_can_ops_live_item(p_live_item_id) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  -- Never keep bag_hold_none (or non-approval pending) in the approval queue.
  update public.live_reservation_requests r
  set
    queue_position = null,
    updated_at = now()
  where r.live_item_id = p_live_item_id
    and r.status = 'pending'
    and coalesce(r.request_kind, 'approval_pending') is distinct from 'approval_pending'
    and r.queue_position is not null;

  get diagnostics v_cleared = row_count;

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
      -- Canonical queue = seller approval queue only
      and coalesce(r.request_kind, 'approval_pending') = 'approval_pending'
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
    'reassigned', v_updated,
    'cleared_non_approval', v_cleared
  );
end;
$$;

comment on function public.batata_recompact_reservation_queue(uuid) is
  'Recompact approval queue (pending+approval_pending only). bag_hold_none always queue_position NULL.';

revoke all on function public.batata_recompact_reservation_queue(uuid) from public, anon, authenticated;
grant execute on function public.batata_recompact_reservation_queue(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- B) INSERT assign — keep bag_hold_none out (idempotent with Phase 1)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_assign_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max integer;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  -- C.2 bag lines: no approval queue / no approval TTL
  if coalesce(new.request_kind, 'approval_pending') = 'bag_hold_none' then
    new.queue_position := null;
    return new;
  end if;

  -- Guaranteed / other kinds should not land as pending queue members
  if coalesce(new.request_kind, 'approval_pending') is distinct from 'approval_pending' then
    new.queue_position := null;
    return new;
  end if;

  if new.queue_position is null and new.live_item_id is not null then
    select coalesce(max(r.queue_position), 0)
      into v_max
    from public.live_reservation_requests r
    where r.live_item_id = new.live_item_id
      and r.status = 'pending'
      and coalesce(r.request_kind, 'approval_pending') = 'approval_pending';
    new.queue_position := v_max + 1;
  end if;

  if new.expires_at is null then
    new.expires_at := timezone('utc', now()) + interval '45 minutes';
  end if;

  return new;
end;
$$;

comment on function public.batata_live_reservation_assign_queue() is
  'BEFORE INSERT: assign queue only for pending approval_pending. bag_hold_none → queue_position NULL.';

-- ---------------------------------------------------------------------------
-- C) BEFORE UPDATE — prevent any writer from stamping queue on bag_hold_none
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_guard_bag_hold_queue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.request_kind, 'approval_pending') = 'bag_hold_none'
     and new.queue_position is not null then
    new.queue_position := null;
  end if;
  return new;
end;
$$;

drop trigger if exists batata_live_reservation_guard_bag_hold_queue_tg
  on public.live_reservation_requests;
create trigger batata_live_reservation_guard_bag_hold_queue_tg
  before update on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_guard_bag_hold_queue();

comment on function public.batata_live_reservation_guard_bag_hold_queue() is
  'BEFORE UPDATE: bag_hold_none cannot keep a non-null queue_position.';

-- ---------------------------------------------------------------------------
-- D) Legacy normalize (queue_position only)
-- ---------------------------------------------------------------------------
update public.live_reservation_requests
set
  queue_position = null,
  updated_at = now()
where coalesce(request_kind, 'approval_pending') = 'bag_hold_none'
  and queue_position is not null;
