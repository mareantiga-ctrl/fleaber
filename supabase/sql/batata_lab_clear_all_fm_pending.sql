-- Lab «Limpar FM»: limpa holds que bloqueiam aviso ao iniciar directo.
-- NÃO apaga converted (compras reais pagas).
create or replace function public.batata_lab_clear_all_fm_pending()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fm integer := 0;
  v_fl_pending integer := 0;
  v_accepted integer := 0;
  v_orders integer := 0;
  v_left integer := 0;
begin
  delete from public.live_reservation_requests
  where source = 'facebook_manual'
    and status = 'pending';
  get diagnostics v_fm = row_count;

  delete from public.live_reservation_requests
  where source = 'fleaber_live'
    and status = 'pending';
  get diagnostics v_fl_pending = row_count;

  delete from public.live_reservation_requests
  where status = 'accepted'
    and source in ('fleaber_live', 'facebook_manual');
  get diagnostics v_accepted = row_count;

  delete from public.orders
  where lower(trim(coalesce(status, ''))) in (
    'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
  );
  get diagnostics v_orders = row_count;

  select count(*)::integer into v_left
  from public.live_reservation_requests
  where status in ('pending', 'accepted')
    and source in ('fleaber_live', 'facebook_manual');

  return jsonb_build_object(
    'ok', (v_left = 0),
    'mode', 'rpc_all_open_holds',
    'deleted', v_fm + v_fl_pending + v_accepted + v_orders,
    'remaining', v_left,
    'fm_deleted', v_fm,
    'fleaber_live_pending_deleted', v_fl_pending,
    'accepted_deleted', v_accepted,
    'open_orders_deleted', v_orders
  );
end;
$$;

revoke all on function public.batata_lab_clear_all_fm_pending()
  from public, anon, authenticated;
grant execute on function public.batata_lab_clear_all_fm_pending() to service_role;

comment on function public.batata_lab_clear_all_fm_pending() is
  'Lab Limpar FM: pending FM+fleaber_live + accepted unpaid + encomendas abertas. Não toca converted.';
