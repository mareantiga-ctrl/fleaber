"""Fix product_bundles_status_check + hold trigger RAISE syntax; re-apply RPCs."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
conn, Cur = z.pg()
conn.autocommit = True
cur = conn.cursor(cursor_factory=Cur)

cur.execute(
    """
  select conname, pg_get_constraintdef(oid)
  from pg_constraint
  where conrelid = 'public.product_bundles'::regclass
    and contype = 'c'
"""
)
print("BEFORE", [dict(r) for r in cur.fetchall()])

cur.execute(
    """
  alter table public.product_bundles
    drop constraint if exists product_bundles_status_check;
  alter table public.product_bundles
    add constraint product_bundles_status_check
    check (
      lower(trim(status)) in (
        'pending',
        'awaiting_payment',
        'accepted',
        'rejected',
        'cancelled',
        'cancelado',
        'expired',
        'purchased'
      )
    );
"""
)
print("CHK_OK")

# Fix hold trigger RAISE (MESSAGE duplicated)
cur.execute(
    r"""
create or replace function public.batata_orders_bundle_no_prepay_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_flag_enabled('bundle_quote_before_pay_v1') then
    return NEW;
  end if;
  if TG_OP = 'INSERT' or TG_OP = 'UPDATE' then
    if NEW.bundle_id is not null
       and coalesce(auth.role(), '') = 'authenticated'
       and lower(trim(coalesce(NEW.status, ''))) in ('reservado', 'aguarda_confirmacao')
       and NEW.checkout_attempt_id is null
       and coalesce(NEW.is_reservation, false) = true then
      raise exception 'bundle_no_stock_hold_until_pay'
        using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end;
$$;
"""
)
print("HOLD_TRIG_OK")

# Also fix guard accepted raise
cur.execute(
    r"""
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
  v_dead int := 0;
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
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
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

    select count(*)::int into v_dead
    from unnest(NEW.product_ids) as pid
    join public.products p on p.id = pid
    where coalesce(p.list_on_marketplace, false) = false
       or coalesce(p.is_sold, false) = true;
    if v_dead > 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;

    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
    NEW.seller_confirm_expires_at := coalesce(
      NEW.seller_confirm_expires_at,
      timezone('utc', now()) + interval '48 hours'
    );
    NEW.rule_version := coalesce(NEW.rule_version, 'quote_before_pay_v1');
    return NEW;
  end if;

  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    if v_new_st = 'accepted' then
      raise exception 'bundle_use_confirm_quote_rpc' using errcode = 'P0001';
    end if;
    if v_new_st = 'awaiting_payment' and v_uid is distinct from OLD.seller_id then
      raise exception 'bundle_quote_seller_only' using errcode = '42501';
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado', 'expired')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_party' using errcode = '42501';
    end if;
  end if;

  if v_uid is distinct from OLD.seller_id then
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.total_eur := OLD.total_eur;
  else
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    else
      v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
      v_disc := round(v_sub * (v_pct / 100.0), 2);
      NEW.subtotal_eur := v_sub;
      NEW.discount_pct := v_pct;
      NEW.discount_eur := v_disc;
      NEW.total_eur := greatest(v_sub - v_disc, 0);
    end if;
  end if;

  if v_old_st in (
    'awaiting_payment', 'accepted', 'rejected', 'cancelled', 'cancelado',
    'expired', 'purchased'
  ) and v_new_st is distinct from v_old_st then
    if not (
      (v_old_st = 'awaiting_payment' and v_new_st in ('pending', 'cancelled', 'expired', 'purchased'))
      or (v_old_st = 'pending' and v_new_st in ('awaiting_payment', 'cancelled', 'expired'))
      or (v_new_st in ('cancelled', 'expired', 'purchased'))
    ) then
      NEW.status := OLD.status;
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    end if;
  end if;

  return NEW;
end;
$fn$;
"""
)
print("GUARD_OK")

# Persist into migration file appendix reminder — also append SQL file patch
patch = ROOT / "supabase/migrations/20261104151000_bundle_status_check_awaiting_payment_batata.sql"
patch.write_text(
    """-- ZIP149 hotfix: status check + RAISE syntax
alter table public.product_bundles
  drop constraint if exists product_bundles_status_check;
alter table public.product_bundles
  add constraint product_bundles_status_check
  check (
    lower(trim(status)) in (
      'pending','awaiting_payment','accepted','rejected',
      'cancelled','cancelado','expired','purchased'
    )
  );
""",
    encoding="utf-8",
)
print("WROTE", patch)
