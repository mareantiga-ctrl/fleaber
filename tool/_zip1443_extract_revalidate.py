"""Write clean 4-arg revalidate that uses quote_shipping_cents."""
from pathlib import Path

# Use live revalidate and only replace shipping lines
import subprocess
import psycopg2

PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split(
    'PS_PW = r"""'
)[1].split('"""')[0]
pw = subprocess.check_output(
    ["powershell", "-NoProfile", "-Command", PS], text=True
).strip()
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
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_commerce_checkout_revalidate'
"""
)
raw = cur.fetchone()[0].replace("\r\n", "\n")
import re

raw = re.sub(r"\n{2,}", "\n", raw)
old = """  begin
    v_ship_cents := public.batata_commerce_shipping_cents(p_shipping_method);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'invalid_shipping_method');
  end;"""
new = """  begin
    v_ship_cents := public.batata_commerce_quote_shipping_cents(
      p_shipping_method, p_lines, '{}'::jsonb
    );
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_shipping_method',
      'message', sqlerrm
    );
  end;"""
if old not in raw:
    raise SystemExit("revalidate shipping block missing: " + repr(raw[raw.find("v_ship") : raw.find("v_ship") + 200]))
raw = raw.replace(old, new, 1)
Path("tool/reports/144.3-checkout-align/revalidate_4arg.sql").write_text(
    raw + "\n", encoding="utf-8"
)
print("wrote revalidate_4arg.sql", len(raw))
