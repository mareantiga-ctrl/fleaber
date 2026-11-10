-- =============================================================================
-- E74 — Expire automático PREPARADO (NÃO activa cron / flags)
-- Documenta helper de dry-run + comentários. Flag permanece OFF em produção.
-- =============================================================================

create or replace function public.batata_expire_guaranteed_reservations_dry_run(
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(least(coalesce(p_limit, 50), 200), 1);
  v_count bigint := 0;
begin
  -- Conta candidatas; NÃO altera stock/reservas.
  select count(*) into v_count
  from (
    select 1
    from public.live_reservation_requests r
    where r.status in ('guaranteed', 'accepted')
      and r.expires_at is not null
      and r.expires_at <= timezone('utc', now())
    limit v_limit
  ) x;

  return jsonb_build_object(
    'ok', true,
    'dry_run', true,
    'would_touch_approx', v_count,
    'hint', 'Chamar batata_expire_guaranteed_reservations só com GO-F2 + scheduler externo'
  );
end;
$$;

revoke all on function public.batata_expire_guaranteed_reservations_dry_run(integer) from public;
grant execute on function public.batata_expire_guaranteed_reservations_dry_run(integer)
  to service_role;

comment on function public.batata_expire_guaranteed_reservations_dry_run(integer) is
  'E74: dry-run only. NÃO activa expire_guaranteed_cron.';

notify pgrst, 'reload schema';
