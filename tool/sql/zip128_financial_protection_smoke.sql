-- ZIP 128 — smoke SQL (PROD Sandbox logic; sem Stripe real)
-- Correr após apply. Não move dinheiro externo.

begin;

-- 1) Tabelas / colunas
do $$
begin
  assert exists (
    select 1 from information_schema.columns
    where table_name='orders' and column_name='funds_hold_until'
  );
  assert exists (
    select 1 from information_schema.columns
    where table_name='wallets' and column_name='held_balance'
  );
  assert to_regclass('public.stripe_disputes') is not null;
  assert to_regclass('public.seller_risk_events') is not null;
end $$;

-- 2) Freeze parcial + idempotência (wallet dummy se necessário)
do $$
declare
  v_uid uuid;
  v_r jsonb;
  v_held numeric;
  v_debt numeric;
begin
  select id into v_uid from public.profiles limit 1;
  if v_uid is null then
    raise notice 'skip freeze: no profile';
    return;
  end if;
  perform public.batata_ensure_wallet(v_uid);
  update public.wallets set balance = greatest(balance, 50.00), held_balance = 0, recovery_debt = 0
  where id = v_uid;

  v_r := public.batata_apply_stripe_dispute_freeze(
    'dp_test_zip128_smoke',
    null, v_uid, 1500, 'needs_response', 'fraudulent',
    'ch_test', 'pi_test', 'evt_zip128_1', null,
    '{"smoke":true}'::jsonb
  );
  assert (v_r->>'ok')::boolean;

  select held_balance, recovery_debt into v_held, v_debt
  from public.wallets where id = v_uid;
  assert v_held = 15.00;

  -- idempotente mesmo event
  v_r := public.batata_apply_stripe_dispute_freeze(
    'dp_test_zip128_smoke',
    null, v_uid, 1500, 'needs_response', 'fraudulent',
    'ch_test', 'pi_test', 'evt_zip128_1', null,
    '{"smoke":true}'::jsonb
  );
  assert (v_r->>'idempotent')::boolean;

  -- recovery se freeze > disponível
  update public.wallets set balance = 5, held_balance = 0, recovery_debt = 0 where id = v_uid;
  delete from public.stripe_disputes where stripe_dispute_id = 'dp_test_zip128_smoke2';
  v_r := public.batata_apply_stripe_dispute_freeze(
    'dp_test_zip128_smoke2',
    null, v_uid, 2000, 'needs_response', 'fraudulent',
    'ch_test2', 'pi_test2', 'evt_zip128_2', null,
    '{}'::jsonb
  );
  select held_balance, recovery_debt into v_held, v_debt
  from public.wallets where id = v_uid;
  assert v_held = 5.00;
  assert v_debt = 15.00;

  -- cleanup smoke
  delete from public.stripe_disputes where stripe_dispute_id like 'dp_test_zip128%';
  update public.wallets set held_balance = 0, recovery_debt = 0 where id = v_uid;
  raise notice 'freeze smoke OK';
end $$;

rollback;
