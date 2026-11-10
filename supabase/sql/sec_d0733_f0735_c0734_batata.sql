-- =============================================================================
-- BATATA — D 0733 + F 0735 + C 0734 (P1/P2)
-- P1: seller refund após concluido / com disputa aberta
-- P2 D: chat JSON sem order_id; completed_at backdate
-- P2 F: offer TTL accept; ghost cancelado→unlist SELECT; directory hub_published
-- P2 C: tip só em live activa (pending + wallet)
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P1 helper: refund seller permitido?
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_allows_seller_stripe_refund(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_st text;
  v_open_dispute boolean;
begin
  if p_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_order');
  end if;

  select lower(trim(coalesce(o.status, ''))) into v_st
  from public.orders o
  where o.id = p_order_id;

  if v_st is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  -- Já reembolsado / cancelado: Edge trata idempotência à parte
  if v_st in ('cancelado', 'cancelled', 'canceled', 'devolvida') then
    return jsonb_build_object('ok', true, 'status', v_st, 'terminal', true);
  end if;

  -- Alinhado à UI (orderAllowsBuyerCancelStatus): após envio / receção não anula
  if v_st in (
    'enviado',
    'concluido',
    'concluído',
    'entregue',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_status',
      'status', v_st
    );
  end if;

  select exists (
    select 1
    from public.order_disputes d
    where d.order_id = p_order_id
      and lower(trim(coalesce(d.status, ''))) in (
        'aberta', 'open', 'pending', 'em_analise', 'em_análise'
      )
  ) into v_open_dispute;

  if coalesce(v_open_dispute, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_open_dispute',
      'status', v_st
    );
  end if;

  return jsonb_build_object('ok', true, 'status', v_st);
end;
$$;

revoke all on function public.batata_order_allows_seller_stripe_refund(uuid)
  from public, anon, authenticated;
grant execute on function public.batata_order_allows_seller_stripe_refund(uuid)
  to service_role;

comment on function public.batata_order_allows_seller_stripe_refund(uuid) is
  'D0733-P1: Edge refund-order — bloqueia pós-envio/concluido e disputa aberta.';

-- ---------------------------------------------------------------------------
-- P2 D: completed_at sempre now() na transição para concluido (JWT)
-- ---------------------------------------------------------------------------
create or replace function public.batata_set_order_completed_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $batata_completed$
begin
  if new.status = 'concluido'
     and (old.status is distinct from new.status) then
    -- D0733-P2: ignorar backdate JWT (2020-01-01)
    new.completed_at := now();
  end if;

  if old.status = 'concluido' and new.status is distinct from 'concluido' then
    new.completed_at := null;
    new.auto_feedback_processed_at := null;
  end if;

  -- JWT não altera completed_at fora da transição
  if tg_op = 'UPDATE'
     and auth.uid() is not null
     and coalesce(auth.role(), '') = 'authenticated'
     and new.completed_at is distinct from old.completed_at
     and not (
       new.status = 'concluido'
       and old.status is distinct from 'concluido'
     ) then
    new.completed_at := old.completed_at;
  end if;

  return new;
end;
$batata_completed$;

drop trigger if exists batata_set_order_completed_at_trg on public.orders;
create trigger batata_set_order_completed_at_trg
before update on public.orders
for each row
execute function public.batata_set_order_completed_at();

-- ---------------------------------------------------------------------------
-- P2 D: FLEABER_JSON kinds que exigem order_id
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_messages_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_raw text;
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := v_uid;

  v_raw := coalesce(NEW.text, '');
  if v_raw not like 'FLEABER_JSON_V1:%' then
    return NEW;
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
    'premio_rifa'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c
  where c.id = NEW.chat_id;

  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;

  if v_uid is distinct from v_chat_a and v_uid is distinct from v_chat_b then
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

  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;

  if v_needs_order and v_oid is null then
    raise exception 'chat_system_card_order_id_required' using errcode = '23514';
  end if;

  if v_oid is not null then
    select o.seller_id, o.buyer_id
      into v_order_seller, v_order_buyer
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
      if v_uid is distinct from v_order_seller then
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
      if v_uid is distinct from v_order_buyer then
        raise exception 'chat_system_card_buyer_only' using errcode = '42501';
      end if;
    end if;

    if v_kind in ('order_dispute_opened') then
      if v_uid is distinct from v_order_buyer and v_uid is distinct from v_order_seller then
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

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chat_messages_guard_insert on public.chat_messages;
create trigger trg_batata_chat_messages_guard_insert
  before insert on public.chat_messages
  for each row
  execute function public.batata_chat_messages_guard_insert();

-- ---------------------------------------------------------------------------
-- P2 F: offer — não aceitar expirada
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_offers_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_new_st text;
  v_old_st text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' then
    v_new_st := lower(trim(coalesce(NEW.status, '')));
    v_old_st := lower(trim(coalesce(OLD.status, '')));

    if v_new_st = 'accepted' and v_old_st is distinct from 'accepted' then
      if OLD.expires_at is not null and OLD.expires_at <= now() then
        raise exception 'offer_expired' using errcode = '23514';
      end if;
      if NEW.expires_at is not null and NEW.expires_at <= now() then
        raise exception 'offer_expired' using errcode = '23514';
      end if;
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_offers_guard_write on public.product_offers;
create trigger trg_batata_product_offers_guard_write
  before update on public.product_offers
  for each row
  execute function public.batata_product_offers_guard_write();

comment on function public.batata_product_offers_guard_write() is
  'F0735-P2: seller não aceita product_offers com expires_at no passado.';

-- ---------------------------------------------------------------------------
-- P2 F: products RLS — ghost cancelado não revela unlist
-- ---------------------------------------------------------------------------
drop policy if exists "products_select_marketplace_or_own" on public.products;
create policy "products_select_marketplace_or_own"
  on public.products
  for select
  to authenticated
  using (
    (list_on_marketplace = true and coalesce(is_sold, false) = false)
    or seller_id = auth.uid()
    or exists (
      select 1
      from public.orders o
      where o.product_id = products.id
        and o.buyer_id = auth.uid()
        and lower(trim(coalesce(o.status, ''))) not in (
          'cancelado', 'cancelled', 'canceled',
          'expirado', 'expired'
        )
    )
  );

comment on policy "products_select_marketplace_or_own" on public.products is
  'F0735-P2: listed OU own OU order activa (não cancelado/expirado).';

-- ---------------------------------------------------------------------------
-- P2 F: directory só hub_published (+ self)
-- ---------------------------------------------------------------------------
create or replace view public.profiles_directory_public
with (security_barrier = true)
as
select
  p.id,
  p.created_at,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  p.user_type,
  p.handle,
  coalesce(p.vacation_mode, false) as vacation_mode,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  (p.phone_verified_at is not null) as phone_verified
from public.profiles p
where coalesce(p.hub_published, false) = true
   or p.id = auth.uid();

comment on view public.profiles_directory_public is
  'F0735-P2: directory autenticada = hub_published OU self. Sem PII sensível.';

grant select on public.profiles_directory_public to authenticated;
revoke all on public.profiles_directory_public from anon;

-- ---------------------------------------------------------------------------
-- P2 C: tip pending só live activa
-- ---------------------------------------------------------------------------
create or replace function public.batata_create_live_tip_pending(
  p_live_id uuid,
  p_seller_id uuid,
  p_amount numeric,
  p_message text default null,
  p_stripe_session_id text default null
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
  v_live_seller uuid;
  v_live_active boolean;
  v_note text;
  v_amount numeric;
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

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;
  if v_amount > 500 then
    raise exception 'Valor máximo de gorjeta: 500 €.';
  end if;

  select
    coalesce(seller_id, vendedor_id),
    (
      coalesce(is_active, false) = true
      or lower(trim(coalesce(status, ''))) in ('live', 'ao_vivo', 'active')
    )
  into v_live_seller, v_live_active
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto não encontrado.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este direto.';
  end if;

  if not coalesce(v_live_active, false) then
    raise exception 'live_not_active_for_tip' using errcode = '23514';
  end if;

  v_fee := public.batata_live_tip_processing_fee(v_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(v_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

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
    stripe_session_id
  ) values (
    p_live_id,
    v_buyer_id,
    p_seller_id,
    v_amount,
    v_fee,
    v_seller_amount,
    v_note,
    'stripe',
    'pending',
    null
  )
  returning id into v_tip_id;

  return v_tip_id;
end;
$$;

revoke all on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_create_live_tip_pending(uuid, uuid, numeric, text, text)
  to authenticated, service_role;

-- Wallet tip: mesma regra live activa
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
  v_live_active boolean;
  v_note text;
begin
  if v_buyer_id is null then
    raise exception 'Tem de iniciar sessão para enviar gorjeta.';
  end if;

  if p_seller_id is null or p_seller_id = v_buyer_id then
    raise exception 'Vendedor inválido para gorjeta.';
  end if;

  if coalesce(p_amount, 0) < 1 then
    raise exception 'Valor mínimo de gorjeta: 1 €.';
  end if;

  if p_live_id is null then
    raise exception 'Direto obrigatório para gorjeta.';
  end if;

  select
    coalesce(seller_id, vendedor_id),
    (
      coalesce(is_active, false) = true
      or lower(trim(coalesce(status, ''))) in ('live', 'ao_vivo', 'active')
    )
  into v_live_seller, v_live_active
  from public.lives
  where id = p_live_id;

  if v_live_seller is null then
    raise exception 'Direto não encontrado.';
  end if;

  if v_live_seller <> p_seller_id then
    raise exception 'O vendedor não corresponde a este directo.';
  end if;

  if not coalesce(v_live_active, false) then
    raise exception 'live_not_active_for_tip' using errcode = '23514';
  end if;

  v_fee := public.batata_live_tip_processing_fee(p_amount);
  v_seller_amount := public.batata_live_tip_seller_amount(p_amount);
  v_note := nullif(trim(coalesce(p_message, '')), '');

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
    coalesce(v_note, 'Gorjeta em direto')
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

notify pgrst, 'reload schema';
