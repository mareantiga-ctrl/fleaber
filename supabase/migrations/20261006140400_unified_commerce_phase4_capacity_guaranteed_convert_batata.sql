-- =============================================================================
-- BATATA 2026-10-06 — Phase 4: capacity guard allows guaranteed→order convert
-- When checkout_attempt_id is set and buyer already has accepted LRR covering
-- the units, do not treat that accepted hold as blocking the payment order.
-- =============================================================================

create or replace function public.batata_orders_guard_product_hold_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_new text;
  v_old text;
  v_need int;
  v_check jsonb;
  v_sold boolean;
  v_listed boolean;
  v_live_ok boolean;
  v_guaranteed_cover int := 0;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if NEW.product_id is null then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_old := case when TG_OP = 'UPDATE'
    then lower(trim(coalesce(OLD.status, '')))
    else '' end;

  if not public.batata_order_status_holds_product_qty(v_new) then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and public.batata_order_status_holds_product_qty(v_old)
     and v_new is not distinct from v_old then
    return NEW;
  end if;

  select coalesce(p.is_sold, false),
         coalesce(p.list_on_marketplace, false)
    into v_sold, v_listed
  from public.products p
  where p.id = NEW.product_id;

  if not found then
    raise exception 'order_hold_product_missing' using errcode = '23514';
  end if;

  if v_sold then
    raise exception 'order_hold_product_sold' using errcode = '23514';
  end if;

  v_live_ok :=
    NEW.live_item_id is not null
    or NEW.live_id is not null
    or NEW.live_raffle_id is not null;

  if not v_listed and not v_live_ok then
    raise exception 'order_hold_product_not_listed' using errcode = '23514';
  end if;

  v_need := greatest(coalesce(NEW.quantity, 1), 1);

  -- Phase 4 convert: payment order for an existing accepted guarantee
  if NEW.checkout_attempt_id is not null and NEW.buyer_id is not null then
    select coalesce(sum(greatest(coalesce(r.requested_qty, 1), 1)), 0)::int
      into v_guaranteed_cover
    from public.live_reservation_requests r
    join public.live_items li on li.id = r.live_item_id
    where r.buyer_id = NEW.buyer_id
      and r.status = 'accepted'
      and (
        (NEW.live_item_id is not null and r.live_item_id = NEW.live_item_id)
        or coalesce(li.product_id, li.checkout_product_id) = NEW.product_id
      );
    if v_guaranteed_cover >= v_need then
      return NEW;
    end if;
  end if;

  v_check := public.batata_product_checkout_available(
    NEW.product_id,
    NEW.id,
    v_need
  );

  if coalesce((v_check->>'ok')::boolean, false) is not true then
    raise exception 'order_hold_exceeds_stock'
      using errcode = '23514';
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_product_hold_capacity() is
  'E6-P1 + Phase4: JWT hold blocks oversell; guaranteed convert via checkout_attempt_id allowed.';

notify pgrst, 'reload schema';
