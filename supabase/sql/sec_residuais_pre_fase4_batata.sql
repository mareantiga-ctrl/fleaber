-- =============================================================================
-- RESIDUAIS PRÉ-FASE 4 — cancel/refund finalize · amount_paid_cents · partial
-- Staging. Idempotente. NÃO baseline Fase 4.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Autoridade financeira: montante efectivamente liquidado (Stripe settle)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists amount_paid_cents integer;

comment on column public.orders.amount_paid_cents is
  'PRE-F4: cêntimos efectivamente pagos/settled (Stripe amount_received). '
  'Base preferida para refund parcial; MB WAY/directo pode ficar null → price_total pós-pago.';

-- Congelar amount_paid_cents no guard JWT (cliente não inventa)
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
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    NEW.amount_paid_cents := null;
    return NEW;
  end if;

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
  -- Cliente nunca define amount_paid_cents
  if NEW.amount_paid_cents is distinct from OLD.amount_paid_cents then
    NEW.amount_paid_cents := OLD.amount_paid_cents;
  end if;

  v_old_status := lower(trim(coalesce(OLD.status, '')));
  v_frozen :=
    v_old_status in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor'
    )
    or coalesce(OLD.stripe_payment_intent_id, '') <> ''
    or coalesce(OLD.stripe_checkout_session_id, '') <> ''
    or coalesce(OLD.amount_paid_cents, 0) > 0;

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

-- ---------------------------------------------------------------------------
-- Finalize atómico Stripe refund → cancelado (service_role / Edge)
-- Idempotente: retry após crash pós-Stripe.
-- ---------------------------------------------------------------------------
create or replace function public.batata_finalize_stripe_order_refund(
  p_order_id uuid,
  p_refund_id text,
  p_payment_intent_id text default null,
  p_session_id text default null,
  p_amount_cents integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_status text;
  v_already boolean := false;
begin
  if p_order_id is null or nullif(trim(coalesce(p_refund_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));

  if nullif(trim(coalesce(v_order.stripe_refund_id, '')), '') is not null then
    v_already := true;
    -- Garantir cancelado mesmo se refund já gravado (crash a meio).
    if v_status is distinct from 'cancelado' and v_status is distinct from 'cancelled' then
      update public.orders
      set status = 'cancelado'
      where id = p_order_id;
    end if;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'already_refunded', true,
      'refund_id', v_order.stripe_refund_id,
      'status', 'cancelado',
      'stock_units_applied', (
        select stock_units_applied from public.orders where id = p_order_id
      )
    );
  end if;

  update public.orders
  set
    stripe_refund_id = trim(p_refund_id),
    stripe_refunded_at = coalesce(stripe_refunded_at, now()),
    stripe_payment_intent_id = coalesce(
      nullif(trim(coalesce(p_payment_intent_id, '')), ''),
      stripe_payment_intent_id
    ),
    stripe_checkout_session_id = coalesce(
      nullif(trim(coalesce(p_session_id, '')), ''),
      stripe_checkout_session_id
    ),
    amount_paid_cents = coalesce(
      amount_paid_cents,
      case when p_amount_cents is not null and p_amount_cents > 0 then p_amount_cents else null end
    ),
    status = 'cancelado'
  where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'already_refunded', false,
    'refund_id', trim(p_refund_id),
    'status', 'cancelado',
    'stock_units_applied', (
      select stock_units_applied from public.orders where id = p_order_id
    )
  );
end;
$$;

revoke all on function public.batata_finalize_stripe_order_refund(uuid, text, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.batata_finalize_stripe_order_refund(uuid, text, text, text, integer)
  to service_role;

comment on function public.batata_finalize_stripe_order_refund(uuid, text, text, text, integer) is
  'PRE-F4: grava refund Stripe + cancelado atómico; retry idempotente; restock via trigger.';

-- ---------------------------------------------------------------------------
-- Partial refund: base = least(price_total, amount_paid_cents/100) quando pago Stripe
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_paid_eur numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute public.order_disputes%rowtype;
  v_status text;
  v_paid_ok boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);

  if p_order_id is null then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  elsif v_role is distinct from 'service_role' and v_uid is not null then
    if v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_release_processed_at is not null
     or v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  v_paid_ok := v_status in (
    'pago',
    'enviado',
    'entregue',
    'concluido',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );

  if not v_paid_ok then
    raise exception 'order_not_paid_for_refund';
  end if;

  select *
  into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and (
      lower(coalesce(d.seller_offer_type, '')) in (
        'partial_refund',
        'return_and_partial_refund'
      )
      or d.seller_offer_type is null
    )
  order by d.created_at desc
  limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);

  -- Autoridade: price_total comercial ∩ amount_paid_cents (Stripe settled) se existir.
  v_total := public.batata_order_amount(v_order);
  if coalesce(v_order.amount_paid_cents, 0) > 0 then
    v_paid_eur := round(v_order.amount_paid_cents::numeric / 100.0, 2);
    v_total := least(v_total, v_paid_eur);
  end if;

  if v_total <= 0 or v_percent <= 0 then
    return false;
  end if;

  v_refund := round(v_total * (v_percent / 100.0), 2);
  if v_refund <= 0 or v_refund > v_total then
    return false;
  end if;

  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(round(v_total - v_refund - v_commission, 2), 0);

  v_buyer_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_refund,
    'reembolso',
    'Reembolso parcial de ' || round(v_percent, 2)::text || '%'
  );

  v_seller_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_seller_amount,
    'venda',
    'Valor restante após reembolso parcial'
  );

  perform public.batata_record_fleaber_commission_once(
    v_order.id,
    v_commission,
    'protection_fee',
    'Taxa de Proteção Fleaber'
  );

  update public.orders
  set wallet_release_processed_at = now(),
      wallet_refund_processed_at = now()
  where id = v_order.id;

  update public.order_disputes
  set
    buyer_decision = coalesce(nullif(trim(buyer_decision), ''), 'accepted_partial_refund'),
    status = 'resolvida',
    current_turn = 'administracao',
    next_deadline = now()
  where id = v_dispute.id
    and lower(coalesce(status, '')) is distinct from 'resolvida';

  return v_buyer_done or v_seller_done;
end;
$$;

revoke all on function public.batata_process_partial_refund_dispute(uuid, numeric)
  from public, anon;
grant execute on function public.batata_process_partial_refund_dispute(uuid, numeric)
  to authenticated, service_role;

comment on function public.batata_process_partial_refund_dispute(uuid, numeric) is
  'PRE-F4: buyer-only; pós-pago; % disputa; base least(price_total, amount_paid_cents).';

notify pgrst, 'reload schema';
