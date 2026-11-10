-- =============================================================================
-- BATATA 2026-10-05 — Fase 2: scoped expire (DROP + recreate overloads)
-- =============================================================================

drop function if exists public.batata_expire_guaranteed_reservations(timestamptz);
drop function if exists public.batata_expire_guaranteed_reservations();
drop function if exists public.batata_expire_guaranteed_reservations(timestamptz, uuid);

create or replace function public.batata_expire_guaranteed_reservations(
  p_now timestamptz default timezone('utc', now()),
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_pay jsonb;
  v_expired integer := 0;
  v_deferred integer := 0;
  v_failures integer := 0;
  v_hold_until timestamptz;
  v_fail jsonb;
begin
  perform set_config('batata.allow_internal_live_ops', '1', true);

  for r in
    select *
    from public.live_reservation_requests
    where status = 'accepted'
      and expires_at is not null
      and expires_at < p_now
      and (p_request_id is null or id = p_request_id)
    for update skip locked
  loop
    v_pay := public.batata_lrr_payment_in_progress(r.id, p_now);

    if coalesce((v_pay->>'in_progress')::boolean, false) then
      v_hold_until := nullif(v_pay->>'hold_until', '')::timestamptz;
      if v_hold_until is not null and v_hold_until > r.expires_at then
        update public.live_reservation_requests
        set
          expires_at = v_hold_until,
          notes = trim(both ' |' from coalesce(notes, '') || ' | payment_grace'),
          updated_at = p_now
        where id = r.id;
      end if;
      v_deferred := v_deferred + 1;
      continue;
    end if;

    update public.live_reservation_requests
    set
      status = 'expired',
      expiry_reason = 'guaranteed_hold_expired_unpaid',
      notes = trim(both ' |' from coalesce(notes, '') || ' | guaranteed_auto_expired'),
      updated_at = p_now
    where id = r.id
      and status = 'accepted';

    if found then
      v_expired := v_expired + 1;
      perform public.batata_commerce_emit_reservation_event(
        r.id,
        'guaranteed_expired',
        jsonb_build_object('expiry_reason', 'guaranteed_hold_expired_unpaid')
      );

      if r.buyer_id is not null then
        v_fail := public.batata_buyer_trust_record_failure(
          r.buyer_id,
          'live_reservation_request',
          r.id::text,
          'guaranteed_hold_expired_unpaid',
          jsonb_build_object('live_item_id', r.live_item_id, 'seller_id', r.seller_id)
        );
        if coalesce((v_fail->>'inserted')::boolean, false) then
          v_failures := v_failures + 1;
        end if;
      end if;

      begin
        perform public.batata_recompute_live_item_status(r.live_item_id);
      exception when others then
        null;
      end;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'expired', v_expired,
    'payment_deferred', v_deferred,
    'failures_recorded', v_failures
  );
end;
$$;

revoke all on function public.batata_expire_guaranteed_reservations(timestamptz, uuid) from public;
grant execute on function public.batata_expire_guaranteed_reservations(timestamptz, uuid)
  to service_role;

-- Re-schedule cron to call two-arg with defaults via explicit select
do $cron_guaranteed$
begin
  perform cron.unschedule('batata-guaranteed-reservations-expire');
exception when others then
  null;
end;
$cron_guaranteed$;

do $cron_guaranteed_sched$
begin
  perform cron.schedule(
    'batata-guaranteed-reservations-expire',
    '*/15 * * * *',
    $$ select public.batata_expire_guaranteed_reservations(timezone('utc', now()), null); $$
  );
exception when others then
  raise notice 'guaranteed expire cron not scheduled: %', sqlerrm;
end;
$cron_guaranteed_sched$;

notify pgrst, 'reload schema';
