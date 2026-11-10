-- =============================================================================
-- FASE 1 hardening (BATATA) — P0 financeiro / autoridade servidor
-- Auditoria 02 CONFIRMADO: P0-01 preço, mutabilidade orders, wallet INSERT, payout.
-- NÃO inclui oversell (Fase 2).
-- Idempotente: seguro reexecutar.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Orders — remover INSERT legado permissivo + congelar dinheiro pós-pago
-- ---------------------------------------------------------------------------

drop policy if exists "Utilizadores podem criar encomendas" on public.orders;
drop policy if exists "Utilizadores podem criar as suas próprias encomendas" on public.orders;

-- Comprador/vendedor autenticado: não alterar campos financeiros/identidade
-- depois de pago (ou com Stripe já ligado). Antes/qty ainda podem mudar
-- em estados pré-pagamento (rifa portes, checkout).
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_status text;
  v_frozen boolean := false;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    -- Nunca criar já pago / com Stripe IDs.
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    return NEW;
  end if;

  -- UPDATE: identidade e Stripe IDs nunca pelo cliente.
  if NEW.buyer_id is distinct from OLD.buyer_id then
    NEW.buyer_id := OLD.buyer_id;
  end if;
  if NEW.seller_id is distinct from OLD.seller_id then
    NEW.seller_id := OLD.seller_id;
  end if;
  if NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id then
    NEW.stripe_checkout_session_id := OLD.stripe_checkout_session_id;
  end if;
  if NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id then
    NEW.stripe_payment_intent_id := OLD.stripe_payment_intent_id;
  end if;
  if NEW.stripe_refund_id is distinct from OLD.stripe_refund_id then
    NEW.stripe_refund_id := OLD.stripe_refund_id;
  end if;

  v_old_status := lower(trim(coalesce(OLD.status, '')));
  v_frozen :=
    v_old_status in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor'
    )
    or coalesce(OLD.stripe_payment_intent_id, '') <> ''
    or coalesce(OLD.stripe_checkout_session_id, '') <> '';

  if v_frozen then
    if NEW.price_total is distinct from OLD.price_total then
      NEW.price_total := OLD.price_total;
    end if;
    if NEW.quantity is distinct from OLD.quantity then
      NEW.quantity := OLD.quantity;
    end if;
    if NEW.payment_method is distinct from OLD.payment_method then
      NEW.payment_method := OLD.payment_method;
    end if;
    if NEW.product_id is distinct from OLD.product_id then
      NEW.product_id := OLD.product_id;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_money_cols on public.orders;
create trigger trg_batata_orders_guard_money_cols
  before insert or update on public.orders
  for each row
  execute function public.batata_orders_guard_money_cols();

comment on function public.batata_orders_guard_money_cols() is
  'FASE1: congela price/qty/Stripe/identidade pós-pago; bloqueia Stripe IDs pelo cliente.';

-- ---------------------------------------------------------------------------
-- 2) Wallet — sem INSERT autenticado com saldo inventado
-- ---------------------------------------------------------------------------

drop policy if exists "wallets_insert_own" on public.wallets;

revoke insert on table public.wallets from authenticated, anon;

-- create/ensure continua via SECURITY DEFINER batata_ensure_wallet (balance 0)
-- e service_role (Connect).

-- ---------------------------------------------------------------------------
-- 3) Payout atómico — débito condicional + ledger idempotente
-- ---------------------------------------------------------------------------

create table if not exists public.wallet_payout_ledger (
  idempotency_key text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  amount_eur numeric(12, 2) not null check (amount_eur > 0),
  status text not null check (status in ('debited', 'transferred', 'failed')),
  stripe_transfer_id text,
  balance_after numeric(12, 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists wallet_payout_ledger_transfer_uidx
  on public.wallet_payout_ledger (stripe_transfer_id)
  where stripe_transfer_id is not null;

alter table public.wallet_payout_ledger enable row level security;

drop policy if exists wallet_payout_ledger_select_own on public.wallet_payout_ledger;
create policy wallet_payout_ledger_select_own
  on public.wallet_payout_ledger
  for select
  to authenticated
  using (user_id = auth.uid());

-- Nenhuma INSERT/UPDATE policy para authenticated — só service_role / DEFINER.

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
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'status', v_existing.status,
      'stripe_transfer_id', v_existing.stripe_transfer_id,
      'balance_after', v_existing.balance_after,
      'amount_cents', v_existing.amount_cents
    );
  end if;

  v_eur := round((p_amount_cents::numeric) / 100.0, 2);

  update public.wallets
  set balance = balance - v_eur,
      updated_at = now()
  where id = p_user_id
    and balance >= v_eur
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

create or replace function public.batata_wallet_payout_finish(
  p_idempotency_key text,
  p_stripe_transfer_id text,
  p_failed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_row public.wallet_payout_ledger%rowtype;
begin
  select * into v_row
  from public.wallet_payout_ledger
  where idempotency_key = trim(p_idempotency_key)
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_row.status = 'transferred' then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'status', 'transferred',
      'stripe_transfer_id', v_row.stripe_transfer_id
    );
  end if;

  if p_failed then
    if v_row.status = 'debited' then
      update public.wallets
      set balance = balance + v_row.amount_eur,
          updated_at = now()
      where id = v_row.user_id;

      update public.wallet_payout_ledger
      set status = 'failed', updated_at = now()
      where idempotency_key = v_row.idempotency_key;

      insert into public.wallet_transactions (
        wallet_id, amount, type, description
      ) values (
        v_row.user_id,
        v_row.amount_eur,
        'reembolso',
        'Reversão levantamento falhado ' || v_row.idempotency_key
      );
    end if;
    return jsonb_build_object('ok', true, 'status', 'failed');
  end if;

  if p_stripe_transfer_id is null or length(trim(p_stripe_transfer_id)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'missing_transfer_id');
  end if;

  update public.wallet_payout_ledger
  set status = 'transferred',
      stripe_transfer_id = trim(p_stripe_transfer_id),
      updated_at = now()
  where idempotency_key = v_row.idempotency_key;

  update public.wallet_transactions
  set description = 'Levantamento para conta bancária (' || trim(p_stripe_transfer_id) || ')'
  where wallet_id = v_row.user_id
    and type = 'levantamento'
    and description = 'Levantamento pendente ' || v_row.idempotency_key;

  return jsonb_build_object(
    'ok', true,
    'status', 'transferred',
    'stripe_transfer_id', trim(p_stripe_transfer_id),
    'balance_after', v_row.balance_after
  );
end;
$fn$;

revoke all on function public.batata_wallet_payout_debit(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.batata_wallet_payout_finish(text, text, boolean) from public, anon, authenticated;
grant execute on function public.batata_wallet_payout_debit(uuid, integer, text) to service_role;
grant execute on function public.batata_wallet_payout_finish(text, text, boolean) to service_role;

notify pgrst, 'reload schema';
