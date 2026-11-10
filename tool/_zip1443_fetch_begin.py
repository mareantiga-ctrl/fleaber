import subprocess
from pathlib import Path

PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split(
    'PS_PW = r"""'
)[1].split('"""')[0]
pw = subprocess.check_output(
    ["powershell", "-NoProfile", "-Command", PS], text=True
).strip()
import psycopg2

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
cur.execute(
    """
  select pg_get_functiondef(p.oid)
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'batata_commerce_checkout_begin'
"""
)
defs = cur.fetchall()
out = Path("tool/reports/144.3-checkout-align/begin_prod.sql")
out.parent.mkdir(parents=True, exist_ok=True)
text = "\n\n-- OVERLOAD --\n\n".join(d[0] for d in defs)
out.write_text(text, encoding="utf-8")
print("wrote", out, "bytes", len(text), "overloads", len(defs))
# also revalidate signatures
cur.execute(
    """
  select pg_get_function_identity_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_commerce_checkout_revalidate'
"""
)
print("revalidate args", cur.fetchall())
