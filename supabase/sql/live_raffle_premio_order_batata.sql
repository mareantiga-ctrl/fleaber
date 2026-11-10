-- Fleaber BATATA: encomenda «Prémio da Rifa» (irmão gémeo do pago, sem dinheiro).
-- Executar no SQL Editor staging DEPOIS de live_raffle_prize_stock_batata.sql.
--
-- Efeito:
-- 1) status orders.premio_rifa (label UI: «Prémio da Rifa» — nunca «Pago»)
-- 2) no sorteio: cria encomenda 0€ para cada vencedor + chat
-- 3) hold da rifa só em active/closed; após draw a encomenda bloqueia o stock

-- ---------------------------------------------------------------------------
-- 1) Coluna + constraint de status
-- ---------------------------------------------------------------------------
alter table public.orders
  add column if not exists live_raffle_id uuid references public.live_raffles (id) on delete set null;

create index if not exists orders_live_raffle_id_idx
  on public.orders (live_raffle_id)
  where live_raffle_id is not null;

create unique index if not exists orders_live_raffle_winner_uidx
  on public.orders (live_raffle_id, buyer_id)
  where live_raffle_id is not null
    and lower(trim(coalesce(status, ''))) = 'premio_rifa'
    and coalesce(status, '') not in ('cancelado', 'cancelled');

comment on column public.orders.live_raffle_id is
  'Rifa que originou a encomenda-prémio (status premio_rifa).';

alter table public.orders drop constraint if exists orders_status_batata_check;
alter table public.orders
  add constraint orders_status_batata_check
  check (
    status is null
    or status in (
      'reserva_pendente',
      'reservado',
      'pendente',
      'aguarda_confirmacao',
      'pago',
      'premio_rifa',
      'enviado',
      'entregue',
      'concluido',
      'cancelado',
      'pedido_devolucao',
      'em_devolucao',
      'devolucao_entregue',
      'disputa_devolucao_vendedor',
      'devolvida'
    )
  );

-- ---------------------------------------------------------------------------
-- 2) Hold: só enquanto rifa activa/fechada (drawn → encomenda)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3) Stock: premio_rifa bloqueia como pago
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
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id
      and exists (
        select 1 from public.lives l2
        where l2.id = li2.live_id
          and coalesce(l2.seller_id, l2.vendedor_id) = v_seller
      );
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
  where lower(trim(coalesce(o.status, ''))) in ('pago', 'premio_rifa', 'enviado', 'concluido')
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
    'available_qty', v_available,
    'cross_reserved_qty', v_blocked_cross_res,
    'raffle_hold_qty', v_raffle_hold,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

revoke all on function public.batata_live_item_stock(uuid) from public;
grant execute on function public.batata_live_item_stock(uuid) to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 4) Helper: cria encomenda + chat para 1 vencedor
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_raffle_prize_order(
  p_raffle_id uuid,
  p_winner_uid uuid,
  p_rank int default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_raffle public.live_raffles%rowtype;
  v_live public.lives%rowtype;
  v_li public.live_items%rowtype;
  v_seller uuid;
  v_product_id uuid;
  v_order_id uuid;
  v_chat_id uuid;
  v_title text;
  v_snap jsonb;
  v_avail int;
begin
  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    raise exception 'raffle_not_found';
  end if;

  if v_raffle.live_item_id is null then
    return null; -- prémio manual: sem encomenda de catálogo
  end if;

  select * into v_live from public.lives where id = v_raffle.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null then
    raise exception 'seller_missing';
  end if;

  select * into v_li from public.live_items where id = v_raffle.live_item_id;
  if v_li.id is null then
    raise exception 'live_item_not_found';
  end if;

  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);
  if v_product_id is null then
    begin
      v_product_id := public.batata_ensure_checkout_product(v_li.id);
    exception when others then
      raise exception 'prize_product_missing';
    end;
  end if;

  -- Idempotente: já existe encomenda desta rifa para este vencedor.
  select o.id into v_order_id
  from public.orders o
  where o.live_raffle_id = p_raffle_id
    and o.buyer_id = p_winner_uid
    and lower(trim(coalesce(o.status, ''))) = 'premio_rifa'
  limit 1;

  if v_order_id is not null then
    return v_order_id;
  end if;

  v_title := coalesce(nullif(trim(v_raffle.title), ''), nullif(trim(v_li.title), ''), 'Prémio da Rifa');

  insert into public.orders (
    product_id,
    buyer_id,
    seller_id,
    price_total,
    shipping_method,
    payment_method,
    status,
    is_reservation,
    quantity,
    live_id,
    live_item_id,
    live_raffle_id
  ) values (
    v_product_id,
    p_winner_uid,
    v_seller,
    0,
    'Envio a cargo do vencedor',
    'Prémio da Rifa',
    'premio_rifa',
    false,
    1,
    v_raffle.live_id,
    v_li.id,
    p_raffle_id
  )
  returning id into v_order_id;

  -- Sempre conversa NOVA por sorteio (mesmo artigo + mesmo vencedor).
  -- Reutilizar o chat antigo misturava cards «Artigo enviado» da rifa anterior.
  insert into public.chats (user_a, user_b, product_id, last_message, last_message_time)
  values (
    p_winner_uid,
    v_seller,
    v_product_id,
    'Prémio da Rifa · envio a teu cargo',
    now()
  )
  returning id into v_chat_id;

  insert into public.chat_messages (
    sender_id,
    receiver_id,
    is_read,
    text,
    chat_id,
    is_reservation
  ) values (
    v_seller,
    p_winner_uid,
    false,
    'FLEABER_JSON_V1:' || jsonb_build_object(
      'kind', 'raffle_prize_awarded',
      'order_id', v_order_id,
      'raffle_id', p_raffle_id,
      'message', 'Este artigo é teu (Prémio da Rifa). Escolhe como o queres receber. Se comprares mais nesta loja, podes pedir para ir tudo no mesmo pacote.',
      'v', 1
    )::text,
    v_chat_id,
    true
  );

  update public.chats
  set last_message = 'Prémio da Rifa · envio a teu cargo',
      last_message_time = now()
  where id = v_chat_id;

  -- Se o stock restante for 0, marca sold (como qty=1).
  begin
    if public.batata_live_item_total_qty(v_li.id) <= greatest(v_raffle.winner_count, 1) then
      perform public.batata_mark_live_item_sold(v_li.id);
    end if;
  exception when others then
    null;
  end;

  -- Marketplace: se Disp. esgotou (prémio + hold), tira do feed como venda normal.
  begin
    v_snap := public.batata_live_item_stock(v_li.id);
    v_avail := coalesce((v_snap->>'available_qty')::int, 0);
    if v_avail < 1 and v_product_id is not null then
      update public.products
         set quantity = 0,
             is_sold = true,
             list_on_marketplace = false
       where id = v_product_id;
    end if;
  exception when others then
    null;
  end;

  return v_order_id;
end;
$$;

revoke all on function public.batata_create_raffle_prize_order(uuid, uuid, int) from public;
grant execute on function public.batata_create_raffle_prize_order(uuid, uuid, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Draw: sorteia + cria encomenda premio_rifa por vencedor
-- ---------------------------------------------------------------------------
create or replace function public.batata_draw_live_raffle_winners(p_raffle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.live_raffles%rowtype;
  v_seed text;
  v_rank int;
  v_needed int;
  v_total_weight bigint;
  v_pick bigint;
  v_cursor bigint := 0;
  v_winner record;
  v_winners jsonb := '[]'::jsonb;
  v_participants int;
  v_winner_name text;
  v_winner_uid uuid;
  v_order_id uuid;
  v_prize_orders jsonb := '[]'::jsonb;
begin
  select * into v_row from public.live_raffles where id = p_raffle_id for update;
  if v_row.id is null then
    raise exception 'raffle_not_found';
  end if;

  perform public.batata_live_raffle_assert_seller(v_row.live_id);

  if v_row.status = 'active' then
    if v_row.ends_at is not null and v_row.ends_at <= now() then
      update public.live_raffles set status = 'closed' where id = p_raffle_id
      returning * into v_row;
    else
      raise exception 'raffle_still_active';
    end if;
  end if;

  if v_row.status <> 'closed' then
    raise exception 'invalid_status';
  end if;

  select count(*)::int into v_participants
  from public.live_raffle_entries e
  where e.raffle_id = p_raffle_id
    and e.is_eligible
    and e.ticket_balance > 0;

  if v_participants < 1 then
    raise exception 'no_participants';
  end if;

  v_seed := encode(extensions.gen_random_bytes(32), 'hex');
  v_needed := least(v_row.winner_count, v_participants);

  for v_rank in 1..v_needed loop
    select coalesce(sum(e.ticket_balance), 0)::bigint into v_total_weight
    from public.live_raffle_entries e
    where e.raffle_id = p_raffle_id
      and e.is_eligible
      and e.ticket_balance > 0
      and not exists (
        select 1 from public.live_raffle_winners w
        where w.raffle_id = p_raffle_id and w.user_id = e.user_id
      );

    if v_total_weight < 1 then
      exit;
    end if;

    v_pick := (abs(hashtextextended(v_seed || ':' || v_rank::text, 0)) % v_total_weight) + 1;
    v_cursor := 0;

    for v_winner in
      select e.id as entry_id, e.user_id, e.ticket_balance
      from public.live_raffle_entries e
      where e.raffle_id = p_raffle_id
        and e.is_eligible
        and e.ticket_balance > 0
        and not exists (
          select 1 from public.live_raffle_winners w
          where w.raffle_id = p_raffle_id and w.user_id = e.user_id
        )
      order by e.id
    loop
      v_cursor := v_cursor + v_winner.ticket_balance;
      if v_cursor >= v_pick then
        insert into public.live_raffle_winners (
          raffle_id, user_id, entry_id, rank, tickets_at_draw, draw_proof
        ) values (
          p_raffle_id,
          v_winner.user_id,
          v_winner.entry_id,
          v_rank,
          v_winner.ticket_balance,
          jsonb_build_object(
            'seed', v_seed,
            'rank', v_rank,
            'pick', v_pick,
            'weight', v_total_weight
          )
        );

        v_winners := v_winners || jsonb_build_array(
          jsonb_build_object(
            'rank', v_rank,
            'user_id', v_winner.user_id,
            'tickets_at_draw', v_winner.ticket_balance
          )
        );

        begin
          v_order_id := public.batata_create_raffle_prize_order(
            p_raffle_id, v_winner.user_id, v_rank
          );
          if v_order_id is not null then
            v_prize_orders := v_prize_orders || jsonb_build_array(
              jsonb_build_object(
                'user_id', v_winner.user_id,
                'order_id', v_order_id
              )
            );
          end if;
        exception when others then
          -- Não falhar o sorteio se a encomenda falhar (ex. sem product_id).
          null;
        end;

        exit;
      end if;
    end loop;
  end loop;

  if jsonb_array_length(v_winners) < 1 then
    raise exception 'draw_failed';
  end if;

  update public.live_raffles
  set status = 'drawn',
      draw_seed = v_seed,
      drawn_at = now()
  where id = p_raffle_id
  returning * into v_row;

  perform public.batata_live_raffle_audit(
    p_raffle_id,
    'drawn',
    jsonb_build_object(
      'seed', v_seed,
      'winners', v_winners,
      'prize_orders', v_prize_orders
    )
  );

  v_winner_uid := (v_winners->0->>'user_id')::uuid;
  select coalesce(nullif(trim(p.full_name), ''), 'Participante')
    into v_winner_name
  from public.profiles p
  where p.id = v_winner_uid;

  if v_winner_name is null then
    v_winner_name := 'Participante';
  end if;

  perform public.batata_live_raffle_social_broadcast(
    v_row.live_id,
    '🏆 ' || v_winner_name || ' ganhou a Rifa da Live! Parabéns!'
  );

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    v_row.live_id,
    v_winner_uid,
    'system',
    '🎟️ Rifa: Este artigo é teu. Pagas só o envio — e podes juntar mais peças desta vendedora no mesmo pacote.',
    'Rifa da Live'
  );

  return jsonb_build_object(
    'ok', true,
    'status', v_row.status,
    'draw_seed', v_seed,
    'winners', v_winners,
    'winner_name', v_winner_name,
    'prize_orders', v_prize_orders
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Stock: premio_rifa → pago NÃO volta a decrementar products.quantity
-- ---------------------------------------------------------------------------
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
begin
  if new.product_id is not null
     and lower(coalesce(new.status, '')) = 'pago'
     and (
       tg_op = 'INSERT'
       or lower(coalesce(old.status, '')) is distinct from lower(coalesce(new.status, ''))
     ) then
    -- Prémio da Rifa: stock já foi retido no sorteio — não decrementar de novo.
    if tg_op = 'UPDATE'
       and lower(coalesce(old.status, '')) = 'premio_rifa' then
      return new;
    end if;

    v_units := greatest(coalesce(new.quantity, 1), 1);

    select quantity into v_before
    from public.products
    where id = new.product_id;

    update public.products
       set quantity = greatest(coalesce(quantity, 1) - v_units, 0)
     where id = new.product_id
     returning quantity into v_remaining;

    raise log 'BATATA_STOCK order=% product=% units=% qty_before=% qty_after=%',
      new.id, new.product_id, v_units, v_before, v_remaining;

    if v_remaining is not null and v_remaining <= 0 then
      update public.products
         set is_sold = true,
             list_on_marketplace = false
       where id = new.product_id;
      raise log 'BATATA_STOCK esgotado product=% (is_sold=true, off marketplace)',
        new.product_id;
    elsif v_remaining is not null and v_remaining > 0 then
      update public.products
         set is_sold = false
       where id = new.product_id
         and is_sold = true;
      raise log 'BATATA_STOCK parcial product=% qty_remaining=%',
        new.product_id, v_remaining;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.batata_draw_live_raffle_winners(uuid) from public;
grant execute on function public.batata_draw_live_raffle_winners(uuid) to authenticated;
