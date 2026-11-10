-- Hotfix: batata_buyer_trust_recompute — avoid unassigned RECORD loop variable
create or replace function public.batata_buyer_trust_recompute(p_buyer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fulfillments integer := 0;
  v_failures_90 integer := 0;
  v_threshold integer;
  v_should_lost boolean := false;
  v_prev text;
  v_recovery integer := 0;
  v_status text := 'trusted';
  v_lost_at timestamptz;
  v_recovered_at timestamptz;
  v_seq integer := 0;
  v_kind text;
begin
  if p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_buyer');
  end if;

  select s.global_status, s.recovery_count, s.lost_at, s.recovered_at
    into v_prev, v_recovery, v_lost_at, v_recovered_at
  from public.buyer_trust_state s
  where s.buyer_id = p_buyer_id;

  if not found then
    v_prev := 'trusted';
    v_recovery := 0;
    v_lost_at := null;
    v_recovered_at := null;
  end if;

  select count(*)::int into v_fulfillments
  from public.buyer_trust_events e
  where e.buyer_id = p_buyer_id
    and e.kind = 'fulfillment'
    and e.revoked_at is null
    and not exists (
      select 1 from public.buyer_trust_events rv
      where rv.buyer_id = p_buyer_id
        and rv.kind = 'fulfillment_revoked'
        and rv.source_type = e.source_type
        and rv.source_id = e.source_id
    );

  select count(*)::int into v_failures_90
  from public.buyer_trust_events e
  where e.buyer_id = p_buyer_id
    and e.kind = 'failure'
    and e.occurred_at >= timezone('utc', now()) - interval '90 days';

  if v_fulfillments <= 4 then
    v_threshold := 1;
  elsif v_fulfillments <= 19 then
    v_threshold := 2;
  else
    v_threshold := 3;
  end if;

  v_should_lost := v_failures_90 >= v_threshold;

  if v_should_lost or v_prev = 'lost' then
    v_status := 'lost';
    if v_lost_at is null then
      v_lost_at := timezone('utc', now());
    end if;

    v_seq := 0;
    for v_kind in
      select e.kind
      from public.buyer_trust_events e
      where e.buyer_id = p_buyer_id
        and e.kind in ('fulfillment', 'failure')
        and e.occurred_at >= v_lost_at
        and (e.kind <> 'fulfillment' or e.revoked_at is null)
      order by e.occurred_at asc, e.created_at asc
    loop
      if v_kind = 'failure' then
        v_seq := 0;
      elsif v_kind = 'fulfillment' then
        v_seq := v_seq + 1;
      end if;
    end loop;

    v_recovery := least(v_seq, 3);
    if v_seq >= 3 then
      v_status := 'trusted';
      v_recovery := 0;
      v_recovered_at := timezone('utc', now());
      if not exists (
        select 1 from public.buyer_trust_events e
        where e.buyer_id = p_buyer_id
          and e.kind = 'recovered'
          and e.occurred_at >= v_lost_at
      ) then
        insert into public.buyer_trust_events (
          buyer_id, kind, source_type, source_id, meta, occurred_at
        ) values (
          p_buyer_id, 'recovered', 'system',
          'recovered:' || p_buyer_id::text || ':' || extract(epoch from timezone('utc', now()))::bigint::text,
          jsonb_build_object('fulfillments', v_fulfillments),
          timezone('utc', now())
        );
      end if;
    elsif v_should_lost and v_prev is distinct from 'lost' then
      if not exists (
        select 1 from public.buyer_trust_events e
        where e.buyer_id = p_buyer_id
          and e.kind = 'loss'
          and e.source_id = (
            'loss:' || p_buyer_id::text || ':' || v_failures_90::text || ':' || v_fulfillments::text
          )
      ) then
        insert into public.buyer_trust_events (
          buyer_id, kind, source_type, source_id, meta, occurred_at
        ) values (
          p_buyer_id, 'loss', 'system',
          'loss:' || p_buyer_id::text || ':' || v_failures_90::text || ':' || v_fulfillments::text,
          jsonb_build_object(
            'failures_90d', v_failures_90,
            'fulfillments', v_fulfillments,
            'threshold', v_threshold
          ),
          timezone('utc', now())
        );
      end if;
      v_lost_at := timezone('utc', now());
    end if;
  else
    v_status := 'trusted';
    v_recovery := 0;
  end if;

  insert into public.buyer_trust_state as s (
    buyer_id, global_status, recovery_count, lost_at, recovered_at,
    fulfillment_count, updated_at
  ) values (
    p_buyer_id, v_status, v_recovery, v_lost_at, v_recovered_at,
    v_fulfillments, timezone('utc', now())
  )
  on conflict (buyer_id) do update
    set global_status = excluded.global_status,
        recovery_count = excluded.recovery_count,
        lost_at = case
          when excluded.global_status = 'lost' then coalesce(s.lost_at, excluded.lost_at)
          else s.lost_at
        end,
        recovered_at = case
          when excluded.global_status = 'trusted' and s.global_status = 'lost'
            then excluded.recovered_at
          else s.recovered_at
        end,
        fulfillment_count = excluded.fulfillment_count,
        updated_at = timezone('utc', now());

  return jsonb_build_object(
    'ok', true,
    'buyer_id', p_buyer_id,
    'global_status', v_status,
    'fulfillment_count', v_fulfillments,
    'failures_90d', v_failures_90,
    'threshold', v_threshold,
    'recovery_count', v_recovery
  );
end;
$$;

grant execute on function public.batata_buyer_trust_recompute(uuid) to service_role;
notify pgrst, 'reload schema';
