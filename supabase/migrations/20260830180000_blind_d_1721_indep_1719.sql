-- =============================================================================
-- BATATA — Blind D 1721 + Indep 1719 (P1/P2/P3)
-- Staging only. production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: entrega em mão (alinhar com UI _isHandDeliveryOrder)
-- ---------------------------------------------------------------------------
create or replace function public.batata_shipping_method_is_hand(p_method text)
returns boolean
language plpgsql
immutable
as $$
declare
  m text := lower(trim(coalesce(p_method, '')));
begin
  if m = '' then
    return false;
  end if;
  return m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)'
  )
  or m like 'entrega em m%'
  or m like 'hand%'
  or m like 'mao%'
  or m like 'mão%';
end;
$$;

comment on function public.batata_shipping_method_is_hand(text) is
  'D1-EARLY-CONFIRM: mão ≠ transportadora — buyer só salta pago→concluido em mão.';

-- ---------------------------------------------------------------------------
-- D1-EARLY-CONFIRM-PAYOUT — buyer não marca concluido a partir de pago
--   excepto entrega em mão (produto: confirma receção sem «enviado»).
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
  v_captured boolean := false;
  v_platform boolean := false;
  v_pm text;
  v_ship text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'entregue', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_pm := coalesce(OLD.payment_method, NEW.payment_method);
  v_ship := coalesce(OLD.shipping_method, NEW.shipping_method);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  -- ---- Comprador ----
  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- D1-EARLY-CONFIRM: concluido a partir de pago só em mão.
    -- Transportadora exige enviado/entregue (hold de envio + janela disputa).
    if v_new = 'concluido' then
      if v_old = 'pago' then
        if not public.batata_shipping_method_is_hand(v_ship) then
          raise exception 'order_concluido_requires_shipped'
            using errcode = '42501';
        end if;
      elsif v_old not in (
        'enviado', 'entregue', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    -- Seller nunca marca concluido (só buyer / service)
    if v_new = 'concluido' and not v_is_buyer then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_paid_status() is
  'D1-EARLY-CONFIRM: pago→concluido só mão; carrier exige enviado.';

-- ---------------------------------------------------------------------------
-- D1-DISPUTE-UPDATE — seller não fecha disputa (resolvida/recusada)
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_new_st text;
  v_new_turn text;
  v_terminal boolean;
  v_is_buyer boolean;
  v_is_seller boolean;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_new_turn := lower(trim(coalesce(NEW.current_turn, '')));
  v_terminal := v_new_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  );
  v_is_buyer := OLD.buyer_id is not null and OLD.buyer_id = v_uid;
  v_is_seller := exists (
    select 1 from public.orders o
    where o.id = OLD.order_id and o.seller_id = v_uid
  );

  if v_old_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  ) then
    NEW.seller_refund_percent := OLD.seller_refund_percent;
    NEW.seller_offer_type := OLD.seller_offer_type;
    NEW.seller_pays_return_shipping := OLD.seller_pays_return_shipping;
    NEW.seller_offer_set_by := OLD.seller_offer_set_by;
    NEW.seller_offer_set_at := OLD.seller_offer_set_at;
    NEW.buyer_decision := OLD.buyer_decision;
    NEW.admin_resolution := OLD.admin_resolution;
    NEW.admin_resolution_note := OLD.admin_resolution_note;
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  -- Só o comprador fecha a disputa (desbloqueia release).
  if v_terminal and v_new_st is distinct from v_old_st then
    if not v_is_buyer then
      raise exception 'dispute_close_buyer_only' using errcode = '42501';
    end if;
  end if;

  -- Seller pode responder, não terminalizar via buyer_decision cancelled
  if v_is_seller and not v_is_buyer then
    if NEW.buyer_decision is distinct from OLD.buyer_decision then
      NEW.buyer_decision := OLD.buyer_decision;
    end if;
  end if;

  if v_new_turn = 'administracao' and not v_terminal then
    NEW.current_turn := OLD.current_turn;
  end if;

  if v_terminal then
    NEW.current_turn := 'administracao';
  end if;

  if NEW.admin_resolution is distinct from OLD.admin_resolution then
    NEW.admin_resolution := OLD.admin_resolution;
  end if;
  if NEW.admin_resolution_note is distinct from OLD.admin_resolution_note then
    NEW.admin_resolution_note := OLD.admin_resolution_note;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_authority on public.order_disputes;
create trigger trg_batata_order_disputes_guard_authority
  before update on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_authority();

comment on function public.batata_order_disputes_guard_authority() is
  'D1-DISPUTE: terminal resolvida/recusada só buyer JWT.';

-- ---------------------------------------------------------------------------
-- D1-DISPUTE-REOPEN P2 — 1 disputa por order (anti griefing hold)
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_insert_once()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if exists (
    select 1 from public.order_disputes d where d.order_id = NEW.order_id
  ) then
    raise exception 'dispute_already_exists_for_order' using errcode = '23505';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_insert_once on public.order_disputes;
create trigger trg_batata_order_disputes_guard_insert_once
  before insert on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_insert_once();

-- Índice único: só se não houver duplicados legados (trigger cobre o resto)
do $$
begin
  if not exists (
    select 1 from public.order_disputes
    group by order_id having count(*) > 1
  ) then
    execute 'create unique index if not exists order_disputes_order_id_uidx on public.order_disputes (order_id)';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- RT1719-20 / RT1719-11 — amount da proposta imutável após INSERT
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_offers_guard_authority()
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

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) is distinct from 'pending' then
      NEW.status := 'pending';
    end if;
    NEW.responded_at := null;
    if NEW.offered_by = 'buyer' then
      NEW.buyer_id := v_uid;
    elsif NEW.offered_by = 'seller' then
      NEW.seller_id := v_uid;
    end if;
    if coalesce(NEW.amount, 0) <= 0 then
      raise exception 'offer_amount_invalid' using errcode = '23514';
    end if;
    return NEW;
  end if;

  -- RT1719: preço nasce no INSERT; JWT não muta amount (nem pending).
  if NEW.amount is distinct from OLD.amount then
    raise exception 'offer_amount_immutable' using errcode = '42501';
  end if;
  NEW.product_id := OLD.product_id;
  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.offered_by := OLD.offered_by;

  if NEW.status is distinct from OLD.status
     and lower(trim(coalesce(NEW.status, ''))) = 'accepted' then
    if lower(trim(coalesce(OLD.offered_by, ''))) = 'buyer' then
      if v_uid is distinct from OLD.seller_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    elsif lower(trim(coalesce(OLD.offered_by, ''))) = 'seller' then
      if v_uid is distinct from OLD.buyer_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    else
      raise exception 'offer_accept_not_authorized' using errcode = '42501';
    end if;
    NEW.responded_at := coalesce(NEW.responded_at, now());
    NEW.amount := OLD.amount;
  end if;

  if lower(trim(coalesce(OLD.status, ''))) in (
    'accepted', 'rejected', 'superseded', 'expired'
  ) then
    NEW.amount := OLD.amount;
    NEW.status := OLD.status;
    NEW.responded_at := OLD.responded_at;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_offers_guard_authority on public.product_offers;
create trigger trg_batata_product_offers_guard_authority
  before insert or update on public.product_offers
  for each row
  execute function public.batata_product_offers_guard_authority();

comment on function public.batata_product_offers_guard_authority() is
  'RT1719-20: amount imutável após INSERT; accept só contraparte.';

-- ---------------------------------------------------------------------------
-- RT1719-30 P3 — buyer pending: qty ≤ stock do live_item (não 99 fantasma)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean := false;
  v_avail int := 0;
  v_item_qty int := 0;
  v_new_consumes boolean := false;
  v_old_consumes boolean := false;
  v_need_capacity boolean := false;
  v_allowed_status boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  v_allowed_status := NEW.status in (
    'pending', 'accepted', 'rejected', 'expired', 'converted'
  );
  if not v_allowed_status then
    raise exception 'invalid_reservation_status' using errcode = '23514';
  end if;

  v_is_seller :=
    (NEW.seller_id is not null and NEW.seller_id = v_uid)
    or exists (
      select 1 from public.lives l
      where l.id = NEW.live_id
        and (l.seller_id = v_uid or l.vendedor_id = v_uid)
    )
    or public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations');

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
      -- P3: clamp à quantidade do item (fila não inventa 99 unidades)
      v_item_qty := coalesce(public.batata_live_item_total_qty(NEW.live_item_id), 0);
      if v_item_qty < 1 then
        v_item_qty := 1;
      end if;
      if NEW.requested_qty > v_item_qty then
        NEW.requested_qty := v_item_qty;
      end if;
      if NEW.requested_qty > 20 then
        NEW.requested_qty := 20;
      end if;
      return NEW;
    end if;

    if NEW.requested_qty > 99 then
      raise exception 'invalid_requested_qty' using errcode = '23514';
    end if;

    if v_new_consumes then
      perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
      v_avail := public.batata_live_reservation_accept_available(
        NEW.live_item_id,
        null
      );
      if NEW.requested_qty > v_avail then
        raise exception 'qty_exceeds_stock' using errcode = '23514';
      end if;
    end if;
    return NEW;
  end if;

  v_old_consumes := public.batata_live_reservation_status_consumes_capacity(OLD.status);

  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from public.batata_live_reservation_status_canonical(OLD.status) then
      NEW.status := public.batata_live_reservation_status_canonical(OLD.status);
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
    return NEW;
  end if;

  if v_new_consumes and not v_old_consumes then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  v_need_capacity :=
    v_new_consumes
    and (
      (not v_old_consumes)
      or (NEW.requested_qty > coalesce(OLD.requested_qty, 0))
    );

  if v_need_capacity then
    if NEW.live_item_id is null then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
    v_avail := public.batata_live_reservation_accept_available(
      NEW.live_item_id,
      NEW.id
    );
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_reservation_guard_authority
  on public.live_reservation_requests;
create trigger trg_batata_live_reservation_guard_authority
  before insert or update on public.live_reservation_requests
  for each row
  execute function public.batata_live_reservation_guard_authority();

comment on function public.batata_live_reservation_guard_authority() is
  'RT1719-30: buyer pending qty clamped ao stock do item (≤20).';

notify pgrst, 'reload schema';
