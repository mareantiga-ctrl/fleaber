-- =============================================================================
-- P0-01 raffle prize authority (BATATA)
-- Comprador autenticado NÃO pode fabricar/transformar order em prémio financeiro.
-- Autoridade: live_raffle_id + vencedor (live_raffle_winners) + produto da rifa.
-- Fluxo legítimo: batata_draw_live_raffle_winners → batata_create_raffle_prize_order
--   (SECURITY DEFINER + set_config batata.raffle_prize_write).
-- Idempotente.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Flag de escrita autorizada (só RPCs DEFINER de prémio)
-- ---------------------------------------------------------------------------
-- Usado por batata_create_raffle_prize_order antes do INSERT.

-- ---------------------------------------------------------------------------
-- 2) Guard: authenticated não forja premio_rifa / live_raffle_id / pm prémio
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_raffle_prize_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_allow text := coalesce(current_setting('batata.raffle_prize_write', true), '');
  v_new_status text;
  v_old_status text;
  v_pm text;
begin
  -- service_role / SQL Editor / bypass explícito da RPC de prémio
  if v_allow = '1' then
    return NEW;
  end if;
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new_status := lower(trim(coalesce(NEW.status, '')));
  v_pm := lower(trim(coalesce(NEW.payment_method, '')));

  if TG_OP = 'INSERT' then
    -- Nunca criar já como prémio via PostgREST.
    if v_new_status = 'premio_rifa' then
      NEW.status := 'reserva_pendente';
    end if;
    if NEW.live_raffle_id is not null then
      NEW.live_raffle_id := null;
    end if;
    if v_pm like '%premio%rifa%'
       or v_pm like '%prémio%rifa%'
       or v_pm like '%premio_rifa%' then
      NEW.payment_method := 'Pagamento na app';
    end if;
    return NEW;
  end if;

  -- UPDATE
  v_old_status := lower(trim(coalesce(OLD.status, '')));

  -- Não permitir saltar para premio_rifa.
  if v_new_status = 'premio_rifa' and v_old_status is distinct from 'premio_rifa' then
    NEW.status := OLD.status;
  end if;

  -- live_raffle_id imutável pelo cliente (só RPC autorizada).
  if NEW.live_raffle_id is distinct from OLD.live_raffle_id then
    NEW.live_raffle_id := OLD.live_raffle_id;
  end if;

  -- payment_method de prémio não pode ser injectado pelo cliente.
  if (
    v_pm like '%premio%rifa%'
    or v_pm like '%prémio%rifa%'
    or v_pm like '%premio_rifa%'
  ) and lower(trim(coalesce(OLD.payment_method, ''))) is distinct from v_pm then
    -- Só mantém se OLD já era prémio (escrito pela RPC).
    if not (
      lower(trim(coalesce(OLD.payment_method, ''))) like '%premio%rifa%'
      or lower(trim(coalesce(OLD.payment_method, ''))) like '%prémio%rifa%'
      or lower(trim(coalesce(OLD.payment_method, ''))) like '%premio_rifa%'
    ) then
      NEW.payment_method := OLD.payment_method;
    end if;
  end if;

  -- Congelar identidade financeira de encomendas-prémio (ou com rifa ligada).
  if OLD.live_raffle_id is not null or v_old_status = 'premio_rifa' then
    if NEW.product_id is distinct from OLD.product_id then
      NEW.product_id := OLD.product_id;
    end if;
    if NEW.live_item_id is distinct from OLD.live_item_id then
      NEW.live_item_id := OLD.live_item_id;
    end if;
    if NEW.live_id is distinct from OLD.live_id then
      NEW.live_id := OLD.live_id;
    end if;
    if NEW.quantity is distinct from OLD.quantity then
      NEW.quantity := OLD.quantity;
    end if;
    if NEW.price_total is distinct from OLD.price_total then
      NEW.price_total := OLD.price_total;
    end if;
    if NEW.buyer_id is distinct from OLD.buyer_id then
      NEW.buyer_id := OLD.buyer_id;
    end if;
    if NEW.seller_id is distinct from OLD.seller_id then
      NEW.seller_id := OLD.seller_id;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_raffle_prize_authority on public.orders;
create trigger trg_batata_orders_guard_raffle_prize_authority
  before insert or update on public.orders
  for each row
  execute function public.batata_orders_guard_raffle_prize_authority();

comment on function public.batata_orders_guard_raffle_prize_authority() is
  'P0-01: authenticated cannot forge premio_rifa / live_raffle_id / prize payment_method.';

-- ---------------------------------------------------------------------------
-- 3) RPC legítima: set_config + (re)garantir só service_role / DEFINER callers
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
  v_winner_ok boolean := false;
begin
  select * into v_raffle from public.live_raffles where id = p_raffle_id;
  if v_raffle.id is null then
    raise exception 'raffle_not_found';
  end if;

  if v_raffle.live_item_id is null then
    return null; -- prémio manual: sem encomenda de catálogo
  end if;

  -- Exige vencedor registado (não fabricar order «de prémio» sem winner).
  select exists (
    select 1
    from public.live_raffle_winners w
    where w.raffle_id = p_raffle_id
      and w.user_id = p_winner_uid
  ) into v_winner_ok;

  if not v_winner_ok then
    raise exception 'not_raffle_winner';
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

  -- Autoriza o trigger a aceitar status/live_raffle_id/payment_method de prémio.
  perform set_config('batata.raffle_prize_write', '1', true);

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

  begin
    if public.batata_live_item_total_qty(v_li.id) <= greatest(v_raffle.winner_count, 1) then
      perform public.batata_mark_live_item_sold(v_li.id);
    end if;
  exception when others then
    null;
  end;

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

-- draw: mesmo comportamento + set_config para o trigger de autoridade.
-- (corpo alinhado a live_raffle_premio_order_batata.sql)

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

  -- Autoriza inserts de prémio nesta transacção (trigger guard).
  perform set_config('batata.raffle_prize_write', '1', true);

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

revoke all on function public.batata_create_raffle_prize_order(uuid, uuid, int)
  from public, anon, authenticated;
grant execute on function public.batata_create_raffle_prize_order(uuid, uuid, int)
  to service_role;

grant execute on function public.batata_draw_live_raffle_winners(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
