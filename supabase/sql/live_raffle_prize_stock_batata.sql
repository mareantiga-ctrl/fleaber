-- Fleaber BATATA: prémio AM5 (live_item) sai do stock enquanto rifa active/closed;
-- volta se cancelada; fica fora se drawn (entregue ao vencedor).
-- Executar no SQL Editor staging (inclui coluna live_item_id se faltar).

alter table public.live_raffles
  add column if not exists live_item_id uuid references public.live_items (id) on delete set null;

create index if not exists live_raffles_live_item_idx
  on public.live_raffles (live_item_id)
  where live_item_id is not null;

-- Artigo: retém winner_count (mín. 1) unidades(s) — NÃO o stock inteiro.
-- Ex.: total 2 + rifa de 1 vencedor → hold 1 → available 1.
create or replace function public.batata_live_raffle_prize_hold_qty(p_live_item_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(greatest(r.winner_count, 1)), 0)::int
  from public.live_raffles r
  where r.live_item_id = p_live_item_id
    and r.status in ('active', 'closed');
$$;

revoke all on function public.batata_live_raffle_prize_hold_qty(uuid) from public;
grant execute on function public.batata_live_raffle_prize_hold_qty(uuid) to authenticated, anon;

-- Stock canónico (base hotfix) + hold da rifa.
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
  v_raffle_hold integer := 0;
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
        'pago', 'premio_rifa', 'enviado', 'reservado', 'aguarda_confirmacao',
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

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status in ('accepted', 'converted');

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live';

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where lower(trim(coalesce(o.status, ''))) in ('pago', 'premio_rifa')
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);
  v_raffle_hold := public.batata_live_raffle_prize_hold_qty(v_li.id);

  -- Sempre subtrair hold da rifa no available (fonte de verdade para marketplace/prep).
  -- Não depender de products.quantity já ter descido no sync.
  v_available := v_total - v_blocked - v_reserved_accepted - v_pending_bag - v_raffle_hold;
  if v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  elsif lower(trim(coalesce(v_li.status, ''))) = 'sold' then
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
    'raffle_hold_qty', v_raffle_hold,
    'available_qty', v_available,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

revoke all on function public.batata_live_item_stock(uuid) from public;
grant execute on function public.batata_live_item_stock(uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- NÃO redefinir batata_draw_live_raffle_winners neste ficheiro.
-- Se correres prize_stock DEPOIS de live_raffle_premio_order_batata.sql,
-- o sorteio deixa de criar encomenda premio_rifa + mensagem em Mensagens.
-- Draw canónico (com encomenda): live_raffle_premio_order_batata.sql
-- → CORRER POR ÚLTIMO entre os SQL da rifa.
-- ---------------------------------------------------------------------------
