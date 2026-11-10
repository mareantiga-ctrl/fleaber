-- O3 1-A + O4 2-A — devolvida só após refund; parcial 100% plataforma exige Stripe
-- Staging: fxdknzrqjenzqcvnwqqq

-- ---------------------------------------------------------------------------
-- O3 1-A — PATCH devolvida bloqueado até stripe_refund_id (plataforma capturada)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
  v_captured boolean := false;
  v_platform boolean := false;
  v_pm text;
  v_ship text;
  v_stripe_refund text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'entregue', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_pm := coalesce(OLD.payment_method, NEW.payment_method);
  v_ship := coalesce(OLD.shipping_method, NEW.shipping_method);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';
  v_stripe_refund := coalesce(
    nullif(trim(coalesce(NEW.stripe_refund_id, OLD.stripe_refund_id)), ''),
    ''
  );

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  -- ---- Comprador ----
  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'entregue' and v_old is distinct from 'enviado' then
      raise exception 'order_entregue_requires_enviado' using errcode = '42501';
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'concluido' then
      if v_old = 'pago' then
        if not public.batata_shipping_method_is_hand(v_ship) then
          raise exception 'order_concluido_requires_shipped'
            using errcode = '42501';
        end if;
      elsif v_old not in (
        'enviado', 'entregue', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    if v_old in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) and v_new in ('enviado', 'entregue', 'pago', 'concluido') then
      raise exception 'order_return_in_progress' using errcode = '42501';
    end if;

    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;

      -- O3 1-A: plataforma capturada — dinheiro Stripe antes de stock restore
      if v_platform and v_captured and v_stripe_refund = '' then
        raise exception 'order_devolvida_requires_refund' using errcode = '42501';
      end if;
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'concluido' and not v_is_buyer then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_paid_status() is
  'D0820+NOP+O3: devolvida plataforma exige stripe_refund_id; sem abort devolução.';

-- ---------------------------------------------------------------------------
-- O4 2-A — parcial 100% com Stripe capturado: sem mint carteira; usar refund-order
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
  v_remaining numeric;
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
  v_platform boolean := false;
  v_captured boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  if p_order_id is null then return false; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    raise exception 'stripe_refund_already_exists';
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  if v_status not in (
    'pago', 'enviado', 'entregue', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    raise exception 'order_not_paid_for_refund';
  end if;

  v_platform := public.batata_is_platform_payment(v_order.payment_method);
  v_captured :=
    coalesce(v_order.amount_paid_cents, 0) > 0
    or coalesce(nullif(trim(v_order.stripe_payment_intent_id), ''), '') <> '';

  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
  end if;

  if v_order.wallet_release_processed_at is not null then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  if v_remaining <= 0 then
    raise exception 'no_wallet_remaining_for_refund';
  end if;

  select * into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and d.seller_offer_set_by is not null
    and d.seller_offer_set_by = v_order.seller_id
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and lower(coalesce(d.seller_offer_type, '')) in (
      'partial_refund', 'return_and_partial_refund'
    )
  order by d.created_at desc limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);

  -- O4 2-A: 100% com PI Stripe activo → refund-order, não carteira comprador
  if v_percent >= 100
     and v_platform
     and v_captured
     and coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') = '' then
    raise exception 'dispute_full_refund_requires_stripe' using errcode = '42501';
  end if;

  v_refund := round(least(v_total, v_remaining) * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(
    least(v_remaining - v_refund, greatest(v_total - v_refund - v_commission, 0)),
    0
  );

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id, v_order.id, v_refund, 'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
  else
    v_buyer_done := true;
  end if;

  if v_seller_amount > 0 then
    v_seller_done := public.batata_credit_wallet_once(
      v_order.seller_id, v_order.id, v_seller_amount, 'venda',
      'Venda residual após disputa #' || left(v_order.id::text, 8)
    );
  else
    v_seller_done := true;
  end if;

  if v_buyer_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return v_buyer_done and v_seller_done;
end;
$$;

comment on function public.batata_process_partial_refund_dispute(uuid, numeric) is
  'O4 2-A: parcial 100% plataforma exige Stripe refund-order; parcial <100% carteira.';
