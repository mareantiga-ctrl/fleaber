-- Limpeza FM entre lotes do Lab: 1 round-trip (evita timeout REST count+delete+verify).
create or replace function public.batata_lab_clear_fm_pending(p_live_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
  v_left integer := 0;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_id_required');
  end if;

  delete from public.live_reservation_requests
  where live_id = p_live_id
    and source = 'facebook_manual'
    and status = 'pending';
  get diagnostics v_deleted = row_count;

  select count(*)::integer into v_left
  from public.live_reservation_requests
  where live_id = p_live_id
    and source = 'facebook_manual'
    and status = 'pending';

  return jsonb_build_object(
    'ok', (v_left = 0),
    'mode', 'rpc_pending_only',
    'deleted', v_deleted,
    'remaining', v_left,
    'live_id', p_live_id
  );
end;
$$;

revoke all on function public.batata_lab_clear_fm_pending(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_lab_clear_fm_pending(uuid) to service_role;

comment on function public.batata_lab_clear_fm_pending(uuid) is
  'Lab: apaga facebook_manual pending desta live e devolve remaining (1 RPC).';
