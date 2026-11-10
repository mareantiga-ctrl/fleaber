-- =============================================================================
-- BATATA — Blind B 1245/1250 + Indep residuals accionáveis (staging)
-- P0 refund→release: Edge refund-order (deploy separado)
-- Não remove features; não enfraquece RLS; sem produção/Fase 4.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RTB3-P1-01 — rifa exige can_manage_raffles (não só ver dashboard)
-- Owner continua OK via batata_staff_has_permission (uid = seller).
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_raffle_assert_seller(p_live_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_seller uuid;
begin
  v_seller := public.batata_live_raffle_live_seller(p_live_id);
  if v_seller is null then
    raise exception 'live_not_found';
  end if;
  if auth.uid() is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_manage_raffles') then
    raise exception 'not_allowed';
  end if;
  return v_seller;
end;
$$;

revoke all on function public.batata_live_raffle_assert_seller(uuid)
  from public, anon;
grant execute on function public.batata_live_raffle_assert_seller(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RTB3-P1-02 — provas: counterparty só na pasta da encomenda partilhada
-- Path app: order_proofs/{buyer_uid}/{order_id}/…
-- ---------------------------------------------------------------------------
drop policy if exists fleaber_private_select_order_counterparty on storage.objects;
create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and name like (
              'order_proofs/' || o.buyer_id::text || '/' || o.id::text || '/%'
            )
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where (o.seller_id = auth.uid() or o.buyer_id = auth.uid())
            and (
              name like ('order_disputes/' || o.buyer_id::text || '/%')
              or name like ('order_disputes/' || o.seller_id::text || '/%')
            )
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- RTB3-P2-01 — tip Stripe exige live_id + seller do directo
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_live_tip_pending(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null,
  p_stripe_session_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_live_seller uuid;
  v_note text;
  v_amount numeric;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if p_live_id is null then
    raise exception 'Direto obrigatório para gorjeta.';
  end if;

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;
  if v_amount > 500 then
    raise exception 'Valor máximo de gorjeta: 500 €.';
  end if;

  select coalesce(seller_id, vendedor_id) into v_live_seller
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto não encontrado.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este direto.';
  end if;

  v_fee := public.batata_live_tip_processing_fee(v_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(v_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    stripe_session_id
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    v_amount,
    v_fee,
    v_seller_amount,
    v_note,
    'stripe',
    'pending',
    nullif(trim(coalesce(p_stripe_session_id, '')), '')
  )
  returning id into v_tip_id;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RTB3-P2-03 — idempotency_key de payout não é global entre users
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

revoke all on function public.batata_wallet_payout_debit(uuid, integer, text)
  from public, anon, authenticated;
grant execute on function public.batata_wallet_payout_debit(uuid, integer, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- CEGA-P3-01 — stock live sem anon
-- ---------------------------------------------------------------------------
revoke all on function public.batata_live_item_stock(uuid) from public, anon;
grant execute on function public.batata_live_item_stock(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RTB-B-1245 defesa em profundura no release: event refund_created
-- (cobre crash antigo sem stripe_refund_id na row)
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

  -- Evento de refund já escrito (ou crash antigo com finalize parcial)
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
