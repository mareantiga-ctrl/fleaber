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
for name in [
    "batata_product_checkout_available",
    "batata_is_admin",
    "batata_shipping_delta_charge_cents",
    "batata_flag_enabled",
    "digest",
]:
    cur.execute(
        """
      select pg_get_function_identity_arguments(p.oid)
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where (n.nspname='public' or n.nspname='extensions') and p.proname=%s
    """,
        (name,),
    )
    print(name, [r[0] if not hasattr(r, "keys") else list(r.values())[0] for r in cur.fetchall()])
cur.execute(
    "select extname from pg_extension where extname in ('pgcrypto','uuid-ossp')"
)
print("ext", cur.fetchall())
cur.execute(
    """
  select column_name from information_schema.columns
  where table_name='fleaber_feature_flags' order by 1
"""
)
print("flag_cols", [r[0] if not hasattr(r, "keys") else r["column_name"] for r in cur.fetchall()])
