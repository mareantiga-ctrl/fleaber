-- =============================================================================
-- BATATA — Blind P2/P3 fecho (1245 / 1250 / Indep CEGA)
-- Staging only. Sem remover features. Sem produção / Fase 4.
-- P0/P1 já fechados em sec_blind_b_1245_1250_batata.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RTB-B-1245-P2 — price_total JWT alinhado ao contrato no INSERT
-- (checkout já cobrava contrato; display deixava de mentir 999€)
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
  v_role text := coalesce(auth.role(), '');
begin
  if NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    if v_role = 'authenticated' then
      NEW.price_total := round(
        (NEW.contract_unit_cents::numeric * NEW.contract_qty::numeric) / 100.0,
        2
      );
    end if;
    return NEW;
  end if;

  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  if NEW.live_item_id is not null then
    select li.price into v_li
    from public.live_items li
    where li.id = NEW.live_item_id;
    if v_li is not null and v_li > 0 then
      v_unit_cents := greatest(1, round(v_li * 100)::int);
    end if;
  end if;

  if v_unit_cents <= 0 and NEW.product_id is not null then
    select p.price into v_prod
    from public.products p
    where p.id = NEW.product_id;
    if v_prod is not null and v_prod > 0 then
      v_unit_cents := greatest(1, round(v_prod * 100)::int);
    end if;
  end if;

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

  -- JWT: price_total de display = contrato (não 999€ inventados)
  if v_role = 'authenticated' then
    NEW.price_total := round(
      (NEW.contract_unit_cents::numeric * NEW.contract_qty::numeric) / 100.0,
      2
    );
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_seal_contract on public.orders;
create trigger trg_batata_orders_seal_contract
  before insert on public.orders
  for each row
  execute function public.batata_orders_seal_contract();

-- ---------------------------------------------------------------------------
-- RTB3-P2-04 — gorjeta wallet: nest ensure_wallet do seller + live obrigatório
-- (não enfraquece ensure_wallet directo da app)
-- ---------------------------------------------------------------------------
create or replace function public.batata_send_live_tip_from_wallet(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer_id uuid := auth.uid();
  v_tip_id uuid;
  v_fee numeric;
  v_seller_amount numeric;
  v_balance numeric;
  v_live_seller uuid;
  v_note text;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if p_live_id is null then
    raise exception 'Direto obrigatório para gorjeta.';
  end if;

  if coalesce(p_amount, 0) < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;
  if round(coalesce(p_amount, 0), 2) > 500 then
    raise exception 'Valor máximo de gorjeta: 500 €.';
  end if;

  if not exists (select 1 from public.lives where id = p_live_id) then
    raise exception 'Direto não encontrado.';
  end if;

  select coalesce(seller_id, vendedor_id) into v_live_seller
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto sem vendedor.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este direto.';
  end if;

  v_fee := public.batata_live_tip_processing_fee(p_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(p_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

  -- Nest interno: criar carteira do seller sem JWT ser o seller
  perform set_config('batata.wallet_internal', '1', true);
  perform public.batata_ensure_wallet(v_buyer_id);
  perform public.batata_ensure_wallet(p_seller_id);

  select balance into v_balance
  from public.wallets
  where id = v_buyer_id
  for update;

  if coalesce(v_balance, 0) < round(p_amount, 2) then
    raise exception 'insufficient_wallet_balance';
  end if;

  insert into public.live_tips (
    live_id,
    buyer_id,
    seller_id,
    amount,
    processing_fee,
    seller_amount,
    message,
    payment_source,
    status,
    completed_at
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    round(p_amount, 2),
    v_fee,
    v_seller_amount,
    v_note,
    'wallet',
    'completed',
    now()
  )
  returning id into v_tip_id;

  if not public.batata_wallet_apply_tip_once(
    v_buyer_id,
    v_tip_id,
    -round(p_amount, 2),
    'gorjeta_enviada',
    coalesce(v_note, 'Gorjeta em direto')
  ) then
    raise exception 'Não foi possível debitar a carteira.';
  end if;

  if not public.batata_wallet_apply_tip_once(
    p_seller_id,
    v_tip_id,
    v_seller_amount,
    'gorjeta_recebida',
    coalesce(v_note, 'Gorjeta recebida em direto')
  ) then
    raise exception 'Não foi possível creditar o vendedor.';
  end if;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- CEGA-P3-02 — email→UUID: rate 2/h (convites staff mantêm-se)
-- ---------------------------------------------------------------------------
create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_found uuid;
  v_is_seller boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or char_length(v_email) > 320 then
    return null;
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and lower(trim(coalesce(p.user_type, ''))) in ('vendedor', 'seller')
  ) into v_is_seller;

  if not v_is_seller then
    return null;
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_find_user_id_by_email', v_window, 1)
  on conflict (uid, rpc, window_start)
  do update set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 2 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select u.id
  into v_found
  from auth.users u
  where lower(trim(u.email)) = v_email
  limit 1;

  return v_found;
end;
$$;

comment on function public.batata_find_user_id_by_email(text) is
  'P3: email→UUID só vendedor; rate 2/h (convites staff).';

revoke all on function public.batata_find_user_id_by_email(text) from public, anon;
grant execute on function public.batata_find_user_id_by_email(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- CEGA-P3-03 — EXECUTE JWT em release/refund é intencional (fail-closed).
-- Documentado; guards económicos já selados (P0 1245). Sem revoke (parte
-- do fluxo concluido do comprador).
-- ---------------------------------------------------------------------------
comment on function public.batata_release_seller_wallet_for_order(uuid) is
  'CEGA-P3-03 CLOSED_BY_DESIGN: JWT OK; efeito económico só em concluido + fundos reais; refund Stripe bloqueia.';

comment on function public.batata_refund_buyer_wallet_for_order(uuid) is
  'CEGA-P3-03 CLOSED_BY_DESIGN: JWT OK; fail-closed fora de devolvida / sem crédito indevido.';

-- ---------------------------------------------------------------------------
-- CEGA-P3-05 — review off-platform: fora da reputação pública (já).
-- Confirma vista; não remove o direito de deixar opinião privada.
-- ---------------------------------------------------------------------------
comment on view public.reviews_public_ratings is
  'CEGA-P3-05 CLOSED: média pública só purchase_verified=true; off-platform não inflaciona.';

-- ---------------------------------------------------------------------------
-- RTB3-P2-02 — draw_seed fora do JSON do RPC (fica na coluna + audit DEFINER)
-- Função completa: ver bloco aplicado aplicado (ficheiro companion ou migration).
-- ---------------------------------------------------------------------------


-- RTB3-P2-02 draw winners (sem draw_seed no return JWT)
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
    'winners', v_winners,
    'winner_name', v_winner_name,
    'prize_orders', v_prize_orders
  );
end;
$$;


revoke all on function public.batata_draw_live_raffle_winners(uuid) from public, anon;
grant execute on function public.batata_draw_live_raffle_winners(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
