"""Apply ZIP 149.1 SQL to PROD."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
sql = (
    ROOT
    / "supabase/migrations/20261104160000_bundle_pay_deadline_48h_webhook_idempotent_batata.sql"
).read_text(encoding="utf-8")
conn, Cur = z.pg()
conn.autocommit = True
cur = conn.cursor(cursor_factory=Cur)
cur.execute(sql)
print("APPLY_OK")
cur.execute(
    """
  select key, enabled, note from public.fleaber_feature_flags
  where key like 'bundle_%' order by 1
"""
)
for r in cur.fetchall():
    print(dict(r))
