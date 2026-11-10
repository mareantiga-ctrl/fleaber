-- =============================================================================
-- BATATA — Blind E 1810 (órbita) + Indep 1752 P3 higiene
-- P1: produto is_sold / unlist ainda vende
-- P2: RLS shadow ended + bundle self-accept
-- P3: discovery unpublished; admin RPC anon grant
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- E6-DEAD-CAPTURE P1 — stock check respeita is_sold
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_checkout_available(
  p_product_id uuid,
  p_exclude_order_id uuid,
  p_need_qty integer,
  p_exclude_order_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock int;
  v_held int;
  v_avail int;
  v_need int := greatest(coalesce(p_need_qty, 1), 1);
  v_excl uuid[] := coalesce(p_exclude_order_ids, array[]::uuid[]);
  v_sold boolean;
begin
  if p_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_product');
  end if;

  perform pg_advisory_xact_lock(hashtext(p_product_id::text || ':checkout_stock'));

  select p.quantity, coalesce(p.is_sold, false)
  into v_stock, v_sold
  from public.products p
  where p.id = p_product_id
  for update;

  if v_stock is null then
    return jsonb_build_object('ok', false, 'error', 'product_not_found');
  end if;

  if v_sold then
    return jsonb_build_object(
      'ok', false,
      'error', 'product_sold',
      'stock', v_stock,
      'held', 0,
      'available', 0,
      'need', v_need
    );
  end if;

  if p_exclude_order_id is not null
     and not (p_exclude_order_id = any (v_excl)) then
    v_excl := array_append(v_excl, p_exclude_order_id);
  end if;

  v_held := public.batata_product_held_qty(p_product_id, null, v_excl);
  v_avail := greatest(v_stock - v_held, 0);

  return jsonb_build_object(
    'ok', v_avail >= v_need,
    'stock', v_stock,
    'held', v_held,
    'available', v_avail,
    'need', v_need
  );
end;
$$;

revoke all on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[])
  from public, anon;
grant execute on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[])
  to authenticated, service_role;

comment on function public.batata_product_checkout_available(uuid, uuid, integer, uuid[]) is
  'E6-P1: is_sold → ok=false; stock−holds.';

-- Hold JWT: unlist + sem live/raffle → bloqueia (mesmo com qty>0)
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

  -- Marketplace: tem de estar listado. Live/rifa: order traz live_* .
  v_live_ok :=
    NEW.live_item_id is not null
    or NEW.live_id is not null
    or NEW.live_raffle_id is not null;

  if not v_listed and not v_live_ok then
    raise exception 'order_hold_product_not_listed' using errcode = '23514';
  end if;

  v_need := greatest(coalesce(NEW.quantity, 1), 1);
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

drop trigger if exists trg_batata_orders_guard_product_hold_capacity on public.orders;
create trigger trg_batata_orders_guard_product_hold_capacity
  before insert or update of status, quantity, product_id
  on public.orders
  for each row
  execute function public.batata_orders_guard_product_hold_capacity();

comment on function public.batata_orders_guard_product_hold_capacity() is
  'E6-P1: JWT hold bloqueia is_sold e unlist sem live/rifa.';

-- ---------------------------------------------------------------------------
-- E6-AUTH-READ-UNLISTED P2 — shadow só live activa OU buyer com ligação
-- ---------------------------------------------------------------------------
drop policy if exists "products_select_live_checkout_shadow" on public.products;
create policy "products_select_live_checkout_shadow"
  on public.products
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.live_items li
      inner join public.lives l on l.id = li.live_id
      where (
        li.checkout_product_id = products.id
        or li.product_id = products.id
      )
      and (
        -- Directo a decorrer
        (
          coalesce(l.is_active, false) = true
          or lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
        )
        -- Ou comprador com reserva/order neste item
        or exists (
          select 1
          from public.live_reservation_requests r
          where r.buyer_id = auth.uid()
            and r.live_item_id = li.id
            and lower(trim(coalesce(r.status, ''))) in (
              'pending', 'accepted', 'converted'
            )
        )
        or exists (
          select 1
          from public.orders o
          where o.buyer_id = auth.uid()
            and (
              o.product_id = products.id
              or o.live_item_id = li.id
            )
            and lower(trim(coalesce(o.status, ''))) not in (
              'cancelado', 'cancelled', 'expirado', 'expired'
            )
        )
      )
    )
  );

comment on policy "products_select_live_checkout_shadow" on public.products is
  'E6-P2: sem SELECT global de unlisted via lives ended; só live activa ou buyer ligado.';

-- ---------------------------------------------------------------------------
-- E4-BUNDLE-SELF-ACCEPT P2 — só seller aceita; totais imutáveis pelo buyer
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
  v_new_st text;
  v_old_st text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
      NEW.status := coalesce(nullif(trim(NEW.status), ''), 'pending');
      if lower(trim(NEW.status)) is distinct from 'pending' then
        NEW.status := 'pending';
      end if;
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      NEW.status := 'pending';
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;

    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;
    return NEW;
  end if;

  -- UPDATE
  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    if v_new_st = 'accepted' and v_uid is distinct from OLD.seller_id then
      raise exception 'bundle_accept_seller_only' using errcode = '42501';
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_authorized' using errcode = '42501';
    end if;
  end if;

  -- Buyer não muda preço/desconto do conjunto
  if v_uid is distinct from OLD.seller_id then
    NEW.total_eur := OLD.total_eur;
    if NEW.discount_pct is distinct from OLD.discount_pct then
      NEW.discount_pct := OLD.discount_pct;
    end if;
  end if;

  if v_old_st in ('accepted', 'rejected', 'cancelled', 'cancelado', 'expired') then
    NEW.status := OLD.status;
    NEW.total_eur := OLD.total_eur;
    NEW.discount_pct := OLD.discount_pct;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_product_bundles_guard_write on public.product_bundles;
create trigger trg_batata_product_bundles_guard_write
  before insert or update on public.product_bundles
  for each row
  execute function public.batata_product_bundles_guard_write();

comment on function public.batata_product_bundles_guard_write() is
  'E4-P2: accepted só seller; buyer não muta total_eur/discount.';

-- ---------------------------------------------------------------------------
-- E1-DISCOVERY-UNPUB P3 — discovery só published OU a live agora
-- ---------------------------------------------------------------------------
create or replace view public.hub_profiles_discovery_public
with (security_barrier = true)
as
select
  p.id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as handle,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  coalesce(p.vacation_mode, false) as vacation_mode,
  (p.phone_verified_at is not null) as phone_verified,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  coalesce(vs.total_seguidores, 0)::int as follower_count,
  nullif(trim(p.hub_bio), '') as hub_bio,
  coalesce(p.hub_published, false) as hub_published
from public.profiles p
left join public.v_seguidores_stats vs on vs.profile_id = p.id
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    coalesce(p.hub_published, false) = true
    or coalesce(p.is_live, false) = true
  );

comment on view public.hub_profiles_discovery_public is
  'E1-P3: discovery só hub_published ou is_live; sem enum unpublished.';

grant select on public.hub_profiles_discovery_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RT1752-P3-02 — anon sem EXECUTE em admin resolve
-- ---------------------------------------------------------------------------
revoke all on function public.batata_admin_resolve_dispute(uuid, text, text)
  from public, anon;

notify pgrst, 'reload schema';
