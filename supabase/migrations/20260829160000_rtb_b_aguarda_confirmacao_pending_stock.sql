-- Migrated from sec_rtb_b_aguarda_confirmacao_pending_stock_batata.sql
-- RTB-B-BANK-01/02 + RT-E-P2-01

create or replace function public.batata_orders_guard_buyer_cannot_self_accept()
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
  v_is_buyer boolean;
  v_is_seller boolean;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := NEW.seller_id is not null and NEW.seller_id = v_uid;

  if not v_is_buyer or v_is_seller then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if v_new in (
      'reservado',
      'aguarda_confirmacao',
      'aguarda_pagamento',
      'pago',
      'enviado',
      'entregue',
      'concluido',
      'premio_rifa'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  if v_new in ('reservado', 'aguarda_pagamento')
     and v_old in ('reserva_pendente', 'pendente', '', 'aguarda_confirmacao') then
    NEW.status := OLD.status;
  end if;

  if v_new = 'aguarda_confirmacao'
     and v_old in ('reserva_pendente', 'pendente', '') then
    NEW.status := OLD.status;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_buyer_cannot_self_accept on public.orders;
create trigger trg_batata_orders_guard_buyer_cannot_self_accept
  before insert or update of status on public.orders
  for each row
  execute function public.batata_orders_guard_buyer_cannot_self_accept();

comment on function public.batata_orders_guard_buyer_cannot_self_accept() is
  'RTB-B-BANK: buyer JWT não INSERT/PATCH aguarda_confirmacao|reservado sem aceite; prova reservado→aguarda_confirmacao OK.';

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

  v_available := v_total - v_blocked - v_reserved_accepted;
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

comment on function public.batata_live_item_stock(uuid) is
  'APP-402 + RT-E-P2-01: available = total - blocked - accepted (pending_bag informativo, não consome).';

notify pgrst, 'reload schema';
