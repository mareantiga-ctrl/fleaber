-- =============================================================================
-- C1 — fecho P1 reteste independente (RI-E-SELLER-PATCH-OVER, RI-B-BUYER-FORGE-VENDEDOR)
-- Staging only. NÃO Fase 4. NÃO produção.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- E) Accept capacity no trigger UPDATE/INSERT — não só no RPC
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_accept_available(
  p_live_item_id uuid,
  p_exclude_request_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_item_qty int := 0;
  v_already int := 0;
begin
  if p_live_item_id is null then
    return 0;
  end if;
  v_item_qty := coalesce(public.batata_live_item_total_qty(p_live_item_id), 0);
  if v_item_qty <= 0 then
    return 0;
  end if;
  select coalesce(sum(r.requested_qty), 0)::int
  into v_already
  from public.live_reservation_requests r
  where r.live_item_id = p_live_item_id
    and r.status in ('accepted', 'converted')
    and r.id is distinct from p_exclude_request_id;
  return greatest(v_item_qty - v_already, 0);
end;
$fn$;

revoke all on function public.batata_live_reservation_accept_available(uuid, uuid)
  from public, anon;
grant execute on function public.batata_live_reservation_accept_available(uuid, uuid)
  to authenticated, service_role;

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
  v_new_st text;
  v_old_st text;
  v_becoming_accepted boolean := false;
  v_qty_up_while_accepted boolean := false;
begin
  -- service_role / sem JWT: sem rewrite (RPC/lab)
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 or NEW.requested_qty > 99 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  v_is_seller :=
    (NEW.seller_id is not null and NEW.seller_id = v_uid)
    or exists (
      select 1 from public.lives l
      where l.id = NEW.live_id
        and (l.seller_id = v_uid or l.vendedor_id = v_uid)
    )
    or public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations');

  v_new_st := lower(trim(coalesce(NEW.status, '')));

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
      return NEW;
    end if;
    -- Seller INSERT accepted: mesma barreira de capacidade que o RPC
    if v_new_st = 'accepted' then
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

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_becoming_accepted :=
    v_new_st = 'accepted'
    and v_old_st is distinct from 'accepted';
  v_qty_up_while_accepted :=
    v_old_st = 'accepted'
    and v_new_st = 'accepted'
    and NEW.requested_qty is distinct from OLD.requested_qty
    and NEW.requested_qty > OLD.requested_qty;

  -- UPDATE → accepted só seller/staff
  if v_becoming_accepted then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  -- Capacidade: PATCH directo e RPC (JWT seller) — mesma regra
  if v_becoming_accepted or v_qty_up_while_accepted then
    v_avail := public.batata_live_reservation_accept_available(
      NEW.live_item_id,
      NEW.id
    );
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
  end if;

  -- Buyer JWT não muda status nem qty após criar
  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from OLD.status then
      NEW.status := OLD.status;
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
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
  'C1 RI-E: buyer≠accepted; seller accept (PATCH/RPC) ≤ capacidade real; pending lista espera intacta.';

-- ---------------------------------------------------------------------------
-- B) Buyer JWT: author_role sempre comprador (não forja vendedor)
-- ---------------------------------------------------------------------------
create or replace function public.batata_reviews_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_order public.orders%rowtype;
  v_canon text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    NEW.author_role := public.batata_review_author_role_canonical(NEW.author_role);
    return NEW;
  end if;

  NEW.buyer_id := v_uid;
  NEW.is_automatic := false;

  -- Este guard só autoriza o comprador da order → papel canónico comprador.
  -- Seller review (se existir no produto) não passa por este caminho JWT buyer.
  NEW.author_role := 'comprador';
  v_canon := 'comprador';

  if NEW.order_id is null then
    raise exception 'review_order_required' using errcode = '23514';
  end if;

  select * into v_order from public.orders where id = NEW.order_id;
  if not found or v_order.buyer_id is distinct from v_uid then
    raise exception 'review_order_not_yours' using errcode = '42501';
  end if;

  if lower(coalesce(v_order.status, '')) not in ('concluido', 'entregue') then
    raise exception 'review_order_invalid_status' using errcode = '23514';
  end if;

  if not public.batata_order_payment_confirmed(
       v_order.payment_method,
       v_order.status,
       v_order.amount_paid_cents,
       v_order.stripe_payment_intent_id
     ) then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  if public.batata_is_off_platform_payment(v_order.payment_method)
     and coalesce(v_order.stock_units_applied, 0) <= 0
     and coalesce(v_order.amount_paid_cents, 0) <= 0 then
    raise exception 'review_order_unpaid' using errcode = '23514';
  end if;

  NEW.target_id := v_order.seller_id;

  if exists (
    select 1 from public.reviews r
    where r.order_id = NEW.order_id
      and r.buyer_id = v_uid
      and public.batata_review_author_role_canonical(r.author_role) = 'comprador'
  ) then
    raise exception 'review_duplicate' using errcode = '23505';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_reviews_guard_insert on public.reviews;
create trigger trg_batata_reviews_guard_insert
  before insert on public.reviews
  for each row
  execute function public.batata_reviews_guard_insert();

comment on function public.batata_reviews_guard_insert() is
  'C1 RI-B: JWT buyer → author_role=comprador only; aliases buyer/comprador unique.';

notify pgrst, 'reload schema';
