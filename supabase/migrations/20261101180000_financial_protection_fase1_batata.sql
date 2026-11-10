-- =============================================================================
-- FASE1 proteção financeira (ZIP 128) — BATATA
-- C2C 48h preservado · B2C hold 14d · chargeback freeze parcial · risk hold
-- Idempotente. Compatível / reversível (ver secção ROLLBACK no relatório 128).
-- NÃO executa pagamentos Stripe. NÃO activa Live.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Colunas encomenda
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists commerce_channel text,
  add column if not exists seller_professional_at_pay boolean not null default false,
  add column if not exists withdrawal_exception_code text,
  add column if not exists consumer_withdrawal_deadline_at timestamptz,
  add column if not exists funds_hold_until timestamptz,
  add column if not exists consumer_withdrawal_started_at timestamptz,
  add column if not exists consumer_withdrawal_status text,
  add column if not exists stripe_dispute_id text,
  add column if not exists stripe_dispute_amount_cents integer,
  add column if not exists stripe_dispute_status text;

comment on column public.orders.commerce_channel is
  'c2c | b2c — snapshot no settle; B2C = vendedor profissional verificado.';
comment on column public.orders.funds_hold_until is
  'Até esta data o crédito wallet não é libertável (B2C 14d / disputa).';
comment on column public.orders.withdrawal_exception_code is
  'Excepção legal livre resolução (ex. personalized, sealed_hygiene) ou null.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_commerce_channel_chk'
  ) then
    alter table public.orders
      add constraint orders_commerce_channel_chk
      check (
        commerce_channel is null
        or commerce_channel in ('c2c', 'b2c')
      );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Produtos — excepção declarada (não inventa excepções ilegais)
-- ---------------------------------------------------------------------------
alter table public.products
  add column if not exists withdrawal_exception_code text;

comment on column public.products.withdrawal_exception_code is
  'Código de excepção art.16 Dir.2011/83 se aplicável; null = direito normal.';

-- ---------------------------------------------------------------------------
-- 3) Wallet held (só o contestado / recovery)
-- ---------------------------------------------------------------------------
alter table public.wallets
  add column if not exists held_balance numeric(12, 2) not null default 0.00,
  add column if not exists recovery_debt numeric(12, 2) not null default 0.00,
  add column if not exists risk_status text not null default 'clear',
  add column if not exists risk_hold_reason text,
  add column if not exists risk_hold_at timestamptz,
  add column if not exists risk_reviewed_at timestamptz,
  add column if not exists risk_ban_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'wallets_risk_status_chk'
  ) then
    alter table public.wallets
      add constraint wallets_risk_status_chk
      check (risk_status in (
        'clear', 'risk_hold', 'under_review', 'cleared', 'permanent_ban'
      ));
  end if;
end $$;

comment on column public.wallets.held_balance is
  'EUR retidos (disputas Stripe / recovery) — payout usa balance - held.';
comment on column public.wallets.recovery_debt is
  'EUR a recuperar quando held > balance disponível.';

-- ---------------------------------------------------------------------------
-- 4) Tabelas dispute / recovery / risk events
-- ---------------------------------------------------------------------------
create table if not exists public.stripe_disputes (
  id uuid primary key default gen_random_uuid(),
  stripe_dispute_id text not null unique,
  charge_id text,
  payment_intent_id text,
  order_id uuid references public.orders(id) on delete set null,
  seller_id uuid references public.profiles(id) on delete set null,
  amount_cents integer not null check (amount_cents >= 0),
  currency text not null default 'eur',
  status text not null default 'needs_response',
  reason text,
  evidence_due_by timestamptz,
  frozen_eur numeric(12, 2) not null default 0,
  recovery_eur numeric(12, 2) not null default 0,
  stripe_event_id text,
  raw_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stripe_disputes_seller_idx
  on public.stripe_disputes (seller_id);
create index if not exists stripe_disputes_order_idx
  on public.stripe_disputes (order_id);

alter table public.stripe_disputes enable row level security;

drop policy if exists stripe_disputes_select_own on public.stripe_disputes;
create policy stripe_disputes_select_own
  on public.stripe_disputes for select to authenticated
  using (seller_id = auth.uid() or public.batata_is_admin());

create table if not exists public.seller_risk_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  severity text not null default 'risk'
    check (severity in ('risk', 'confirmed_fraud', 'info')),
  reason_public text not null,
  reason_internal text,
  actor_id uuid,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists seller_risk_events_user_idx
  on public.seller_risk_events (user_id, created_at desc);

alter table public.seller_risk_events enable row level security;

drop policy if exists seller_risk_events_select_own on public.seller_risk_events;
create policy seller_risk_events_select_own
  on public.seller_risk_events for select to authenticated
  using (user_id = auth.uid() or public.batata_is_admin());

-- ---------------------------------------------------------------------------
-- 5) Snapshot B2C no settle
-- ---------------------------------------------------------------------------
create or replace function public.batata_stamp_order_commerce_channel(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_verified boolean := false;
  v_exc text;
begin
  select o.seller_id, p.withdrawal_exception_code
    into v_seller, v_exc
  from public.orders o
  left join public.products p on p.id = o.product_id
  where o.id = p_order_id;

  if v_seller is null then
    return;
  end if;

  select exists (
    select 1 from public.seller_trade_profiles t
    where t.user_id = v_seller
      and t.is_trader = true
      and t.verification_status = 'verified'
  ) into v_verified;

  update public.orders
  set
    seller_professional_at_pay = v_verified,
    commerce_channel = case when v_verified then 'b2c' else 'c2c' end,
    withdrawal_exception_code = coalesce(withdrawal_exception_code, v_exc)
  where id = p_order_id
    and (
      commerce_channel is null
      or seller_professional_at_pay is distinct from v_verified
    );
end;
$$;

revoke all on function public.batata_stamp_order_commerce_channel(uuid)
  from public, anon;
grant execute on function public.batata_stamp_order_commerce_channel(uuid)
  to service_role;

-- Ao passar a concluido: B2C sem excepção → hold 14 dias
create or replace function public.batata_orders_set_b2c_hold_on_concluido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start timestamptz;
  v_verified boolean := false;
  v_exc text;
begin
  if lower(coalesce(new.status, '')) = 'concluido'
     and lower(coalesce(old.status, '')) is distinct from 'concluido' then
    select exists (
      select 1 from public.seller_trade_profiles t
      where t.user_id = new.seller_id
        and t.is_trader = true
        and t.verification_status = 'verified'
    ) into v_verified;

    select p.withdrawal_exception_code into v_exc
    from public.products p where p.id = new.product_id;

    new.seller_professional_at_pay := v_verified;
    new.commerce_channel := case when v_verified then 'b2c' else 'c2c' end;
    new.withdrawal_exception_code := coalesce(
      new.withdrawal_exception_code, v_exc
    );

    v_start := coalesce(new.completed_at, now());

    if new.commerce_channel = 'b2c'
       and coalesce(nullif(trim(new.withdrawal_exception_code), ''), '') = '' then
      new.consumer_withdrawal_deadline_at := v_start + interval '14 days';
      new.funds_hold_until := greatest(
        coalesce(new.funds_hold_until, v_start),
        v_start + interval '14 days'
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_batata_orders_b2c_hold on public.orders;
create trigger trg_batata_orders_b2c_hold
before update of status on public.orders
for each row
execute function public.batata_orders_set_b2c_hold_on_concluido();

-- ---------------------------------------------------------------------------
-- 6) Release — respeita funds_hold_until + dispute stripe + risk ban
-- ---------------------------------------------------------------------------
create or replace function public.batata_release_seller_wallet_for_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_product_title text;
  v_amount numeric;
  v_base numeric;
  v_remaining numeric;
  v_done boolean;
  v_cleared int;
  v_ship text;
  v_risk text;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.seller_id is null then
    return false;
  end if;

  if auth.uid() is not null and auth.uid() <> v_order.buyer_id
     and coalesce(auth.role(), '') = 'authenticated'
     and not public.batata_is_admin() then
    return false;
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido') then
    return false;
  end if;

  -- ZIP 128: hold B2C / disputa Stripe / livre resolução em curso
  if v_order.funds_hold_until is not null
     and v_order.funds_hold_until > now() then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_dispute_status), ''), '') <> ''
     and lower(v_order.stripe_dispute_status) not in (
       'won', 'lost', 'warning_closed', 'charge_refunded'
     ) then
    -- disputa aberta → não libertar
    if lower(v_order.stripe_dispute_status) in (
      'needs_response', 'under_review', 'warning_needs_response',
      'warning_under_review'
    ) then
      return false;
    end if;
  end if;

  if coalesce(v_order.consumer_withdrawal_status, '') in (
    'requested', 'return_in_transit', 'open'
  ) then
    return false;
  end if;

  select risk_status into v_risk from public.wallets where id = v_order.seller_id;
  if coalesce(v_risk, 'clear') in ('risk_hold', 'under_review', 'permanent_ban') then
    return false;
  end if;

  v_ship := coalesce(v_order.shipping_method, '');
  if v_order.shipped_at is null
     and not public.batata_shipping_method_is_hand(v_ship) then
    return false;
  end if;

  if v_order.wallet_release_processed_at is not null then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  if exists (
    select 1 from public.order_disputes d
    where d.order_id = v_order.id
      and lower(coalesce(d.status, '')) is distinct from 'recusada'
      and lower(coalesce(d.status, '')) is distinct from 'fechada'
      and lower(coalesce(d.status, '')) is distinct from 'resolvida'
  ) then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    update public.orders
    set wallet_release_processed_at = now(),
        wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now())
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  if exists (
    select 1 from public.stripe_checkout_events e
    where e.order_id = v_order.id
      and lower(coalesce(e.event, '')) in ('refund_created', 'charge.refunded')
  ) then
    update public.orders
    set wallet_release_processed_at = now(),
        wallet_refund_processed_at = coalesce(wallet_refund_processed_at, now())
    where id = v_order.id and wallet_release_processed_at is null;
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);

  if v_base <= 0 or v_remaining <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0 and v_base <= 0;
  end if;

  select nullif(trim(title), '') into v_product_title
  from public.products where id = v_order.product_id;

  v_amount := least(
    greatest(v_base - public.batata_order_commission_amount(v_base), 0),
    v_remaining
  );

  if v_amount <= 0 then
    update public.orders
    set wallet_release_processed_at = now()
    where id = v_order.id and wallet_release_processed_at is null;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.seller_id, v_order.id, v_amount, 'venda',
    'Venda de ' || coalesce(v_product_title, 'artigo Fleaber')
  );

  if v_done then
    perform public.batata_record_fleaber_commission_once(
      v_order.id, public.batata_order_commission_amount(v_base),
      'protection_fee', 'Taxa de Proteção Fleaber'
    );
    update public.orders set wallet_release_processed_at = now() where id = v_order.id;
  end if;
  return v_done;
end;
$$;

revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

-- Cron auxiliar: libertar B2C após hold (service_role)
create or replace function public.batata_release_orders_past_funds_hold(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id from public.orders
    where status = 'concluido'
      and wallet_release_processed_at is null
      and funds_hold_until is not null
      and funds_hold_until <= p_now
      and coalesce(consumer_withdrawal_status, '') not in (
        'requested', 'return_in_transit', 'open'
      )
      and (
        stripe_dispute_status is null
        or lower(stripe_dispute_status) in (
          'won', 'lost', 'warning_closed', 'charge_refunded', ''
        )
      )
    limit 200
  loop
    if public.batata_release_seller_wallet_for_order(r.id) then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

revoke all on function public.batata_release_orders_past_funds_hold(timestamptz)
  from public, anon, authenticated;
grant execute on function public.batata_release_orders_past_funds_hold(timestamptz)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7) Payout — available = balance - held; bloqueio risk
-- ---------------------------------------------------------------------------
create or replace function public.batata_wallet_payout_debit(
  p_user_id uuid,
  p_amount_cents integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_eur numeric(12, 2);
  v_new_balance numeric(12, 2);
  v_existing public.wallet_payout_ledger%rowtype;
  v_risk text;
  v_held numeric(12, 2);
begin
  if p_user_id is null or p_amount_cents is null or p_amount_cents <= 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount');
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 then
    return jsonb_build_object('ok', false, 'error', 'invalid_idempotency_key');
  end if;

  select * into v_existing
  from public.wallet_payout_ledger
  where idempotency_key = trim(p_idempotency_key);

  if found then
    if v_existing.user_id is distinct from p_user_id then
      return jsonb_build_object('ok', false, 'error', 'idempotency_key_foreign');
    end if;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'status', v_existing.status,
      'stripe_transfer_id', v_existing.stripe_transfer_id,
      'balance_after', v_existing.balance_after,
      'amount_cents', v_existing.amount_cents
    );
  end if;

  select risk_status, coalesce(held_balance, 0)
    into v_risk, v_held
  from public.wallets where id = p_user_id for update;

  if coalesce(v_risk, 'clear') in ('risk_hold', 'under_review', 'permanent_ban') then
    return jsonb_build_object('ok', false, 'error', 'payout_blocked_risk_hold');
  end if;

  v_eur := round((p_amount_cents::numeric) / 100.0, 2);

  update public.wallets
  set balance = balance - v_eur,
      updated_at = now()
  where id = p_user_id
    and (balance - coalesce(held_balance, 0)) >= v_eur
  returning balance into v_new_balance;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance');
  end if;

  insert into public.wallet_payout_ledger (
    idempotency_key, user_id, amount_cents, amount_eur, status, balance_after
  ) values (
    trim(p_idempotency_key), p_user_id, p_amount_cents, v_eur, 'debited', v_new_balance
  );

  insert into public.wallet_transactions (
    wallet_id, amount, type, description
  ) values (
    p_user_id,
    -v_eur,
    'levantamento',
    'Levantamento pendente ' || trim(p_idempotency_key)
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'status', 'debited',
    'balance_after', v_new_balance,
    'amount_cents', p_amount_cents,
    'amount_eur', v_eur
  );
end;
$fn$;

revoke all on function public.batata_wallet_payout_debit(uuid, integer, text)
  from public, anon, authenticated;
grant execute on function public.batata_wallet_payout_debit(uuid, integer, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 8) Freeze / unfreeze disputa (parcial + recovery debt)
-- ---------------------------------------------------------------------------
-- Tipos de auditoria (não movem balance; amount=0)
do $$
begin
  alter table public.wallet_transactions
    drop constraint if exists wallet_transactions_type_check;
exception when undefined_object then
  null;
end $$;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_type_check
  check (type in (
    'venda',
    'compra',
    'reembolso',
    'levantamento',
    'estorno',
    'gorjeta_enviada',
    'gorjeta_recebida',
    'hold_dispute',
    'recovery_offset'
  ));

create or replace function public.batata_apply_stripe_dispute_freeze(
  p_stripe_dispute_id text,
  p_order_id uuid,
  p_seller_id uuid,
  p_amount_cents integer,
  p_status text,
  p_reason text,
  p_charge_id text,
  p_payment_intent_id text,
  p_stripe_event_id text,
  p_evidence_due_by timestamptz,
  p_raw jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eur numeric(12, 2);
  v_row public.stripe_disputes%rowtype;
  v_bal numeric(12, 2);
  v_held numeric(12, 2);
  v_freeze numeric(12, 2);
  v_debt numeric(12, 2) := 0;
  v_already numeric(12, 2) := 0;
begin
  if p_stripe_dispute_id is null or length(trim(p_stripe_dispute_id)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_dispute_id');
  end if;
  if p_amount_cents is null or p_amount_cents < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount');
  end if;

  v_eur := round(p_amount_cents::numeric / 100.0, 2);

  select * into v_row
  from public.stripe_disputes
  where stripe_dispute_id = trim(p_stripe_dispute_id)
  for update;

  if found then
    -- Idempotência: mesmo event_id → no-op
    if p_stripe_event_id is not null
       and v_row.stripe_event_id is not distinct from p_stripe_event_id then
      return jsonb_build_object(
        'ok', true, 'idempotent', true, 'dispute_id', v_row.id
      );
    end if;
    v_already := coalesce(v_row.frozen_eur, 0);
    update public.stripe_disputes
    set status = coalesce(p_status, status),
        reason = coalesce(p_reason, reason),
        amount_cents = p_amount_cents,
        evidence_due_by = coalesce(p_evidence_due_by, evidence_due_by),
        stripe_event_id = coalesce(p_stripe_event_id, stripe_event_id),
        raw_summary = coalesce(p_raw, raw_summary),
        updated_at = now()
    where id = v_row.id;
  else
    insert into public.stripe_disputes (
      stripe_dispute_id, charge_id, payment_intent_id, order_id, seller_id,
      amount_cents, status, reason, evidence_due_by, stripe_event_id, raw_summary
    ) values (
      trim(p_stripe_dispute_id), p_charge_id, p_payment_intent_id, p_order_id,
      p_seller_id, p_amount_cents, coalesce(p_status, 'needs_response'),
      p_reason, p_evidence_due_by, p_stripe_event_id, coalesce(p_raw, '{}'::jsonb)
    )
    returning * into v_row;
  end if;

  -- Congelar só o diferencial ainda não frozen
  v_freeze := greatest(v_eur - v_already, 0);

  if p_seller_id is not null and v_freeze > 0 then
    perform public.batata_ensure_wallet(p_seller_id);
    select balance, coalesce(held_balance, 0)
      into v_bal, v_held
    from public.wallets where id = p_seller_id for update;

    if v_bal - v_held >= v_freeze then
      update public.wallets
      set held_balance = coalesce(held_balance, 0) + v_freeze,
          updated_at = now()
      where id = p_seller_id;
    else
      v_debt := v_freeze - greatest(v_bal - v_held, 0);
      update public.wallets
      set held_balance = coalesce(held_balance, 0) + greatest(v_bal - v_held, 0),
          recovery_debt = coalesce(recovery_debt, 0) + v_debt,
          updated_at = now()
      where id = p_seller_id;
      v_freeze := greatest(v_bal - v_held, 0);
    end if;

    update public.stripe_disputes
    set frozen_eur = coalesce(frozen_eur, 0) + v_freeze,
        recovery_eur = coalesce(recovery_eur, 0) + v_debt,
        updated_at = now()
    where id = v_row.id;

    insert into public.wallet_transactions (wallet_id, amount, type, description)
    values (
      p_seller_id, 0, 'hold_dispute',
      'Retenção disputa Stripe ' || trim(p_stripe_dispute_id) ||
      ' (+' || v_freeze::text || '€ held)'
    );
  end if;

  if p_order_id is not null then
    update public.orders
    set stripe_dispute_id = trim(p_stripe_dispute_id),
        stripe_dispute_amount_cents = p_amount_cents,
        stripe_dispute_status = coalesce(p_status, stripe_dispute_status),
        funds_hold_until = greatest(
          coalesce(funds_hold_until, now()),
          now() + interval '30 days'
        )
    where id = p_order_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'dispute_id', v_row.id,
    'frozen_eur', v_freeze,
    'recovery_eur', v_debt
  );
end;
$$;

revoke all on function public.batata_apply_stripe_dispute_freeze(
  text, uuid, uuid, integer, text, text, text, text, text, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.batata_apply_stripe_dispute_freeze(
  text, uuid, uuid, integer, text, text, text, text, text, timestamptz, jsonb
) to service_role;

create or replace function public.batata_release_stripe_dispute_freeze(
  p_stripe_dispute_id text,
  p_final_status text,
  p_stripe_event_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.stripe_disputes%rowtype;
  v_unhold numeric(12, 2);
begin
  select * into v_row
  from public.stripe_disputes
  where stripe_dispute_id = trim(p_stripe_dispute_id)
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if p_stripe_event_id is not null
     and v_row.stripe_event_id is not distinct from p_stripe_event_id
     and lower(coalesce(v_row.status, '')) = lower(coalesce(p_final_status, '')) then
    return jsonb_build_object('ok', true, 'idempotent', true);
  end if;

  v_unhold := coalesce(v_row.frozen_eur, 0);

  if v_row.seller_id is not null and v_unhold > 0
     and lower(coalesce(p_final_status, '')) in ('won', 'warning_closed') then
    update public.wallets
    set held_balance = greatest(coalesce(held_balance, 0) - v_unhold, 0),
        updated_at = now()
    where id = v_row.seller_id;

    update public.stripe_disputes
    set frozen_eur = 0, status = p_final_status,
        stripe_event_id = coalesce(p_stripe_event_id, stripe_event_id),
        updated_at = now()
    where id = v_row.id;
  elsif lower(coalesce(p_final_status, '')) in ('lost', 'charge_refunded') then
    -- Mantém held até recovery; marca status
    update public.stripe_disputes
    set status = p_final_status,
        stripe_event_id = coalesce(p_stripe_event_id, stripe_event_id),
        updated_at = now()
    where id = v_row.id;
  else
    update public.stripe_disputes
    set status = coalesce(p_final_status, status),
        stripe_event_id = coalesce(p_stripe_event_id, stripe_event_id),
        updated_at = now()
    where id = v_row.id;
  end if;

  if v_row.order_id is not null then
    update public.orders
    set stripe_dispute_status = coalesce(p_final_status, stripe_dispute_status)
    where id = v_row.order_id;
  end if;

  return jsonb_build_object('ok', true, 'unheld_eur', v_unhold);
end;
$$;

revoke all on function public.batata_release_stripe_dispute_freeze(text, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_release_stripe_dispute_freeze(text, text, text)
  to service_role;

-- Compensação recovery com créditos futuros (após credit wallet)
create or replace function public.batata_apply_recovery_debt_on_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_debt numeric(12, 2);
  v_take numeric(12, 2);
begin
  if new.amount is null or new.amount <= 0 then
    return new;
  end if;
  if lower(coalesce(new.type, '')) not in (
    'venda', 'gorjeta_recebida', 'reembolso'
  ) then
    return new;
  end if;

  select coalesce(recovery_debt, 0) into v_debt
  from public.wallets where id = new.wallet_id for update;

  if v_debt <= 0 then
    return new;
  end if;

  v_take := least(v_debt, new.amount);
  update public.wallets
  set recovery_debt = recovery_debt - v_take,
      held_balance = coalesce(held_balance, 0) + v_take,
      updated_at = now()
  where id = new.wallet_id;

  insert into public.wallet_transactions (wallet_id, amount, type, description)
  values (
    new.wallet_id, 0, 'recovery_offset',
    'Compensação dívida recuperação ' || v_take::text || '€'
  );

  return new;
end;
$$;

drop trigger if exists trg_batata_recovery_on_credit on public.wallet_transactions;
create trigger trg_batata_recovery_on_credit
after insert on public.wallet_transactions
for each row
execute function public.batata_apply_recovery_debt_on_credit();

-- ---------------------------------------------------------------------------
-- 9) Livre resolução B2C (comprador)
-- ---------------------------------------------------------------------------
create or replace function public.batata_start_consumer_withdrawal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.buyer_id is distinct from v_uid then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if coalesce(v_order.commerce_channel, 'c2c') <> 'b2c' then
    return jsonb_build_object('ok', false, 'error', 'not_b2c');
  end if;
  if coalesce(nullif(trim(v_order.withdrawal_exception_code), ''), '') <> '' then
    return jsonb_build_object('ok', false, 'error', 'exception_applies');
  end if;
  if v_order.consumer_withdrawal_deadline_at is null
     or v_order.consumer_withdrawal_deadline_at < now() then
    return jsonb_build_object('ok', false, 'error', 'deadline_passed');
  end if;
  if coalesce(v_order.consumer_withdrawal_status, '') in (
    'requested', 'return_in_transit', 'open', 'refunded'
  ) then
    return jsonb_build_object('ok', true, 'idempotent', true,
      'status', v_order.consumer_withdrawal_status);
  end if;

  update public.orders
  set consumer_withdrawal_status = 'requested',
      consumer_withdrawal_started_at = now(),
      funds_hold_until = greatest(
        coalesce(funds_hold_until, now()),
        coalesce(consumer_withdrawal_deadline_at, now()) + interval '14 days'
      )
  where id = p_order_id;

  return jsonb_build_object('ok', true, 'status', 'requested');
end;
$$;

revoke all on function public.batata_start_consumer_withdrawal(uuid)
  from public, anon;
grant execute on function public.batata_start_consumer_withdrawal(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10) Risk hold / ban (admin ou service)
-- ---------------------------------------------------------------------------
create or replace function public.batata_set_seller_risk_status(
  p_user_id uuid,
  p_status text,
  p_reason_public text,
  p_reason_internal text default null,
  p_severity text default 'risk'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
begin
  if v_role <> 'service_role' and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if p_status not in (
    'clear', 'risk_hold', 'under_review', 'cleared', 'permanent_ban'
  ) then
    return jsonb_build_object('ok', false, 'error', 'invalid_status');
  end if;

  perform public.batata_ensure_wallet(p_user_id);

  update public.wallets
  set risk_status = p_status,
      risk_hold_reason = p_reason_public,
      risk_hold_at = case
        when p_status in ('risk_hold', 'under_review', 'permanent_ban')
        then coalesce(risk_hold_at, now()) else risk_hold_at end,
      risk_reviewed_at = case
        when p_status in ('cleared', 'under_review', 'permanent_ban')
        then now() else risk_reviewed_at end,
      risk_ban_at = case
        when p_status = 'permanent_ban' then now() else risk_ban_at end,
      updated_at = now()
  where id = p_user_id;

  insert into public.seller_risk_events (
    user_id, kind, severity, reason_public, reason_internal, actor_id
  ) values (
    p_user_id,
    'status_' || p_status,
    coalesce(p_severity, 'risk'),
    coalesce(p_reason_public, 'Atualização de risco'),
    p_reason_internal,
    auth.uid()
  );

  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

revoke all on function public.batata_set_seller_risk_status(uuid, text, text, text, text)
  from public, anon;
grant execute on function public.batata_set_seller_risk_status(uuid, text, text, text, text)
  to authenticated, service_role;

-- Disponível para UI
create or replace function public.batata_wallet_available_eur(p_user_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    coalesce(w.balance, 0) - coalesce(w.held_balance, 0),
    0
  )::numeric(12, 2)
  from public.wallets w
  where w.id = p_user_id;
$$;

revoke all on function public.batata_wallet_available_eur(uuid) from public, anon;
grant execute on function public.batata_wallet_available_eur(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11) Risk hold → suspende novas vendas (sem partir chat/encomendas)
-- ---------------------------------------------------------------------------
create or replace function public.seller_trade_public_info(p_seller_ids uuid[])
returns table (
  user_id uuid,
  is_professional boolean,
  professional_verified boolean,
  trade_name text,
  city text,
  country text,
  contact_email text,
  contact_phone text,
  sales_suspended boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id as user_id,
    (coalesce(t.verification_status, 'none') = 'verified') as is_professional,
    (coalesce(t.verification_status, 'none') = 'verified') as professional_verified,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.trade_name), '') else null end as trade_name,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then nullif(trim(t.city), '') else null end as city,
    case when coalesce(t.verification_status, 'none') = 'verified'
      then coalesce(nullif(trim(t.country), ''), 'PT') else null end as country,
    null::text as contact_email,
    null::text as contact_phone,
    (
      (
        coalesce(t.is_trader, false)
        and coalesce(t.verification_status, 'none') <> 'verified'
      )
      or exists (
        select 1 from public.wallets w
        where w.id = s.id
          and coalesce(w.risk_status, 'clear') in (
            'risk_hold', 'under_review', 'permanent_ban'
          )
      )
    ) as sales_suspended
  from unnest(p_seller_ids) as s(id)
  left join public.seller_trade_profiles t on t.user_id = s.id;
$$;

grant execute on function public.seller_trade_public_info(uuid[]) to authenticated;

-- Fechar livre resolução após refund Stripe (service_role / refund-order)
create or replace function public.batata_mark_consumer_withdrawal_refunded(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
begin
  if v_role <> 'service_role' and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  update public.orders
  set consumer_withdrawal_status = 'refunded',
      funds_hold_until = least(coalesce(funds_hold_until, now()), now())
  where id = p_order_id
    and coalesce(consumer_withdrawal_status, '') in (
      'requested', 'return_in_transit', 'open'
    );
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_mark_consumer_withdrawal_refunded(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_mark_consumer_withdrawal_refunded(uuid)
  to service_role;

-- Evidência dispute: registo local (Stripe API via edge submit-dispute-evidence)
create table if not exists public.stripe_dispute_evidence_uploads (
  id uuid primary key default gen_random_uuid(),
  stripe_dispute_id text not null
    references public.stripe_disputes(stripe_dispute_id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  uploaded_by uuid references public.profiles(id) on delete set null,
  evidence_kind text not null default 'other',
  storage_path text,
  stripe_submitted boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists stripe_dispute_evidence_dispute_idx
  on public.stripe_dispute_evidence_uploads (stripe_dispute_id);

alter table public.stripe_dispute_evidence_uploads enable row level security;

drop policy if exists stripe_dispute_evidence_select_own
  on public.stripe_dispute_evidence_uploads;
create policy stripe_dispute_evidence_select_own
  on public.stripe_dispute_evidence_uploads for select to authenticated
  using (
    uploaded_by = auth.uid()
    or public.batata_is_admin()
    or exists (
      select 1 from public.stripe_disputes d
      where d.stripe_dispute_id =
        stripe_dispute_evidence_uploads.stripe_dispute_id
        and d.seller_id = auth.uid()
    )
  );
