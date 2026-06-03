-- Fleaber BATATA: verificação pós-deploy para V0 staging (não cria utilizadores).
-- Executar DEPOIS de live_ops_hotfix_batata.sql
-- Os dados de teste são criados pelo script: dart run tool/live_ops_staging_check.dart

do $$
begin
  if not exists (
    select 1
    from pg_proc
    where proname = 'batata_live_reconcile_stripe_order'
  ) then
    raise exception 'RPC batata_live_reconcile_stripe_order em falta — corre live_ops_hotfix_batata.sql';
  end if;

  if not exists (
    select 1
    from pg_proc
    where proname = 'batata_live_bag_remove_request'
  ) then
    raise exception 'RPC batata_live_bag_remove_request em falta';
  end if;

  if not exists (
    select 1
    from pg_proc
    where proname = 'batata_update_live_item'
  ) then
    raise exception 'RPC batata_update_live_item em falta';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'live_id'
  ) then
    raise exception 'Coluna orders.live_id em falta — corre orders_live_context_batata.sql';
  end if;
  raise notice 'live_ops_test_seed: RPCs e orders.live_id OK para V0 staging';
end;
$$;
