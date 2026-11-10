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
  select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_product_checkout_available'
  limit 1
"""
)
row = cur.fetchone()
print(list(row.values())[0][:2500])
print("--- held ---")
cur.execute(
    """
  select pg_get_function_identity_arguments(p.oid) as args
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_product_held_qty'
"""
)
print([r["args"] for r in cur.fetchall()])
cur.execute(
    """
  select column_name from information_schema.columns
  where table_name='fleaber_feature_flags'
"""
)
print("flags", [r["column_name"] for r in cur.fetchall()])
cur.execute(
    """
  select pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_product_held_qty'
  order by p.oid desc limit 1
"""
)
print("--- held def ---")
print(list(cur.fetchone().values())[0][:1500])
