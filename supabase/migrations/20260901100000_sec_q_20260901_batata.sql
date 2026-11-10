-- Q fechos 2026-09-01 — pós-auditoria cega Q (RTQ findings)
-- Q1 P0: live_item_id tem de pertencer a live_id
-- Q5 P1: vendedor não fecha disputa resolvida sozinho
-- Q6 P1: não inflacionar stock com encomenda activa
-- Q8 P0: parcial pós-envio plataforma → Stripe (não mint carteira)
-- Q3 P2: fragmento #https:// em proof/label URLs
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- Q1 — live_item ∈ live (variante pós N-P0 seller_id)
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
  v_live_id uuid;
  v_item_live_id uuid;
  v_live_owner uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  if NEW.live_item_id is not null then
    select li.live_id
      into v_item_live_id
    from public.live_items li
    where li.id = NEW.live_item_id
    limit 1;
    if v_item_live_id is null then
      raise exception 'live_item_not_found' using errcode = '23503';
    end if;
    if NEW.live_id is not null and NEW.live_id is distinct from v_item_live_id then
      raise exception 'live_item_live_mismatch' using errcode = '42501';
    end if;
    NEW.live_id := coalesce(NEW.live_id, v_item_live_id);
  end if;

  v_live_id := NEW.live_id;

  select coalesce(l.seller_id, l.vendedor_id)
    into v_live_owner
  from public.lives l
  where l.id = v_live_id
  limit 1;

  if v_live_owner is not null then
    NEW.seller_id := v_live_owner;
  end if;

  if v_live_id is not null
     and public.batata_live_reservation_status_consumes_capacity(NEW.status)
     and (
       TG_OP = 'INSERT'
       or not public.batata_live_reservation_status_consumes_capacity(
         public.batata_live_reservation_status_canonical(OLD.status)
       )
     ) then
    if public.batata_live_is_draft(v_live_id) and not public.batata_is_admin() then
      raise exception 'live_not_public' using errcode = '42501';
    end if;
    if not public.batata_live_is_broadcasting(v_live_id)
       and not (public.batata_live_is_draft(v_live_id) and public.batata_is_admin()) then
      raise exception 'live_ended' using errcode = '42501';
    end if;
  end if;

  v_is_seller :=
    (v_live_owner is not null and v_live_owner = v_uid)
    or (
      v_live_owner is not null
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations')
    );

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
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
    NEW.seller_id := OLD.seller_id;
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

  NEW.seller_id := coalesce(v_live_owner, OLD.seller_id);
  return NEW;
end;
$fn$;

comment on function public.batata_live_reservation_guard_authority() is
  'N-P0+Q1: seller_id=dono live; live_item_id tem de pertencer ao live_id.';

-- ---------------------------------------------------------------------------
-- Q5 — vendedor não salta para resolvida sem decisão comprador / admin
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
  v_order_seller uuid;
  v_buyer_decision text;
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
  v_buyer_decision := lower(trim(coalesce(NEW.buyer_decision, '')));
  v_terminal := v_new_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
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

  if v_new_st = 'escalada_fleaber' then
    NEW.current_turn := 'administracao';
  elsif v_new_turn = 'administracao' and not v_terminal then
    NEW.current_turn := OLD.current_turn;
  end if;

  if v_terminal then
    NEW.current_turn := 'administracao';
  end if;

  -- Q5: seller não fecha resolvida sem buyer_decision nem admin
  if v_new_st = 'resolvida'
     and v_old_st is distinct from 'resolvida'
     and not public.batata_is_admin() then
    select o.seller_id into v_order_seller
    from public.orders o
    where o.id = NEW.order_id
    limit 1;
    if v_order_seller = v_uid
       and v_buyer_decision not in (
         'accepted_partial_refund',
         'accepted_return',
         'rejected_partial_refund',
         'rejected_return'
       ) then
      NEW.status := OLD.status;
      NEW.current_turn := OLD.current_turn;
      return NEW;
    end if;
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

comment on function public.batata_order_disputes_guard_authority() is
  'O-P3+Q5: escalate→admin; seller não PATCH resolvida sem decisão comprador.';

-- ---------------------------------------------------------------------------
-- Q6 — não inflacionar products.quantity com encomenda activa a segurar stock
-- ---------------------------------------------------------------------------
create or replace function public.batata_products_guard_quantity_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_held int := 0;
  v_floor int := 0;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.quantity is not distinct from OLD.quantity then
    return NEW;
  end if;
  if NEW.seller_id is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations') then
    NEW.quantity := OLD.quantity;
    return NEW;
  end if;

  select coalesce(sum(coalesce(o.stock_units_applied, o.quantity, 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = NEW.id
    and coalesce(o.stock_units_applied, 0) > 0
    and lower(trim(coalesce(o.status, ''))) not in (
      'cancelado', 'cancelada', 'cancelled', 'canceled',
      'devolvida', 'concluido'
    );

  if v_held > 0 and NEW.quantity > OLD.quantity then
    raise exception 'product_quantity_increase_blocked_active_order'
      using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_products_guard_quantity on public.products;
create trigger trg_batata_products_guard_quantity
  before update of quantity on public.products
  for each row
  execute function public.batata_products_guard_quantity_authority();

-- ---------------------------------------------------------------------------
-- Q8 — parcial pós-envio em plataforma capturada → Stripe (não mint carteira)
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_remaining numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute public.order_disputes%rowtype;
  v_status text;
  v_platform boolean := false;
  v_captured boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  if p_order_id is null then return false; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    raise exception 'stripe_refund_already_exists';
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  if v_status not in (
    'pago', 'enviado', 'entregue', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    raise exception 'order_not_paid_for_refund';
  end if;

  v_platform := public.batata_is_platform_payment(v_order.payment_method);
  v_captured :=
    coalesce(v_order.amount_paid_cents, 0) > 0
    or coalesce(nullif(trim(v_order.stripe_payment_intent_id), ''), '') <> '';

  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
  end if;

  if v_order.wallet_release_processed_at is not null then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  if v_remaining <= 0 then
    raise exception 'no_wallet_remaining_for_refund';
  end if;

  select * into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and d.seller_offer_set_by is not null
    and d.seller_offer_set_by = v_order.seller_id
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and lower(coalesce(d.seller_offer_type, '')) in (
      'partial_refund', 'return_and_partial_refund'
    )
  order by d.created_at desc limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);

  if v_percent >= 100
     and v_platform
     and v_captured
     and coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') = '' then
    raise exception 'dispute_full_refund_requires_stripe' using errcode = '42501';
  end if;

  -- Q8: pós-envio com PI activo → refund Stripe, não carteira
  if v_platform
     and v_captured
     and coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') = ''
     and v_status in ('enviado', 'entregue', 'concluido') then
    raise exception 'dispute_partial_refund_requires_stripe' using errcode = '42501';
  end if;

  v_refund := round(least(v_total, v_remaining) * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(
    least(v_remaining - v_refund, greatest(v_total - v_refund - v_commission, 0)),
    0
  );

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id, v_order.id, v_refund, 'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
  else
    v_buyer_done := true;
  end if;

  if v_seller_amount > 0 then
    v_seller_done := public.batata_credit_wallet_once(
      v_order.seller_id, v_order.id, v_seller_amount, 'venda',
      'Venda residual após disputa #' || left(v_order.id::text, 8)
    );
  else
    v_seller_done := true;
  end if;

  if v_buyer_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return v_buyer_done and v_seller_done;
end;
$$;

-- ---------------------------------------------------------------------------
-- Q3 P2 — fragmento #https:// (variante do wrap O-P2)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_proof_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_url text;
  v_paid boolean;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.proof_url is not distinct from OLD.proof_url then
    return NEW;
  end if;

  v_paid :=
    lower(trim(coalesce(OLD.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    )
    or coalesce(OLD.amount_paid_cents, 0) > 0
    or nullif(trim(coalesce(OLD.stripe_payment_intent_id, '')), '') is not null;

  v_url := lower(trim(coalesce(NEW.proof_url, '')));
  if v_url = '' then
    return NEW;
  end if;

  if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  if v_paid then
    if not (
      v_url like 'https://%.supabase.co/storage/%'
      or v_url like 'https://fleaber.app/%'
      or v_url like 'https://www.fleaber.app/%'
      or v_url like 'https://fleaber.pt/%'
      or v_url like 'https://www.fleaber.pt/%'
    ) then
      raise exception 'order_proof_url_denied' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

create or replace function public.batata_order_disputes_guard_label_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_url text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.return_label_url is not distinct from OLD.return_label_url then
    return NEW;
  end if;

  if TG_OP = 'INSERT' and NEW.return_label_url is null then
    return NEW;
  end if;

  v_url := lower(trim(coalesce(NEW.return_label_url, '')));
  if v_url = '' then
    return NEW;
  end if;

  if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;

  if not (
    v_url like 'https://fleaber.app/%'
    or v_url like 'https://www.fleaber.app/%'
    or v_url like 'https://fleaber.pt/%'
    or v_url like 'https://www.fleaber.pt/%'
    or v_url like 'https://%.supabase.co/storage/%'
  ) then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
