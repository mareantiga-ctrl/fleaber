-- T 0850 + U 0855 — P0/P1/P2 após re-audit
-- P0 T: não reabrir pago após envio/receção
-- P0 U: oferta qty=1; conjunto completo (Edge)
-- P2 T: qty produto ≥ held; live_item qty ≥ reservas e ≤ produto
-- P2 T: buyer resolvida exige decisão
-- P2 U: Hub qty>0 (idempotente)
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- P0 — seller/buyer JWT não voltam a pago depois de enviado/entregue/…
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_no_reopen_pago()
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
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  v_new := lower(trim(coalesce(NEW.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  if v_new = 'pago' and v_old in (
    'enviado', 'entregue', 'concluido', 'concluído',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  ) then
    raise exception 'order_cannot_reopen_pago' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_no_reopen_pago on public.orders;
create trigger trg_batata_orders_guard_no_reopen_pago
  before update of status on public.orders
  for each row
  execute function public.batata_orders_guard_no_reopen_pago();

comment on function public.batata_orders_guard_no_reopen_pago() is
  'T0850-P0: após envio/receção o estado não regressa a pago (bloqueia mint+refund-order).';

-- ---------------------------------------------------------------------------
-- P0 U — oferta aceite = 1 unidade
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_offer_qty()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if NEW.product_offer_id is not null
     and coalesce(NEW.quantity, 1) > 1 then
    raise exception 'offer_quantity_must_be_one' using errcode = '23514';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_offer_qty on public.orders;
create trigger trg_batata_orders_guard_offer_qty
  before insert on public.orders
  for each row
  execute function public.batata_orders_guard_offer_qty();

comment on function public.batata_orders_guard_offer_qty() is
  'U0855-P0: product_offer_id só com quantity=1.';

-- ---------------------------------------------------------------------------
-- P2 — não baixar products.quantity abaixo do hold activo
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

  if NEW.quantity < 0 then
    raise exception 'product_quantity_invalid' using errcode = '23514';
  end if;

  -- T4: não pôr 0 com unidade ainda em encomenda activa (já descontada no qty)
  if v_held > 0 and coalesce(NEW.quantity, 0) < coalesce(OLD.quantity, 0)
     and coalesce(NEW.quantity, 0) = 0 then
    raise exception 'product_quantity_below_held' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- P2 — live_item qty ≥ reservas; se ligado a produto, ≤ products.quantity
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_items_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_live_owner uuid;
  v_product_seller uuid;
  v_has_active_res boolean := false;
  v_reserved int := 0;
  v_prod_qty int;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id)
      into v_live_owner
    from public.lives l
    where l.id = NEW.live_id
    limit 1;
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations') then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity
      into v_product_seller, v_prod_qty
    from public.products p
    where p.id = NEW.product_id
    limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    if v_prod_qty is not null and coalesce(NEW.quantity, 0) > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
        and r.status in ('pending', 'accepted', 'converted')
    ) into v_has_active_res;
    if v_has_active_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int
      into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('pending', 'accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- P2 — resolvida JWT exige buyer_decision (comprador também)
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
    NEW.return_label_url := OLD.return_label_url;
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  select o.seller_id into v_order_seller
  from public.orders o
  where o.id = NEW.order_id
  limit 1;

  if v_order_seller = v_uid
     and not public.batata_is_admin()
     and NEW.buyer_decision is distinct from OLD.buyer_decision then
    NEW.buyer_decision := OLD.buyer_decision;
    v_buyer_decision := lower(trim(coalesce(NEW.buyer_decision, '')));
  end if;

  if v_order_seller = v_uid
     and not public.batata_is_admin()
     and v_new_st in ('resolvida', 'recusada')
     and v_new_st is distinct from v_old_st then
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  if v_new_st = 'resolvida'
     and v_old_st is distinct from 'resolvida'
     and not public.batata_is_admin()
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

  if v_new_st = 'escalada_fleaber' then
    NEW.current_turn := 'administracao';
  elsif v_new_turn = 'administracao' and not v_terminal then
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

-- ---------------------------------------------------------------------------
-- P2 U — Hub sem qty=0
-- ---------------------------------------------------------------------------
create or replace view public.hub_products_public
with (security_barrier = true)
as
select
  pr.id,
  pr.seller_id,
  hp.handle as seller_handle,
  pr.title,
  pr.price,
  pr.image_urls,
  pr.category,
  pr.state,
  pr.description,
  pr.ref_code,
  pr.clothing_size,
  pr.gender,
  pr.created_at,
  coalesce(pr.is_sold, false) as is_sold
from public.products pr
join public.hub_profiles_public hp on hp.id = pr.seller_id
where coalesce(pr.list_on_marketplace, false) = true
  and coalesce(pr.is_sold, false) = false
  and coalesce(pr.quantity, 0) > 0;

comment on view public.hub_products_public is
  'Marketplace público: listado, não vendido, quantity>0.';

grant select on public.hub_products_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- P0 U — selo: oferta aceite não multiplica qty
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_seal_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_jwt boolean := (v_role = 'authenticated' and v_uid is not null);
  v_unit_cents int := 0;
  v_li numeric;
  v_prod numeric;
  v_offer public.product_offers%rowtype;
  v_auth_qty int;
  v_res_qty int := 0;
  v_client_offer_id uuid;
  v_min_total numeric;
begin
  v_client_offer_id := NEW.product_offer_id;

  if v_jwt then
    NEW.contract_unit_cents := null;
    NEW.contract_qty := null;
  elsif NEW.contract_unit_cents is not null and NEW.contract_unit_cents > 0 then
    if NEW.contract_qty is null or NEW.contract_qty < 1 then
      NEW.contract_qty := greatest(coalesce(NEW.quantity, 1), 1);
    end if;
    NEW.quantity := NEW.contract_qty;
    return NEW;
  end if;

  if NEW.live_raffle_id is not null
     and lower(trim(coalesce(NEW.status, ''))) = 'premio_rifa' then
    NEW.contract_unit_cents := 0;
    NEW.contract_qty := 1;
    NEW.quantity := 1;
    return NEW;
  end if;

  v_auth_qty := greatest(coalesce(NEW.quantity, 1), 1);
  if v_auth_qty > 99 then
    raise exception 'invalid_order_quantity' using errcode = '23514';
  end if;

  if v_jwt
     and NEW.live_item_id is not null
     and NEW.buyer_id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_res_qty
    from public.live_reservation_requests r
    where r.live_item_id = NEW.live_item_id
      and r.buyer_id = NEW.buyer_id
      and r.status in ('accepted', 'converted');
    if v_res_qty > 0 and v_auth_qty > v_res_qty then
      raise exception 'order_quantity_exceeds_reservation'
        using errcode = '23514';
    end if;
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

  v_offer := null;
  if NEW.product_offer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.id = NEW.product_offer_id;
  elsif NEW.product_id is not null and NEW.buyer_id is not null then
    select * into v_offer
    from public.product_offers po
    where po.product_id = NEW.product_id
      and po.buyer_id = NEW.buyer_id
      and (NEW.seller_id is null or po.seller_id = NEW.seller_id)
      and lower(trim(coalesce(po.status, ''))) = 'accepted'
      and (po.expires_at is null or po.expires_at > now())
      and not public.batata_product_offer_is_consumed(po.id, NEW.id)
    order by coalesce(po.responded_at, po.created_at) desc
    limit 1;
  end if;

  if v_offer.id is not null then
    if lower(trim(coalesce(v_offer.status, ''))) is distinct from 'accepted'
       or v_offer.product_id is distinct from NEW.product_id
       or v_offer.buyer_id is distinct from NEW.buyer_id
       or (NEW.seller_id is not null and v_offer.seller_id is distinct from NEW.seller_id)
       or (v_offer.expires_at is not null and v_offer.expires_at <= now())
       or coalesce(v_offer.amount, 0) <= 0
       or v_offer.responded_at is null then
      NEW.product_offer_id := null;
    elsif public.batata_product_offer_is_consumed(v_offer.id, NEW.id) then
      if v_client_offer_id is not null then
        raise exception 'offer_already_consumed' using errcode = '23514';
      end if;
      NEW.product_offer_id := null;
    else
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
      if v_auth_qty > 1 then
        raise exception 'offer_quantity_must_be_one' using errcode = '23514';
      end if;
      v_auth_qty := 1;
    end if;
  else
    if v_client_offer_id is not null
       and public.batata_product_offer_is_consumed(v_client_offer_id, NEW.id) then
      raise exception 'offer_already_consumed' using errcode = '23514';
    end if;
    NEW.product_offer_id := null;
  end if;

  if v_unit_cents <= 0 then
    raise exception 'order_contract_price_missing' using errcode = '23514';
  end if;

  NEW.contract_unit_cents := v_unit_cents;
  NEW.contract_qty := v_auth_qty;
  NEW.quantity := v_auth_qty;

  if v_jwt then
    v_min_total := (v_unit_cents::numeric * v_auth_qty::numeric) / 100.0;
    NEW.price_total := round(v_min_total, 2);
    if NEW.product_offer_id is null
       and lower(coalesce(NEW.payment_method, '')) like '%proposta%' then
      NEW.payment_method := 'Pagamento na app';
    end if;
  end if;

  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
