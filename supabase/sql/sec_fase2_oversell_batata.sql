-- FASE 2 — oversell / stock atómico (P0-02)
-- NÃO altera Fase 1 (preço / wallet INSERT / payout).
-- Preserva claim stock_units_applied (idempotência por order).
-- Substitui greatest(qty - n, 0) por UPDATE … WHERE quantity >= n.

alter table public.orders
  add column if not exists stock_units_applied integer;

comment on column public.orders.stock_units_applied is
  'Unidades já descontadas de products.quantity; null = ainda não aplicado / sem consumo.';

create or replace function public.batata_mark_product_sold_on_paid_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_remaining int;
  v_claimed int;
  v_stock_rows int;
begin
  if new.product_id is null then
    return new;
  end if;

  if lower(coalesce(new.status, '')) <> 'pago' then
    return new;
  end if;

  if new.stock_units_applied is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) is not distinct from lower(coalesce(new.status, '')) then
    return new;
  end if;

  -- Prémio da Rifa: stock já retido no sorteio.
  if tg_op = 'UPDATE'
     and lower(coalesce(old.status, '')) = 'premio_rifa' then
    return new;
  end if;

  v_units := greatest(coalesce(new.quantity, 1), 1);

  -- Claim atómico: settle duplo (webhook + return) da MESMA order não desce 2×.
  update public.orders
     set stock_units_applied = v_units
   where id = new.id
     and stock_units_applied is null;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id
  for update;

  -- FASE2: consumo atómico — sem stock suficiente → aborta o UPDATE a «pago».
  update public.products
     set quantity = quantity - v_units
   where id = new.product_id
     and coalesce(quantity, 0) >= v_units
   returning quantity into v_remaining;
  get diagnostics v_stock_rows = row_count;

  if v_stock_rows = 0 then
    raise exception 'batata_stock_insufficient'
      using errcode = 'P0001',
            hint = 'order=' || new.id::text || ' product=' || new.product_id::text ||
                   ' units=' || v_units::text || ' qty_before=' || coalesce(v_before::text, 'null');
  end if;

  raise log 'BATATA_STOCK order=% product=% units=% qty_before=% qty_after=%',
    new.id, new.product_id, v_units, v_before, v_remaining;

  if v_remaining is not null and v_remaining <= 0 then
    update public.products
       set is_sold = true,
           list_on_marketplace = false
     where id = new.product_id;
  elsif v_remaining is not null and v_remaining > 0 then
    update public.products
       set is_sold = false
     where id = new.product_id
       and is_sold = true;
  end if;

  return new;
end;
$$;

create or replace function public.batata_restore_product_stock_on_cancelled_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_after int;
  v_old text;
  v_new text;
  v_pm text;
  v_cleared int;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if new.product_id is null then
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;
  if v_new not in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) and position('cancelad' in v_new) = 0
    and position('anulad' in v_new) = 0 then
    return new;
  end if;

  v_pm := lower(trim(coalesce(new.payment_method, '')));
  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    -- Prémio: stock não foi decrementado no pago pós-premio_rifa.
    update public.orders
       set stock_units_applied = null
     where id = new.id
       and stock_units_applied is not null;
    return new;
  end if;

  -- Só repõe unidades realmente consumidas (claim). Sem claim = sem consumo
  -- (ex.: oversell refund: nunca chegou a «pago» estável).
  v_units := new.stock_units_applied;
  if v_units is null or v_units <= 0 then
    return new;
  end if;

  -- Claim de restauro: retry/cancelamento repetido não soma 2×.
  update public.orders
     set stock_units_applied = null
   where id = new.id
     and stock_units_applied is not null;
  get diagnostics v_cleared = row_count;
  if v_cleared = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = new.product_id
   returning quantity into v_after;

  raise log
    'BATATA_STOCK restore order=% product=% units=% qty_before=% qty_after=% old_status=%',
    new.id, new.product_id, v_units, v_before, v_after, v_old;

  return new;
end;
$$;

-- Backfill: encomendas já pagas sem claim (legado) — evita restauro a falhar.
update public.orders o
set stock_units_applied = greatest(coalesce(o.quantity, 1), 1)
where o.stock_units_applied is null
  and lower(coalesce(o.status, '')) in (
    'pago', 'enviado', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  );

comment on function public.batata_mark_product_sold_on_paid_order() is
  'FASE2: desconto atómico products.quantity WHERE quantity >= units; claim stock_units_applied por order.';

comment on function public.batata_restore_product_stock_on_cancelled_order() is
  'FASE2: repõe só se stock_units_applied > 0; clear claim idempotente.';
