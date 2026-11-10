-- ZIP 166 — smoke Ponto 11 (ROLLBACK). Sem Stripe LIVE. Sem contas bancárias reais.
begin;

do $$
begin
  assert exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='wallets'
      and column_name='stripe_connect_transfers_status'
  );
  assert to_regprocedure('public.batata_sync_stripe_connect_account(uuid,text,boolean,text,boolean,boolean,text)') is not null
    or to_regprocedure('public.batata_sync_stripe_connect_account(uuid, text, boolean, text, boolean, boolean, text)') is not null
    or exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.proname='batata_sync_stripe_connect_account'
    );
  assert exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='batata_wallet_payout_fail_by_transfer_id'
  );
  assert exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='batata_seller_wallet_summary'
  );
end $$;

do $$
declare
  v_seller uuid;
  v_key text := 'zip166-smoke-payout-' || substr(md5(random()::text), 1, 12);
  v_d1 jsonb;
  v_d2 jsonb;
  v_sum jsonb;
  v_sync jsonb;
  v_fail jsonb;
  v_avail numeric;
  v_bal0 numeric;
  v_held0 numeric;
  v_risk0 text;
begin
  select id into v_seller from public.profiles limit 1;
  if v_seller is null then
    raise notice 'SMOKE_SKIP no profile';
    return;
  end if;

  select balance, coalesce(held_balance,0), coalesce(risk_status,'clear')
    into v_bal0, v_held0, v_risk0
  from public.wallets where id = v_seller;

  perform public.batata_ensure_wallet(v_seller);
  update public.wallets
  set balance = 50.00, held_balance = 10.00, risk_status = 'clear', updated_at = now()
  where id = v_seller;

  v_avail := public.batata_wallet_available_eur(v_seller);
  if v_avail is distinct from 40.00 then
    raise exception 'SMOKE_FAIL available=%', v_avail;
  end if;

  v_d1 := public.batata_wallet_payout_debit(v_seller, 1500, v_key);
  if coalesce((v_d1->>'ok')::boolean, false) is not true then
    raise exception 'SMOKE_FAIL debit1 %', v_d1;
  end if;

  v_d2 := public.batata_wallet_payout_debit(v_seller, 1500, v_key);
  if coalesce((v_d2->>'idempotent')::boolean, false) is not true then
    raise exception 'SMOKE_FAIL debit_idempotent %', v_d2;
  end if;

  perform public.batata_wallet_payout_finish(v_key, 'tr_zip166_smoke_1', false);
  v_fail := public.batata_wallet_payout_fail_by_transfer_id('tr_zip166_smoke_1', 'evt_zip166_1');
  if coalesce((v_fail->>'ok')::boolean, false) is not true then
    raise exception 'SMOKE_FAIL fail_transfer %', v_fail;
  end if;

  -- 2.ª vez fail → idempotente
  v_fail := public.batata_wallet_payout_fail_by_transfer_id('tr_zip166_smoke_1', 'evt_zip166_1b');
  if coalesce((v_fail->>'idempotent')::boolean, false) is not true
     and coalesce((v_fail->>'ok')::boolean, false) is not true then
    raise exception 'SMOKE_FAIL fail_idempotent %', v_fail;
  end if;

  update public.wallets set risk_status = 'risk_hold', balance = 20, held_balance = 0 where id = v_seller;
  v_d1 := public.batata_wallet_payout_debit(
    v_seller, 500, 'zip166-risk-' || substr(md5(random()::text), 1, 8)
  );
  if (v_d1->>'error') is distinct from 'payout_blocked_risk_hold' then
    raise exception 'SMOKE_FAIL risk_block %', v_d1;
  end if;

  v_sync := public.batata_sync_stripe_connect_account(
    v_seller, 'acct_zip166_smoke', true, 'active', true, true, 'evt_acc_1'
  );
  if coalesce((v_sync->>'ok')::boolean, false) is not true then
    raise exception 'SMOKE_FAIL sync %', v_sync;
  end if;

  v_sum := public.batata_seller_wallet_summary(v_seller);
  if coalesce((v_sum->>'ok')::boolean, false) is not true then
    -- sem JWT service: pode ser forbidden se auth.uid null e não é service
    -- em smoke via postgres superuser auth.uid() é null → summary deve OK
    raise exception 'SMOKE_FAIL summary %', v_sum;
  end if;

  -- restore snapshot (ainda dentro do rollback, mas bom para assert)
  update public.wallets
  set balance = coalesce(v_bal0, 0),
      held_balance = coalesce(v_held0, 0),
      risk_status = coalesce(v_risk0, 'clear'),
      stripe_account_id = case
        when stripe_account_id = 'acct_zip166_smoke' then null
        else stripe_account_id
      end
  where id = v_seller;

  raise notice 'SMOKE_OK zip166 seller=% avail=% sync=%', v_seller, v_avail, v_sync->>'stripe_account_id';
end $$;

rollback;
