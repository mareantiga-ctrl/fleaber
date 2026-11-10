-- Hotfix: batata_recompact_reservation_queue — PostgreSQL 42P20
-- "window function calls cannot be nested" (lag inside sum over)

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

notify pgrst, 'reload schema';
