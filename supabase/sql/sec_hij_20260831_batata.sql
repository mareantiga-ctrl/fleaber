-- =============================================================================
-- BATATA — H/I/J fecho 20260831 (escolhas todas A)
-- P0/P1 I: plataforma sem Stripe refund → sem mint wallet; debit fail-closed
-- P1 J: UPDATE plain→JSON = mesmas regras INSERT
-- 1-A: cards «pago» só com order realmente paga
-- 2-A: chat_uploads/{uid}/{chat_id}/… (counterparty só desse chat)
-- 6-A residual: reviews_gerais security_invoker
-- 3-A: sem remint saldo seller staging
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P0 — debit: sem estorno fantasma se saldo insuficiente
-- ---------------------------------------------------------------------------
create or replace function public.batata_debit_wallet_once(
  p_wallet_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_description text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row_count integer := 0;
  v_bal numeric;
  v_desc text := coalesce(nullif(trim(p_description), ''), 'Estorno encomenda');
  v_amt numeric := round(coalesce(p_amount, 0), 2);
begin
  if p_wallet_id is null or p_order_id is null or v_amt <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  select balance into v_bal from public.wallets where id = p_wallet_id for update;
  if coalesce(v_bal, 0) < v_amt then
    -- Fail-closed: não escrever estorno sem dinheiro real a debitar
    return false;
  end if;

  insert into public.wallet_transactions (
    wallet_id, amount, type, description, order_id
  ) values (
    p_wallet_id, v_amt, 'estorno', v_desc, p_order_id
  )
  on conflict (wallet_id, order_id, type, (coalesce(description, '')))
    where order_id is not null
  do nothing;

  get diagnostics v_row_count = row_count;
  if v_row_count = 0 then
    return false;
  end if;

  update public.wallets
  set balance = round(coalesce(v_bal, 0) - v_amt, 2),
      updated_at = now()
  where id = p_wallet_id;

  return true;
end;
$$;

revoke all on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.batata_debit_wallet_once(uuid, uuid, numeric, text)
  to service_role;

comment on function public.batata_debit_wallet_once(uuid, uuid, numeric, text) is
  'I-P0: debit só se saldo >= amount; sem estorno fantasma (clamp a zero).';

-- ---------------------------------------------------------------------------
-- P0 — refund buyer: captura plataforma exige Stripe refund (sem mint wallet)
-- ---------------------------------------------------------------------------
create or replace function public.batata_refund_buyer_wallet_for_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
  v_base numeric;
  v_remaining numeric;
  v_label_fee numeric := 0;
  v_done boolean;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute record;
  v_cleared int;
  v_platform boolean := false;
  v_captured boolean := false;
  v_clawed numeric := 0;
  v_need_claw numeric := 0;
  v_credited numeric := 0;
  v_estornado numeric := 0;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform set_config('batata.allow_internal_order_cols', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null then return false; end if;
    if v_uid is distinct from v_order.buyer_id
       and v_uid is distinct from v_order.seller_id
       and not public.batata_is_admin() then
      return false;
    end if;
  end if;

  if lower(coalesce(v_order.status, '')) <> 'devolvida' then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_platform := public.batata_is_platform_payment(v_order.payment_method);
  v_captured :=
    coalesce(v_order.amount_paid_cents, 0) > 0
    or coalesce(nullif(trim(v_order.stripe_payment_intent_id), ''), '') <> '';

  -- Captura Stripe oficial já refundida: clawback + marca, sem mint wallet
  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  -- I-P0: pagamento plataforma capturado SEM refund Stripe → NÃO mintar carteira comprador.
  -- Clawback tenta recuperar; se falhar (já levantou), fica sem processar (Edge/admin Stripe).
  if v_platform and v_captured then
    select coalesce(sum(amount), 0) into v_credited
    from public.wallet_transactions
    where order_id = v_order.id
      and wallet_id = v_order.seller_id
      and type = 'venda';
    select coalesce(sum(amount), 0) into v_estornado
    from public.wallet_transactions
    where order_id = v_order.id
      and wallet_id = v_order.seller_id
      and type = 'estorno';
    v_need_claw := greatest(v_credited - v_estornado, 0);

    v_clawed := public.batata_clawback_seller_wallet_for_order(v_order.id);

    if v_need_claw > 0 and coalesce(v_clawed, 0) < v_need_claw then
      -- Seller já tirou o dinheiro: não criar passivo na carteira do buyer
      return false;
    end if;

    -- Sem mint; marca processado só se não havia credit seller a recuperar
    -- OU clawback completo. Buyer recupera via Stripe refund-order (não wallet).
    if v_need_claw = 0 or coalesce(v_clawed, 0) >= v_need_claw then
      update public.orders
      set wallet_refund_processed_at = now(),
          returned_at = coalesce(returned_at, now()),
          wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
      where id = v_order.id and wallet_refund_processed_at is null;
      get diagnostics v_cleared = row_count;
      return v_cleared > 0;
    end if;
    return false;
  end if;

  v_base := public.batata_order_wallet_base_eur(v_order);
  if v_base <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id and wallet_refund_processed_at is null;
    get diagnostics v_cleared = row_count;
    return v_cleared > 0;
  end if;

  -- Off-platform / sem captura: clawback + credit buyer (fluxo mão / MB WAY wallet)
  v_clawed := public.batata_clawback_seller_wallet_for_order(v_order.id);

  select coalesce(sum(amount), 0) into v_credited
  from public.wallet_transactions
  where order_id = v_order.id
    and wallet_id = v_order.seller_id
    and type = 'venda';
  select coalesce(sum(amount), 0) into v_estornado
  from public.wallet_transactions
  where order_id = v_order.id
    and wallet_id = v_order.seller_id
    and type = 'estorno';
  v_need_claw := greatest(v_credited - v_estornado, 0);
  if v_need_claw > 0 then
    -- Ainda falta clawback: não mintar buyer
    return false;
  end if;

  delete from public.fleaber_commissions
  where order_id = v_order.id and source = 'protection_fee';

  select * into v_order from public.orders where id = p_order_id;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  v_amount := least(v_base, v_remaining);

  select od.seller_pays_return_shipping, od.return_label_created_at, od.buyer_decision
    into v_dispute
  from public.order_disputes od
  where od.order_id = v_order.id
  order by od.created_at desc limit 1;

  if found
     and coalesce(v_dispute.seller_pays_return_shipping, false) = false
     and v_dispute.return_label_created_at is not null
     and coalesce(v_dispute.buyer_decision, '') = 'accepted_return'
  then
    v_label_fee := 3.50;
  end if;

  if v_label_fee > 0 then
    v_amount := greatest(v_amount - v_label_fee, 0);
  end if;

  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  v_amount := least(v_amount, v_remaining);

  if v_amount <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.buyer_id, v_order.id, v_amount, 'reembolso',
    case when v_label_fee > 0 then
      'Reembolso Encomenda #' || left(v_order.id::text, 8)
        || ' (abatida etiqueta ' || to_char(v_label_fee, 'FM999990.00') || ' €)'
    else
      'Reembolso Encomenda #' || left(v_order.id::text, 8)
    end
  );

  if v_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now()),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;
  return v_done;
end;
$$;

revoke all on function public.batata_refund_buyer_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_refund_buyer_wallet_for_order(uuid)
  to authenticated, service_role;

comment on function public.batata_refund_buyer_wallet_for_order(uuid) is
  'I-P0: plataforma capturada sem stripe_refund_id → sem mint wallet; clawback fail-closed.';

-- ---------------------------------------------------------------------------
-- J + 1-A — validação JSON partilhada INSERT/UPDATE
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_assert_json_card(
  p_chat_id uuid,
  p_sender_id uuid,
  p_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text := coalesce(p_text, '');
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_order_status text;
  v_paid_cents int;
  v_pi text;
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
  v_needs_paid boolean;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
    return;
  end if;

  begin
    v_json := substring(v_raw from length('FLEABER_JSON_V1:') + 1)::jsonb;
  exception when others then
    raise exception 'chat_system_card_invalid_json' using errcode = '23514';
  end;

  v_kind := lower(trim(coalesce(v_json->>'kind', '')));
  if v_kind = '' then
    raise exception 'chat_system_card_kind_required' using errcode = '23514';
  end if;

  if v_kind in (
    'marketplace_bag_paid',
    'auto_feedback_generated',
    'raffle_prize',
    'premio_rifa',
    'order_paid'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c
  where c.id = p_chat_id;

  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;

  if p_sender_id is distinct from v_chat_a and p_sender_id is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  v_needs_order := v_kind in (
    'reservation_seller_confirmed_receipt',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_shipped',
    'reservation_accepted',
    'reservation_request_outcome',
    'price_offer_outcome',
    'cancel_request_outcome',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'bundle_buyer_confirmed_receipt',
    'reservation_payment_submitted',
    'reservation_request',
    'reservation_order_completed',
    'cancel_request',
    'order_review_submitted',
    'seguro_fleaber_paid',
    'price_offer',
    'order_dispute_opened'
  );

  -- 1-A: kinds que afirmam pagamento / pós-pago
  v_needs_paid := v_kind in (
    'seguro_fleaber_paid',
    'reservation_order_shipped',
    'reservation_order_completed',
    'reservation_seller_confirmed_receipt',
    'bundle_buyer_confirmed_receipt'
  );

  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;

  if v_needs_order and v_oid is null then
    raise exception 'chat_system_card_order_id_required' using errcode = '23514';
  end if;

  if v_oid is not null then
    select o.seller_id, o.buyer_id, o.status,
           coalesce(o.amount_paid_cents, 0),
           coalesce(o.stripe_payment_intent_id, '')
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi
    from public.orders o
    where o.id = v_oid;

    if not found then
      raise exception 'chat_system_card_order_missing' using errcode = '23514';
    end if;

    if not (
      (v_order_seller is not distinct from v_chat_a and v_order_buyer is not distinct from v_chat_b)
      or (v_order_seller is not distinct from v_chat_b and v_order_buyer is not distinct from v_chat_a)
    ) then
      raise exception 'chat_system_card_order_chat_mismatch' using errcode = '23514';
    end if;

    if v_needs_paid then
      if not (
        v_paid_cents > 0
        or nullif(trim(v_pi), '') is not null
        or lower(trim(coalesce(v_order_status, ''))) in (
          'pago', 'enviado', 'entregue', 'concluido',
          'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
          'disputa_devolucao_vendedor', 'devolvida'
        )
      ) then
        raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
      end if;
    end if;

    if v_kind in (
      'reservation_seller_confirmed_receipt',
      'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller',
      'reservation_order_shipped',
      'reservation_accepted',
      'reservation_request_outcome',
      'price_offer_outcome',
      'cancel_request_outcome',
      'bundle_direct_payment_details',
      'order_direct_payment_details'
    ) then
      if p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_seller_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in (
      'bundle_buyer_confirmed_receipt',
      'reservation_payment_submitted',
      'reservation_request',
      'reservation_order_completed',
      'cancel_request',
      'order_review_submitted',
      'seguro_fleaber_paid',
      'price_offer'
    ) then
      if p_sender_id is distinct from v_order_buyer then
        raise exception 'chat_system_card_buyer_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in ('order_dispute_opened') then
      if p_sender_id is distinct from v_order_buyer
         and p_sender_id is distinct from v_order_seller then
        raise exception 'chat_system_card_party_only' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_kind not in (
    'chat_image',
    'bundle_proposal',
    'bundle_direct_payment_details',
    'order_direct_payment_details',
    'price_offer',
    'price_offer_outcome',
    'reservation_accepted',
    'reservation_request',
    'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt',
    'cancel_request',
    'cancel_request_outcome',
    'order_dispute_opened',
    'order_review_submitted',
    'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed',
    'reservation_order_shipped',
    'reservation_payment_submitted',
    'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;
end;
$fn$;

revoke all on function public.batata_chat_messages_assert_json_card(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.batata_chat_messages_assert_json_card(uuid, uuid, text)
  to service_role;

create or replace function public.batata_chat_messages_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := v_uid;
  perform public.batata_chat_messages_assert_json_card(
    NEW.chat_id, NEW.sender_id, NEW.text
  );
  return NEW;
end;
$fn$;

create or replace function public.batata_chat_messages_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := OLD.sender_id;
  NEW.chat_id := OLD.chat_id;

  if OLD.sender_id is distinct from v_uid then
    NEW.text := OLD.text;
    return NEW;
  end if;

  -- JSON já gravado: imutável
  if coalesce(OLD.text, '') like 'FLEABER_JSON_V1:%'
     and NEW.text is distinct from OLD.text then
    raise exception 'chat_system_card_immutable' using errcode = '42501';
  end if;

  -- P1 J: plain → JSON = mesmas regras do INSERT
  if coalesce(OLD.text, '') not like 'FLEABER_JSON_V1:%'
     and coalesce(NEW.text, '') like 'FLEABER_JSON_V1:%' then
    perform public.batata_chat_messages_assert_json_card(
      NEW.chat_id, NEW.sender_id, NEW.text
    );
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_insert on public.chat_messages;
create trigger trg_batata_chat_messages_guard_insert
  before insert on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_insert();

drop trigger if exists trg_batata_chat_messages_guard_update on public.chat_messages;
create trigger trg_batata_chat_messages_guard_update
  before update on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_update();

comment on function public.batata_chat_messages_guard_update() is
  'J-P1: plain→JSON valida como INSERT; JSON existente imutável; 1-A pago exigido.';

-- ---------------------------------------------------------------------------
-- 2-A — storage: counterparty só chat_uploads/{uid}/{chat_id}/%
-- ---------------------------------------------------------------------------
drop policy if exists fleaber_private_select_chat_counterparty on storage.objects;
create policy fleaber_private_select_chat_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and name like 'chat_uploads/%/%/%'
    and exists (
      select 1
      from public.chats c
      where c.id::text = split_part(name, '/', 3)
        and (
          (
            c.user_a = auth.uid()
            and name like (
              'chat_uploads/' || c.user_b::text || '/' || c.id::text || '/%'
            )
          )
          or (
            c.user_b = auth.uid()
            and name like (
              'chat_uploads/' || c.user_a::text || '/' || c.id::text || '/%'
            )
          )
        )
    )
  );

comment on policy fleaber_private_select_chat_counterparty on storage.objects is
  'J2-A: counterpart lê só chat_uploads/{outro}/{chat_id}/… deste chat.';

-- ---------------------------------------------------------------------------
-- reviews_gerais — security_invoker (herda RLS de reviews)
-- ---------------------------------------------------------------------------
create or replace view public.reviews_gerais
with (security_invoker = true)
as
select
  id,
  created_at,
  target_id,
  buyer_id,
  stars,
  comment,
  is_automatic,
  target_type
from public.reviews;

grant select on public.reviews_gerais to authenticated;
revoke all on public.reviews_gerais from anon;

notify pgrst, 'reload schema';
