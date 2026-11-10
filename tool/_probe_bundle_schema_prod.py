"""Probe product_bundles schema on PROD."""
from __future__ import annotations

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
cur = conn.cursor(cursor_factory=Cur)

cur.execute(
    """
    select column_name, data_type
    from information_schema.columns
    where table_schema='public' and table_name='product_bundles'
    order by ordinal_position
    """
)
print("COLUMNS:")
for r in cur.fetchall():
    print(dict(r) if hasattr(r, "keys") else r)

cur.execute(
    """
    select status, count(*)::int as n
    from public.product_bundles
    group by 1
    order by 2 desc
    """
)
print("STATUSES:", cur.fetchall())

cur.execute(
    """
    select column_name
    from information_schema.columns
    where table_schema='public' and table_name='product_bundles'
      and column_name ilike '%expir%' or
      (table_name='product_bundles' and column_name ilike '%ship%') or
      (table_name='product_bundles' and column_name ilike '%weight%') or
      (table_name='product_bundles' and column_name ilike '%quote%') or
      (table_name='product_bundles' and column_name ilike '%confirm%')
    """
)
print("SPECIAL_COLS:", cur.fetchall())

cur.execute(
    """
    select key, enabled
    from public.fleaber_feature_flags
    where key ilike '%bundle%' or key ilike '%shipping_delta%'
       or key ilike '%weight%' or key ilike '%conjunto%'
    order by 1
    """
)
print("FLAGS:", cur.fetchall())

cur.execute(
    """
    select proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and (proname ilike '%bundle%' or proname ilike '%shipping_delta%'
           or proname ilike '%confirm_shipping%')
    order by 1
    """
)
print("FUNCS:", [r[0] if not hasattr(r, "keys") else r["proname"] for r in cur.fetchall()])
