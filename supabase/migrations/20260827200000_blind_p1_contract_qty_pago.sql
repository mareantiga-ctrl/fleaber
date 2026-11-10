-- Blind P1-01 / P1-03 / P1-04 (pré-Fase 4). BATATA.
-- Staging: aplicar via linked. Produção NÃO.
-- P1-02 schema baseline = continua Fase 4.

-- ---------------------------------------------------------------------------
-- Colunas de contrato (snapshot na criação da order)
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists contract_unit_cents integer;

alter table public.orders
  add column if not exists contract_qty integer;

comment on column public.orders.contract_unit_cents is
  'P1-01: preço unitário autoritativo (cêntimos) selado na criação; catálogo posterior não manda.';
comment on column public.orders.contract_qty is
  'P1-03: quantidade autoritativa selada na criação.';

-- ---------------------------------------------------------------------------
-- Classificação platform vs off-platform
-- ---------------------------------------------------------------------------
create or replace function public.batata_is_off_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  select
    lower(trim(coalesce(p_method, ''))) ~
    '(mb[[:space:]_-]?way|transfer|transf\.?|directo|direto|pagamento directo|pagamento direto|entrega em m|em m[aã]o|levantamento|combinad)';
$$;

create or replace function public.batata_is_platform_payment(p_method text)
returns boolean
language sql
immutable
as $$
  -- Plataforma = NÃO off-platform (fail-closed: desconhecido bloqueia seller→pago)
  select not public.batata_is_off_platform_payment(p_method)
    and length(trim(coalesce(p_method, ''))) > 0;
$$;

revoke all on function public.batata_is_off_platform_payment(text) from public, anon;
revoke all on function public.batata_is_platform_payment(text) from public, anon;
grant execute on function public.batata_is_off_platform_payment(text)
  to authenticated, service_role;
grant execute on function public.batata_is_platform_payment(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- P1-01: selar contrato no INSERT
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_seal_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_unit_cents int := 0;
  v_li numeric;
  v_prod numeric;
  v_pt int;
begin
  -- Já selado (service_role re-insert / backfill): respeitar.
  if NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    return NEW;
  end if;

  -- Prémio rifa: itens 0 (só portes no checkout).
  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  -- Live item da order
  if NEW.live_item_id is not null then
    select li.price into v_li
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0 then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  -- Catálogo produto
  if v_unit_cents <= 0 and NEW.product_id is not null then
    select p.price into v_prod
    from public.products p
    where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_unit_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

  -- Proposta: payment_method indica proposta + price_total < catálogo → acordo
  if v_unit_cents > 0
     and NEW.price_total is not null
     and NEW.price_total > 0
     and lower(coalesce(NEW.payment_method, '')) like '%proposta%' then
    v_pt := greatest(1, round(NEW.price_total * 100)::int);
    if v_pt < v_unit_cents then
      v_unit_cents := v_pt;
    end if;
  end if;

  if v_unit_cents <= 0 then
    raise exception 'order_contract_price_missing' using errcode = '23514';
  end if;

  NEW.contract_unit_cents := v_unit_cents;
  NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
  NEW.quantity := NEW.contract_qty;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_seal_contract on public.orders;
create trigger trg_batata_orders_seal_contract
  before insert on public.orders
  for each row
  execute function public.batata_orders_seal_contract();

-- ---------------------------------------------------------------------------
-- P1-03 qty: fail-closed + JWT não aumenta
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_quantity_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_stock int;
  v_qty int;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.quantity is null or NEW.quantity < 1 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;
  if NEW.quantity > 99 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;

  -- UPDATE: comprador/vendedor JWT não mudam quantity (contrato).
  if TG_OP = 'UPDATE' and NEW.quantity is distinct from OLD.quantity then
    NEW.quantity := OLD.quantity;
    return NEW;
  end if;

  v_qty := NEW.quantity;

  if NEW.product_id is not null then
    select coalesce(p.quantity, 0) into v_stock
    from public.products p where p.id = NEW.product_id;
    if lower(trim(coalesce(NEW.status, ''))) not in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor', 'cancelado'
    ) then
      if v_stock < 1 then
        raise exception 'no_stock_for_order_quantity' using errcode = '23514';
      end if;
      if v_qty > v_stock then
        raise exception 'order_quantity_exceeds_stock' using errcode = '23514';
      end if;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_quantity_authority on public.orders;
create trigger trg_batata_orders_guard_quantity_authority
  before insert or update of quantity on public.orders
  for each row
  execute function public.batata_orders_guard_quantity_authority();

-- ---------------------------------------------------------------------------
-- Money cols: price_total + qty + payment_method + contract_* imutáveis JWT
-- ---------------------------------------------------------------------------
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
  if NEW.product_id is distinct from OLD.product_id then
    NEW.product_id := OLD.product_id;
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
  if NEW.amount_paid_cents is distinct from OLD.amount_paid_cents then
    NEW.amount_paid_cents := OLD.amount_paid_cents;
  end if;

  -- P1-B + P1-01: price_total e contrato imutáveis via JWT
  if NEW.price_total is distinct from OLD.price_total then
    NEW.price_total := OLD.price_total;
  end if;
  if NEW.contract_unit_cents is distinct from OLD.contract_unit_cents then
    NEW.contract_unit_cents := OLD.contract_unit_cents;
  end if;
  if NEW.contract_qty is distinct from OLD.contract_qty then
    NEW.contract_qty := OLD.contract_qty;
  end if;

  -- P1-03: quantity sempre congelada para JWT em UPDATE
  if NEW.quantity is distinct from OLD.quantity then
    NEW.quantity := OLD.quantity;
  end if;

  -- P1-04 / PAY-7: payment_method não muda via JWT (evitar Stripe→MB WAY)
  if NEW.payment_method is distinct from OLD.payment_method then
    NEW.payment_method := OLD.payment_method;
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

  -- reserved for future frozen-only fields
  if v_frozen then
    null;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'Blind 2026-08-27: money + contract + qty + payment_method imutáveis JWT.';

-- ---------------------------------------------------------------------------
-- P1-04: seller não marca pago em pagamento plataforma
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
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'premio_rifa',
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

    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'concluido' then
      if v_old not in (
        'enviado', 'entregue', 'pago', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    -- P1-04: Seguro Fleaber / Pagamento na app / Stripe → pago só via settle
    if v_new = 'pago' and v_old is distinct from 'pago' then
      if coalesce(OLD.amount_paid_cents, 0) <= 0
         and coalesce(OLD.stripe_payment_intent_id, '') = ''
         and public.batata_is_platform_payment(OLD.payment_method) then
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
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
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
  'DC+Blind: JWT status + P1-04 seller não fabrica pago em pagamento plataforma.';

-- Backfill contrato em orders pré-pago sem selo (uma vez; catálogo actual)
update public.orders o
set
  contract_unit_cents = greatest(1, round(coalesce(p.price, o.price_total, 0) * 100)::int),
  contract_qty = greatest(coalesce(o.quantity, 1), 1)
from public.products p
where o.product_id = p.id
  and o.contract_unit_cents is null
  and lower(trim(coalesce(o.status, ''))) not in (
    'pago', 'enviado', 'entregue', 'concluido', 'cancelado', 'devolvida'
  )
  and coalesce(p.price, 0) > 0;

notify pgrst, 'reload schema';
