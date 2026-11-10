"""Apply ZIP 144.3 migration to PROD via pooler."""
import subprocess
from pathlib import Path

import psycopg2

PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split(
    'PS_PW = r"""'
)[1].split('"""')[0]
pw = subprocess.check_output(
    ["powershell", "-NoProfile", "-Command", PS], text=True
).strip()
sql = Path(
    "supabase/migrations/20261104120000_checkout_amount_align_begin_dpd_batata.sql"
).read_text(encoding="utf-8")
conn = psycopg2.connect(
    host="aws-1-eu-west-1.pooler.supabase.com",
    port=5432,
    dbname="postgres",
    user="postgres.bpmpkzwnrbmuqnhgdscf",
    password=pw,
    sslmode="require",
)
conn.autocommit = True
cur = conn.cursor()
try:
    cur.execute(sql)
    print("APPLY_OK")
except Exception as e:
    print("APPLY_FAIL", e)
    raise
# smoke: quote shipping
cur.execute(
    """
  select public.batata_commerce_quote_shipping_cents(
    'Envio Transportadora (DPD)',
    '[{"product_id":"00000000-0000-0000-0000-000000000001"}]'::jsonb,
    '{"delivery_point_ref":"PUDO-X"}'::jsonb
  )
"""
)
print("quote_smoke", cur.fetchone())
