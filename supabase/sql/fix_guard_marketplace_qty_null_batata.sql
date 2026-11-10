-- BATATA 2026-09-20 — guard live_items: cap alinhado com batata_live_item_total_qty
-- Staging only. Produção NÃO aplicar neste passo.
--
-- Causa: marketplace_product tem live_items.quantity NULL por contrato
--   (live_items_kind_stock_chk). O guard usava coalesce(NEW.quantity,0)=0
--   → live_item_qty_below_reservations após 1ª accept apesar de products.quantity>0.
--
-- Fix: autoridade explícita por item_kind (igual total_qty / inventário BATATA):
--   marketplace_product + product_id → products.quantity
--   live_only / resto → live_items.quantity (coalesce 0)
-- Anti-oversell, locks e restantes checks do guard mantêm-se.

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
  v_has_any_res boolean := false;
  v_reserved int := 0;
  v_cap int := 0;
  v_prod_qty int;
  v_is_staff boolean := false;
  v_can_mark boolean := false;
  v_mark_sold_internal boolean := false;
  v_kind text;
begin
  v_mark_sold_internal :=
    coalesce(current_setting('batata.mark_sold_internal', true), '') = '1';

  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if lower(trim(coalesce(NEW.status, ''))) = 'sold'
     and (
       TG_OP = 'INSERT'
       or lower(trim(coalesce(OLD.status, ''))) is distinct from 'sold'
     )
     and not v_mark_sold_internal
     and v_role is distinct from 'service_role' then
    raise exception 'live_item_status_sold_rpc_only' using errcode = '42501';
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id) into v_live_owner
    from public.lives l where l.id = NEW.live_id limit 1;
  end if;

  if v_live_owner is not null then
    v_is_staff := v_live_owner is distinct from v_uid
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations');
    v_can_mark := v_live_owner = v_uid
      or public.batata_staff_has_permission(v_live_owner, 'can_mark_items_sold');
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin() and not v_is_staff then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  v_kind := lower(trim(coalesce(NEW.item_kind, '')));

  -- Seller/owner ou staff com mark: pode aumentar qty (incl. live_only sem catálogo).
  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and v_role is distinct from 'service_role' then
    if not coalesce(v_can_mark, false) then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    end if;
  end if;

  if NEW.checkout_product_id is not null and v_live_owner is not null then
    select p.seller_id into v_product_seller
    from public.products p where p.id = NEW.checkout_product_id limit 1;
    if v_product_seller is not null
       and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_checkout_product_seller_mismatch'
        using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
    ) into v_has_any_res;
    if v_has_any_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity into v_product_seller, v_prod_qty
    from public.products p where p.id = NEW.product_id limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    -- marketplace: quantity na row é NULL por CHECK; este bound só aplica se
    -- alguém tentar gravar quantity explícita > stock do produto.
    if v_prod_qty is not null and NEW.quantity is not null
       and NEW.quantity > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('accepted', 'converted');

    -- Cap = mesma autoridade que batata_live_item_total_qty (sem gate broadcasting:
    -- o guard corre em UPDATE autenticado do dono/staff durante recompute).
    if v_kind = 'marketplace_product' and NEW.product_id is not null then
      select p.quantity into v_prod_qty
      from public.products p where p.id = NEW.product_id limit 1;
      if v_prod_qty is null then
        v_cap := 0;
      else
        v_cap := greatest(v_prod_qty, 0);
      end if;
    else
      -- live_only (quantity NOT NULL >=1) e fallback
      v_cap := greatest(coalesce(NEW.quantity, 0), 0);
    end if;

    if v_cap < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_live_items_guard_authority() is
  'Guard live_items: anti-oversell. Cap marketplace=products.quantity; live_only=row.quantity. BATATA 2026-09-20.';

notify pgrst, 'reload schema';
