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
  select column_name, is_nullable, column_default
  from information_schema.columns
  where table_name='product_bundles'
  order by ordinal_position
"""
)
for r in cur.fetchall():
    print(dict(r))
print("helpers", hasattr(z, "stripe_session_with_pi"), hasattr(z, "post_webhook"), hasattr(z, "pay_checkout_session"))
