"""Apply ZIP 149 bundle quote-before-pay migration to PROD."""
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

sql = (
    ROOT / "supabase/migrations/20261104150000_bundle_quote_before_pay_batata.sql"
).read_text(encoding="utf-8")

conn, Cur = z.pg()
conn.autocommit = True
cur = conn.cursor(cursor_factory=Cur)
try:
    cur.execute(sql)
    print("APPLY_OK")
except Exception as e:
    print("APPLY_FAIL", e)
    raise

cur.execute(
    """
  select key, enabled from public.fleaber_feature_flags
  where key like 'bundle_%' order by 1
"""
)
print("FLAGS", [dict(r) for r in cur.fetchall()])
cur.execute(
    """
  select proname from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and proname like 'batata_bundle_%'
  order by 1
"""
)
print("FUNCS", [r["proname"] for r in cur.fetchall()])
