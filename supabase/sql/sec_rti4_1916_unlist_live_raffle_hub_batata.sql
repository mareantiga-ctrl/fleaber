-- =============================================================================
-- BATATA — Indep RTI4-1916 (segunda onda)
-- P1: unlist + live_id ended ainda hold/checkout/captura
-- P1: live_raffle_id forjado bypassa unlist → strip → hold fantasma (DoS stock)
-- P2: hub_products_public mostra is_sold=true
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: excepção montra só com DIRECTO ACTIVO (não ended / não raffle JWT)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_is_active_now(p_live_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.lives l
    where l.id = p_live_id
      and (
        coalesce(l.is_active, false) = true
        or lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
      )
  );
$$;

revoke all on function public.batata_live_is_active_now(uuid) from public, anon;
grant execute on function public.batata_live_is_active_now(uuid)
  to authenticated, service_role;

comment on function public.batata_live_is_active_now(uuid) is
  'RTI4-1916: directo a decorrer (is_active ou status live).';

create or replace function public.batata_order_unlist_live_context_ok(
  p_product_id uuid,
  p_seller_id uuid,
  p_live_id uuid,
  p_live_item_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_li_live uuid;
  v_li_seller uuid;
  v_li_prod uuid;
  v_li_checkout uuid;
  v_live_seller uuid;
begin
  -- live_item: produto ligado + live activa
  if p_live_item_id is not null then
    select li.live_id, li.seller_id, li.product_id, li.checkout_product_id
      into v_li_live, v_li_seller, v_li_prod, v_li_checkout
    from public.live_items li
    where li.id = p_live_item_id;

    if found
       and public.batata_live_is_active_now(v_li_live)
       and (
         p_product_id is null
         or p_product_id is not distinct from v_li_prod
         or p_product_id is not distinct from v_li_checkout
       )
       and (
         p_seller_id is null
         or v_li_seller is null
         or p_seller_id is not distinct from v_li_seller
       )
       and (p_live_id is null or p_live_id is not distinct from v_li_live)
    then
      return true;
    end if;
  end if;

  -- Só live_id: mesma loja + directo activo (não basta UUID de live ended)
  if p_live_id is not null and public.batata_live_is_active_now(p_live_id) then
    select l.seller_id into v_live_seller
    from public.lives l
    where l.id = p_live_id;

    if found
       and (
         p_seller_id is null
         or v_live_seller is null
         or p_seller_id is not distinct from v_live_seller
       )
    then
      return true;
    end if;
  end if;

  return false;
end;
$fn$;

revoke all on function public.batata_order_unlist_live_context_ok(uuid, uuid, uuid, uuid)
  from public, anon;
grant execute on function public.batata_order_unlist_live_context_ok(uuid, uuid, uuid, uuid)
  to authenticated, service_role;

comment on function public.batata_order_unlist_live_context_ok(uuid, uuid, uuid, uuid) is
  'RTI4-1916: bypass unlist só com live activa coerente. Sem live_raffle_id (JWT).';

-- ---------------------------------------------------------------------------
-- Hold JWT: relistar regra montra
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_product_hold_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_allow text := coalesce(current_setting('batata.raffle_prize_write', true), '');
  v_new text;
  v_old text;
  v_need int;
  v_check jsonb;
  v_sold boolean;
  v_listed boolean;
  v_live_ok boolean;
begin
  -- Prémio rifa via RPC DEFINER: não aplicar gate montra JWT
  if v_allow = '1' then
    return NEW;
  end if;

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

  -- RTI4: NÃO confiar em live_raffle_id do JWT (strip silencioso deixava hold).
  -- Só live_item / live_id de directo ACTIVO.
  v_live_ok := public.batata_order_unlist_live_context_ok(
    NEW.product_id,
    NEW.seller_id,
    NEW.live_id,
    NEW.live_item_id
  );

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
  before insert or update of status, quantity, product_id, live_id, live_item_id
  on public.orders
  for each row
  execute function public.batata_orders_guard_product_hold_capacity();

comment on function public.batata_orders_guard_product_hold_capacity() is
  'RTI4-1916: hold JWT bloqueia is_sold / unlist sem live ACTIVA (raffle JWT ignorado).';

-- ---------------------------------------------------------------------------
-- P2: Hub montra sem vendidos
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
  and coalesce(pr.is_sold, false) = false;

comment on view public.hub_products_public is
  'Marketplace público (listado e não vendido). Sem stock interno/custo.';

grant select on public.hub_products_public to anon, authenticated;
