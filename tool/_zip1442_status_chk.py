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
cur = conn.cursor()
cur.execute(
    """
  select pg_get_constraintdef(c.oid)
  from pg_constraint c
  where c.conrelid = 'public.orders'::regclass
    and c.contype = 'c'
    and pg_get_constraintdef(c.oid) ilike '%status%'
"""
)
for r in cur.fetchall():
    print(r[0][:400])
cur.execute("select distinct status from public.orders order by 1")
print("statuses", [x[0] for x in cur.fetchall()])
