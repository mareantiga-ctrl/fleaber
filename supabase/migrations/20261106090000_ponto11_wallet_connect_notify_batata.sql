-- =============================================================================
-- ZIP 166 — Ponto 11 fecho: sync Connect + notify libertação/payout + fail transfer
-- Stripe LIVE OFF · sem alterar comissões / taxas · preserva ZIP 128/165
-- =============================================================================

-- 1) Estado Connect espelhado na carteira (account.updated)
alter table public.wallets
  add column if not exists stripe_connect_details_submitted boolean,
  add column if not exists stripe_connect_transfers_status text,
  add column if not exists stripe_connect_charges_enabled boolean,
  add column if not exists stripe_connect_payouts_enabled boolean,
  add column if not exists stripe_connect_synced_at timestamptz;

comment on column public.wallets.stripe_connect_transfers_status is
  'ZIP166: capabilities.transfers (active|pending|inactive) via account.updated';

-- 2) Sync Connect (só service_role / webhook)
create or replace function public.batata_sync_stripe_connect_account(
  p_user_id uuid,
  p_stripe_account_id text,
  p_details_submitted boolean,
  p_transfers_status text,
  p_charges_enabled boolean default null,
  p_payouts_enabled boolean default null,
  p_stripe_event_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_acc text := nullif(trim(coalesce(p_stripe_account_id, '')), '');
  v_tr text := lower(nullif(trim(coalesce(p_transfers_status, '')), ''));
begin
  if p_user_id is null or v_acc is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  insert into public.wallets (id, stripe_account_id, balance, updated_at)
  values (p_user_id, v_acc, 0, now())
  on conflict (id) do update
    set stripe_account_id = coalesce(excluded.stripe_account_id, wallets.stripe_account_id),
        updated_at = now();

  update public.wallets
  set stripe_account_id = v_acc,
      stripe_connect_details_submitted = coalesce(p_details_submitted, stripe_connect_details_submitted),
      stripe_connect_transfers_status = coalesce(v_tr, stripe_connect_transfers_status),
      stripe_connect_charges_enabled = coalesce(p_charges_enabled, stripe_connect_charges_enabled),
      stripe_connect_payouts_enabled = coalesce(p_payouts_enabled, stripe_connect_payouts_enabled),
      stripe_connect_synced_at = now(),
      updated_at = now()
  where id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'user_id', p_user_id,
    'stripe_account_id', v_acc,
    'transfers_status', v_tr,
    'stripe_event_id', p_stripe_event_id
  );
end;
$$;

revoke all on function public.batata_sync_stripe_connect_account(
  uuid, text, boolean, text, boolean, boolean, text
) from public, anon, authenticated;
grant execute on function public.batata_sync_stripe_connect_account(
  uuid, text, boolean, text, boolean, boolean, text
) to service_role;

-- 3) Falha de Transfer Stripe pós-debito / pós-transferred → repor saldo
create or replace function public.batata_wallet_payout_fail_by_transfer_id(
  p_stripe_transfer_id text,
  p_stripe_event_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.wallet_payout_ledger%rowtype;
  v_tid text := nullif(trim(coalesce(p_stripe_transfer_id, '')), '');
  v_fin jsonb;
begin
  if v_tid is null then
    return jsonb_build_object('ok', false, 'error', 'missing_transfer_id');
  end if;

  select * into v_row
  from public.wallet_payout_ledger
  where stripe_transfer_id = v_tid
  for update;

  if not found then
    return jsonb_build_object('ok', true, 'skipped', 'ledger_not_found', 'transfer_id', v_tid);
  end if;

  if v_row.status = 'failed' then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'status', 'failed',
      'idempotency_key', v_row.idempotency_key
    );
  end if;

  -- Reutiliza finish(failed) para debitado; se já transferred, reverte saldo.
  if v_row.status = 'debited' then
    v_fin := public.batata_wallet_payout_finish(v_row.idempotency_key, v_tid, true);
  elsif v_row.status = 'transferred' then
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
      'Reversão levantamento (transfer.failed) ' || v_tid
    );

    v_fin := jsonb_build_object('ok', true, 'status', 'failed', 'reversed_transferred', true);
  else
    v_fin := jsonb_build_object('ok', false, 'error', 'unexpected_status', 'status', v_row.status);
  end if;

  perform public.batata_emit_user_notification_trusted(
    v_row.user_id,
    'wallet_payout_failed',
    'Levantamento não concluído',
    'O Stripe não concluiu a transferência. O valor voltou ao teu saldo Fleaber.',
    null, null, null, null,
    'wallet_payout_fail:' || v_row.idempotency_key
  );

  return jsonb_build_object(
    'ok', true,
    'idempotency_key', v_row.idempotency_key,
    'finish', v_fin,
    'stripe_event_id', p_stripe_event_id
  );
end;
$$;

revoke all on function public.batata_wallet_payout_fail_by_transfer_id(text, text)
  from public, anon, authenticated;
grant execute on function public.batata_wallet_payout_fail_by_transfer_id(text, text)
  to service_role;

-- 4) Resumo saldos (vendedor autenticado = próprio; service_role qualquer)
create or replace function public.batata_seller_wallet_summary(p_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_bal numeric(12, 2) := 0;
  v_held numeric(12, 2) := 0;
  v_pending numeric(12, 2) := 0;
  v_risk text := 'clear';
  v_acc text;
  v_tr text;
  v_submitted boolean;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if auth.uid() is not null
     and auth.uid() is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_notify_is_service_role() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select coalesce(balance, 0),
         coalesce(held_balance, 0),
         coalesce(risk_status, 'clear'),
         stripe_account_id,
         stripe_connect_transfers_status,
         stripe_connect_details_submitted
    into v_bal, v_held, v_risk, v_acc, v_tr, v_submitted
  from public.wallets
  where id = v_uid;

  select coalesce(sum(coalesce(price_total, 0)), 0) into v_pending
  from public.orders
  where seller_id = v_uid
    and status in ('pago', 'enviado', 'em_devolucao')
    and wallet_release_processed_at is null;

  return jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'balance_eur', v_bal,
    'held_eur', v_held,
    'available_eur', greatest(v_bal - v_held, 0),
    'pending_orders_eur', v_pending,
    'risk_status', v_risk,
    'stripe_account_id', v_acc,
    'connect_transfers_status', v_tr,
    'connect_details_submitted', v_submitted
  );
end;
$$;

revoke all on function public.batata_seller_wallet_summary(uuid) from public, anon;
grant execute on function public.batata_seller_wallet_summary(uuid)
  to authenticated, service_role;

-- 5) Notificar após crédito de venda (libertação) — patch pontual via wrapper
create or replace function public.batata_notify_wallet_funds_released(
  p_seller_id uuid,
  p_order_id uuid,
  p_amount_eur numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amt text;
  v_nid uuid;
begin
  if p_seller_id is null or p_order_id is null or coalesce(p_amount_eur, 0) <= 0 then
    return null;
  end if;
  v_amt := trim(to_char(round(p_amount_eur, 2), 'FM999999990.00'));
  v_nid := public.batata_emit_user_notification_trusted(
    p_seller_id,
    'wallet_funds_released',
    'Saldo libertado',
    'Foram creditados ' || v_amt || ' € na tua carteira Fleaber.',
    null, null, null, null,
    'wallet_release:' || p_order_id::text
  );
  return v_nid;
end;
$$;

revoke all on function public.batata_notify_wallet_funds_released(uuid, uuid, numeric)
  from public, anon, authenticated;
grant execute on function public.batata_notify_wallet_funds_released(uuid, uuid, numeric)
  to service_role;

-- Repor release com notify (corpo = ZIP 128 + notify)
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

  if v_order.funds_hold_until is not null
     and v_order.funds_hold_until > now() then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_dispute_status), ''), '') <> ''
     and lower(v_order.stripe_dispute_status) not in (
       'won', 'lost', 'warning_closed', 'charge_refunded'
     ) then
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
    -- ZIP 166: notificação in-app (sem email comercial novo)
    perform public.batata_notify_wallet_funds_released(
      v_order.seller_id, v_order.id, v_amount
    );
  end if;
  return v_done;
end;
$$;

revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

-- 6) Notificar payout OK (chamado pela Edge create-connect-account)
create or replace function public.batata_notify_wallet_payout_sent(
  p_user_id uuid,
  p_amount_eur numeric,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amt text;
  v_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
begin
  if p_user_id is null or coalesce(p_amount_eur, 0) <= 0 or v_key is null then
    return null;
  end if;
  v_amt := trim(to_char(round(p_amount_eur, 2), 'FM999999990.00'));
  return public.batata_emit_user_notification_trusted(
    p_user_id,
    'wallet_payout_sent',
    'Levantamento enviado',
    'Transferimos ' || v_amt || ' € para a tua conta Stripe Connect.',
    null, null, null, null,
    'wallet_payout_ok:' || v_key
  );
end;
$$;

revoke all on function public.batata_notify_wallet_payout_sent(uuid, numeric, text)
  from public, anon, authenticated;
grant execute on function public.batata_notify_wallet_payout_sent(uuid, numeric, text)
  to service_role;
