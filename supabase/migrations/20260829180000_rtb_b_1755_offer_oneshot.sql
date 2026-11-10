-- RTB-B-1755-P1-OFFER-MULTI-BIND + OFFER-REUSE (staging BATATA)
-- Classificação: BUG — oferta aceite = 1 unidade negociada, não autorização N×.
-- Preserva: 1ª order (buyer leftover ou seller com product_offer_id) ao preço aceite;
--           2.ª order do mesmo SKU → catálogo (ou 403 se reenvia offer_id consumida).
-- Blind G: só P2 — sem alteração.
-- production_touched: false · fase4: false

-- Oferta já ligada a order activa (não cancelada).
create or replace function public.batata_product_offer_is_consumed(
  p_offer_id uuid,
  p_exclude_order_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_offer_id is null then false
    else exists (
      select 1
      from public.orders o
      where o.product_offer_id = p_offer_id
        and (p_exclude_order_id is null or o.id is distinct from p_exclude_order_id)
        and lower(trim(coalesce(o.status, ''))) not in (
          'cancelado', 'cancelled', 'rejected', 'expired'
        )
    )
  end;
$$;

revoke all on function public.batata_product_offer_is_consumed(uuid, uuid)
  from public, anon;
grant execute on function public.batata_product_offer_is_consumed(uuid, uuid)
  to authenticated, service_role;

comment on function public.batata_product_offer_is_consumed(uuid, uuid) is
  'RTB-B-1755: oferta aceite one-shot — true se já há order activa com este product_offer_id.';

-- Race: no máximo 1 order activa por oferta.
drop index if exists public.orders_one_active_per_product_offer;
create unique index orders_one_active_per_product_offer
  on public.orders (product_offer_id)
  where product_offer_id is not null
    and lower(trim(coalesce(status, ''))) not in (
      'cancelado', 'cancelled', 'rejected', 'expired'
    );

-- ---------------------------------------------------------------------------
-- Selo: leftover/explícito só se oferta NÃO consumida
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

  -- Proposta: aceite + partes + NÃO consumida (one-shot).
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
      -- Explicit reuse → fail; leftover já filtrado acima, mas defesa em profundidade.
      if v_client_offer_id is not null then
        raise exception 'offer_already_consumed' using errcode = '23514';
      end if;
      NEW.product_offer_id := null;
    else
      NEW.product_offer_id := v_offer.id;
      v_unit_cents := greatest(1, round(v_offer.amount * 100)::int);
    end if;
  else
    -- Explicit id inválido/consumido sem row válida
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
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_seal_contract on public.orders;
create trigger trg_batata_orders_seal_contract
  before insert on public.orders
  for each row
  execute function public.batata_orders_seal_contract();

comment on function public.batata_orders_seal_contract() is
  'SAT + RTB-B-1755: contract_* servidor; oferta aceite one-shot (não leftover N×).';

-- Attribution seller: oferta aceite E ainda não consumida
create or replace function public.batata_orders_guard_buyer_attribution()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean;
  v_ok boolean := false;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP is distinct from 'INSERT' then
    return NEW;
  end if;

  v_is_seller := NEW.seller_id is not null and NEW.seller_id = v_uid;

  if NEW.buyer_id is not null and NEW.buyer_id = v_uid then
    return NEW;
  end if;

  if v_is_seller and NEW.buyer_id is not null and NEW.buyer_id is distinct from v_uid then
    if NEW.product_offer_id is not null then
      select exists (
        select 1
        from public.product_offers po
        where po.id = NEW.product_offer_id
          and po.seller_id = NEW.seller_id
          and po.buyer_id = NEW.buyer_id
          and po.product_id is not distinct from NEW.product_id
          and lower(trim(coalesce(po.status, ''))) = 'accepted'
          and po.responded_at is not null
          and (po.expires_at is null or po.expires_at > now())
          and not public.batata_product_offer_is_consumed(po.id, NEW.id)
      ) into v_ok;
    end if;

    if not v_ok then
      raise exception 'order_buyer_attribution_denied'
        using errcode = '42501';
    end if;
    return NEW;
  end if;

  raise exception 'order_buyer_attribution_denied'
    using errcode = '42501';
end;
$fn$;

comment on function public.batata_orders_guard_buyer_attribution() is
  'RTB-B-P1-01 + 1755: seller só atribui buyer com offer accepted e ainda não consumida.';

notify pgrst, 'reload schema';
