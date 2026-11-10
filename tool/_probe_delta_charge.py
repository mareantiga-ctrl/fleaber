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
  select pg_typeof(public.batata_shipping_delta_charge_cents(100)),
         public.batata_shipping_delta_charge_cents(100)
"""
)
print(dict(cur.fetchone()))
