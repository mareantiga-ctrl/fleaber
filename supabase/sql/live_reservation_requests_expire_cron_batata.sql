-- BATATA 2026-09-30: expirar live_reservation_requests pending após expires_at.
-- Espelha batata_expire_reservation_holds / batata_expire_product_offers (pg_cron */15).
-- Autoridade do tempo: now() do servidor. Não depende da app aberta.
-- Não toca em accepted / converted / rejected nem em orders pagas.

create extension if not exists pg_cron with schema extensions;

-- Permite recompact/recompute sob GUC interno (cron / jobs security definer).
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
  v_internal text;
begin
  begin
    v_internal := current_setting('batata.allow_internal_live_ops', true);
  exception
    when others then
      v_internal := '';
  end;
  if coalesce(v_internal, '') = '1' then
    return true;
  end if;

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

comment on function public.batata_can_ops_live_item(uuid) is
  'Ops live item: seller/staff/participant/service_role; GUC batata.allow_internal_live_ops=1 para cron.';

create or replace function public.batata_expire_live_reservation_requests(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $batata_expire_live_reservation_requests$
declare
  r record;
  v_count integer := 0;
  v_item uuid;
begin
  perform set_config('batata.allow_internal_live_ops', '1', true);

  for r in
    select id, live_item_id
    from public.live_reservation_requests
    where status = 'pending'
      and expires_at is not null
      and expires_at < p_now
    for update skip locked
  loop
    update public.live_reservation_requests
    set
      status = 'expired',
      notes = trim(both ' |' from coalesce(notes, '') || ' | auto_expired'),
      updated_at = p_now
    where id = r.id
      and status = 'pending';

    if found then
      v_count := v_count + 1;
      v_item := r.live_item_id;
      -- Um item problemático não deve abortar o lote inteiro.
      begin
        perform public.batata_recompact_reservation_queue(v_item);
        perform public.batata_recompute_live_item_status(v_item);
      exception
        when others then
          null;
      end;
    end if;
  end loop;

  return v_count;
end;
$batata_expire_live_reservation_requests$;

comment on function public.batata_expire_live_reservation_requests(timestamptz) is
  'Marca pending live_reservation_requests com expires_at < now como expired; recompacta fila.';

revoke all on function public.batata_expire_live_reservation_requests(timestamptz)
  from public, anon, authenticated;
grant execute on function public.batata_expire_live_reservation_requests(timestamptz)
  to service_role;

do $cron_unschedule_live_req$
begin
  perform cron.unschedule('batata-live-reservation-requests-expire');
exception
  when others then
    null;
end;
$cron_unschedule_live_req$;

select cron.schedule(
  'batata-live-reservation-requests-expire',
  '*/15 * * * *',
  $$ select public.batata_expire_live_reservation_requests(); $$
);
