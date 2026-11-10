-- RTBB-B-01 + RTBB-B-02 (staging BATATA)
-- B-02 BUG: batata_live_item_stock só contava sold status=pago → após enviado/entregue
--           available_qty reabria (live_only / pool).
-- B-01 HOLD: 2× reservado + 2× Checkout Session em quantity=1.
--   → capacidade ao entrar em reservado/aguarda_* + checkout conta holds.
-- Preserva: 1 unidade → 1 reservado → 1 Session; settle oversell refund intacto.
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- Helpers: holds que ainda NÃO baixaram products.quantity
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_status_holds_product_qty(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'reservado',
    'aguarda_confirmacao',
    'aguarda_pagamento'
  );
$$;

create or replace function public.batata_order_status_is_sold_fulfilled(p_status text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_status, ''))) in (
    'pago', 'paid',
    'enviado',
    'entregue',
    'concluido', 'concluído',
    'premio_rifa'
  );
$$;

-- Qty já «em jogo» noutros orders do mesmo produto (holds pré-pago).
create or replace function public.batata_product_held_qty(
  p_product_id uuid,
  p_exclude_order_id uuid default null,
  p_exclude_order_ids uuid[] default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_held int := 0;
begin
  if p_product_id is null then
    return 0;
  end if;
  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = p_product_id
    and (p_exclude_order_id is null or o.id is distinct from p_exclude_order_id)
    and (
      p_exclude_order_ids is null
      or cardinality(p_exclude_order_ids) = 0
      or not (o.id = any (p_exclude_order_ids))
    )
    and coalesce(o.status, '') not in (
      'cancelado', 'cancelled', 'rejected', 'expired'
    )
    and public.batata_order_status_holds_product_qty(o.status);
  return v_held;
end;
$$;

drop function if exists public.batata_product_held_qty(uuid, uuid);
revoke all on function public.batata_product_held_qty(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.batata_product_held_qty(uuid, uuid, uuid[])
  to authenticated, service_role;

-- Checkout: lock + stock efectivo (quantity - holds alheios).
create or replace function public.batata_product_checkout_available(
  p_product_id uuid,
  p_exclude_order_id uuid,
  p_need_qty integer,
  p_exclude_order_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock int;
  v_held int;
  v_avail int;
  v_need int := greatest(coalesce(p_need_qty, 1), 1);
  v_excl uuid[] := coalesce(p_exclude_order_ids, array[]::uuid[]);
begin
  if p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_product');
  end if;

  perform pg_advisory_xact_lock(hashtext(p_product_id::text || ':checkout_stock'));

  select p.quantity into v_stock
  from public.products p
  where p.id = p_product_id
  for update;

  if v_stock is null then
    return jsonb_build_object('ok', false, 'error', 'product_not_found');
  end if;

  if p_exclude_order_id is not null
     and not (p_exclude_order_id = any (v_excl)) then
    v_excl := array_append(v_excl, p_exclude_order_id);
  end if;

  v_held := public.batata_product_held_qty(p_product_id, null, v_excl);
  -- Orders excluídos (este / saco) não entram em v_held; precisam de v_need.
  v_avail := greatest(v_stock - v_held, 0);

  return jsonb_build_object(
    'ok', v_avail >= v_need,
    'stock', v_stock,
    'held', v_held,
    'available', v_avail,
    'need', v_need
  );
end;
$$;

drop function if exists public.batata_product_checkout_available(uuid, uuid, integer);
revoke all on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[])
  from public, anon;
grant execute on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[])
  to authenticated, service_role;

comment on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[]) is
  'RTBB-B-01: stock efectivo para criar Checkout Session (advisory lock).';

-- ---------------------------------------------------------------------------
-- B-01: ao passar a reservado/aguarda_*, respeitar capacidade do produto
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_product_hold_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_new text;
  v_old text;
  v_need int;
  v_check jsonb;
begin
  -- service_role / settle: não bloquear (oversell → refund path).
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if NEW.product_id is null then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_old := case when TG_OP = 'UPDATE'
    then lower(trim(coalesce(OLD.status, '')))
    else '' end;

  if not public.batata_order_status_holds_product_qty(v_new) then
    return NEW;
  end if;

  -- Só quando entra em hold (INSERT hold, ou UPDATE para hold a partir de outro estado)
  if TG_OP = 'UPDATE'
     and public.batata_order_status_holds_product_qty(v_old)
     and v_new is not distinct from v_old then
    return NEW;
  end if;

  v_need := greatest(coalesce(NEW.quantity, 1), 1);
  v_check := public.batata_product_checkout_available(
    NEW.product_id,
    NEW.id,
    v_need
  );

  if coalesce((v_check->>'ok')::boolean, false) is not true then
    raise exception 'order_hold_exceeds_stock'
      using errcode = '23514';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_product_hold_capacity on public.orders;
create trigger trg_batata_orders_guard_product_hold_capacity
  before insert or update of status, quantity, product_id
  on public.orders
  for each row
  execute function public.batata_orders_guard_product_hold_capacity();

comment on function public.batata_orders_guard_product_hold_capacity() is
  'RTBB-B-01: JWT não cria 2º hold reservado quando stock=1 já está em hold.';

-- ---------------------------------------------------------------------------
-- B-02: sold inclui logística + live_only desconta sold do available
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_item_stock(p_live_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_total integer;
  v_blocked integer := 0;
  v_blocked_orders integer := 0;
  v_blocked_cross_res integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_unit_price numeric;
  v_live_only boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  v_live_only := lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only';

  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'pendente',
        'pedido_devolucao', 'em_devolucao'
      );

    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and lower(trim(li2.ref_code)) = lower(trim(v_li.ref_code))
      and coalesce(l2.seller_id, l2.vendedor_id) = v_seller;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
        and (
          o.live_item_id = v_li.id
          or (
            o.live_id = v_li.live_id
            and v_product_id is not null
            and o.product_id = v_product_id
          )
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'converted';

  -- RTBB-B-02: pago + logística (+ claim stock) contam como vendido
  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where (
      public.batata_order_status_is_sold_fulfilled(o.status)
      or coalesce(o.stock_units_applied, 0) > 0
    )
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);

  -- marketplace: total = products.quantity (já desce no pago) — não voltar a subtrair sold.
  -- live_only / pool: total estável — descontar sold (senão reabre após enviado).
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;

  if v_available < 0 then
    v_available := 0;
  end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p
    where p.id = v_li.product_id;
  else
    v_unit_price := v_li.price;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'live_id', v_li.live_id,
    'item_kind', v_li.item_kind,
    'product_id', v_li.product_id,
    'checkout_product_id', v_li.checkout_product_id,
    'ref_code', v_li.ref_code,
    'total_qty', v_total,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved_accepted,
    'pending_bag_qty', v_pending_bag,
    'sold_converted_qty', v_sold_converted,
    'available_qty', v_available,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

revoke all on function public.batata_live_item_stock(uuid) from public;
grant execute on function public.batata_live_item_stock(uuid) to authenticated;

comment on function public.batata_live_item_stock(uuid) is
  'APP-402 + RT-E-P2 + RTBB-B-02: live_only desconta sold incl. enviado/entregue/concluido.';

-- ---------------------------------------------------------------------------
-- B-02 gate de accept: usava só reservas accepted|converted — ignorava orders sold.
-- Alinhar a batata_live_item_stock.available_qty (já com logística).
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_accept_available(
  p_live_item_id uuid,
  p_exclude_request_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_stock jsonb;
  v_avail int := 0;
  v_excl_qty int := 0;
  v_excl_status text;
begin
  if p_live_item_id is null then
    return 0;
  end if;

  v_stock := public.batata_live_item_stock(p_live_item_id);
  if coalesce((v_stock->>'ok')::boolean, false) is not true then
    return 0;
  end if;
  v_avail := greatest(coalesce((v_stock->>'available_qty')::int, 0), 0);

  -- available já desconta accepted|converted. Se excluirmos uma row que já consumia,
  -- devolver essa qty para a validação do UPDATE (ex.: aumento de qty).
  if p_exclude_request_id is not null then
    select r.requested_qty, r.status
      into v_excl_qty, v_excl_status
    from public.live_reservation_requests r
    where r.id = p_exclude_request_id
      and r.live_item_id = p_live_item_id;
    if public.batata_live_reservation_status_consumes_capacity(v_excl_status) then
      v_avail := v_avail + greatest(coalesce(v_excl_qty, 0), 0);
    end if;
  end if;

  return greatest(v_avail, 0);
end;
$fn$;

revoke all on function public.batata_live_reservation_accept_available(uuid, uuid)
  from public, anon;
grant execute on function public.batata_live_reservation_accept_available(uuid, uuid)
  to authenticated, service_role;

comment on function public.batata_live_reservation_accept_available(uuid, uuid) is
  'RTBB-B-02: accept capacity = live_item_stock.available (sold incl. logística).';

notify pgrst, 'reload schema';
