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

oid = "d8988209-e15e-41a9-83e2-87b2341fd233"
cur.execute(
    """
  select id, status, bundle_id, checkout_attempt_id, is_reservation,
         payment_method, product_id, buyer_id, created_at
  from public.orders where id=%s::uuid
""",
    (oid,),
)
print("ORDER", dict(cur.fetchone()) if cur.rowcount else None)

cur.execute(
    """
  select tgname, pg_get_triggerdef(oid)
  from pg_trigger
  where NOT tgisinternal
    and (tgrelid = 'public.product_bundles'::regclass
         or tgrelid = 'public.orders'::regclass)
  order by tgrelid::regclass::text, tgname
"""
)
for r in cur.fetchall():
    d = dict(r)
    print(d["tgname"], d["pg_get_triggerdef"][:200])
