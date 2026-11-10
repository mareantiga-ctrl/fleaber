-- Corrida 5 / APP-404: reserva aceite + encomenda PAGA não pode continuar
-- a contar como «reservas» nem a zerar disponíveis.
-- Idempotente. Staging: fxdknzrqjenzqcvnwqqq

-- 1) Stock: aceites com encomenda paga/enviada não entram em reserved_accepted.
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
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'reservado', 'aguarda_confirmacao',
        'pendente', 'pedido_devolucao', 'em_devolucao'
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

  -- Só reservas ACEITES ainda abertas (sem encomenda já paga/enviada).
  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
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
        and lower(trim(coalesce(o.status, ''))) in (
          'pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue'
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where lower(trim(coalesce(o.status, ''))) = 'pago'
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);

  v_available := v_total - v_blocked - v_reserved_accepted - v_pending_bag;
  if v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  elsif v_available < 0 then
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
grant execute on function public.batata_live_item_stock(uuid) to service_role;

-- 2) Ao sincronizar encomenda paga: marcar a reserva live como converted
--    (fila Operação deixa de mostrar «aguardar pagamento»).
create or replace function public.batata_sync_live_item_for_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_live_item_id uuid;
  v_status text;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  v_live_item_id := v_order.live_item_id;

  if v_live_item_id is null
     and v_order.live_id is not null
     and v_order.product_id is not null then
    select li.id into v_live_item_id
    from public.live_items li
    where li.live_id = v_order.live_id
      and li.product_id = v_order.product_id
    order by li.created_at desc
    limit 1;
  end if;

  if v_live_item_id is null then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_live_item');
  end if;

  if auth.uid() is not null
     and auth.uid() is distinct from v_order.seller_id
     and auth.uid() is distinct from v_order.buyer_id
     and not public.batata_staff_has_permission(
       v_order.seller_id, 'can_manage_reservations'
     ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  if v_status in ('pago', 'paid', 'enviado', 'concluido', 'concluído', 'entregue')
     and v_order.buyer_id is not null then
    update public.live_reservation_requests r
    set
      status = 'converted',
      notes = case
        when coalesce(r.notes, '') ilike '%direct_paid:%' then r.notes
        else coalesce(nullif(trim(r.notes), '') || ' | ', '') ||
          'direct_paid:' || p_order_id::text
      end,
      updated_at = now()
    where r.live_item_id = v_live_item_id
      and r.buyer_id = v_order.buyer_id
      and r.status in ('pending', 'accepted');
  end if;

  return public.batata_recompute_live_item_status(v_live_item_id);
end;
$$;

revoke all on function public.batata_sync_live_item_for_order(uuid) from public;
grant execute on function public.batata_sync_live_item_for_order(uuid) to authenticated;
grant execute on function public.batata_sync_live_item_for_order(uuid) to service_role;
