-- =============================================================================
-- BATATA — Blind E Órbita 1930 (P2/P3; P1 = RTI4-1916 já fechado)
-- P1 E1930-E6-UNLIST-LIVE-STAMP: coberto por sec_rti4_1916 (live activa)
-- P2: buyer INSERT total_eur=0.50 hostil (UI mentira; Stripe OK)
-- P3: Connect allowlist *.fleaber.pt (attacker.fleaber.pt)
-- production_touched: false · fase4: false
-- =============================================================================

create or replace function public.batata_product_bundles_catalog_subtotal(p_product_ids uuid[])
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(p.price), 0)::numeric(12, 2)
  from public.products p
  where p.id = any (p_product_ids);
$$;

revoke all on function public.batata_product_bundles_catalog_subtotal(uuid[])
  from public, anon;
grant execute on function public.batata_product_bundles_catalog_subtotal(uuid[])
  to authenticated, service_role;

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
  v_sub numeric(12, 2);
  v_pct numeric(5, 2);
  v_disc numeric(12, 2);
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
      -- Buyer: sem desconto hostil no INSERT
      NEW.discount_pct := 0;
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

    -- Totais a partir do catálogo (ignora total_eur=0.50 do body)
    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
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

  -- Buyer não muda preço/desconto
  if v_uid is distinct from OLD.seller_id then
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  else
    -- Seller: recomputa a partir do catálogo + discount_pct (não confia no total do body)
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
  end if;

  if v_old_st in ('accepted', 'rejected', 'cancelled', 'cancelado', 'expired', 'purchased') then
    NEW.status := OLD.status;
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
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
  'E1930-P2: totais de conjunto = catálogo; buyer sem desconto hostil; accept seller-only.';

notify pgrst, 'reload schema';
