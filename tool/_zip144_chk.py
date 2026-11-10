import subprocess, psycopg2
PS = open(r"tool/_zip144_schema_nn.py", encoding="utf-8").read()
# extract via rerun style
import re
ps = re.search(r'PS = r"""(.*?)"""', open(r"tool/_zip144_schema_nn.py",encoding="utf-8").read(), re.S).group(1)
pw = subprocess.check_output(["powershell","-NoProfile","-Command", ps], text=True).strip()
conn = psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
cur=conn.cursor()
cur.execute("""
select pg_get_constraintdef(oid) from pg_constraint
where conname='orders_commerce_channel_chk'
""")
print(cur.fetchone())
cur.execute("select distinct commerce_channel from public.orders where commerce_channel is not null limit 20")
print(cur.fetchall())
cur.execute("""
select pg_get_constraintdef(oid) from pg_constraint
where conrelid='public.orders'::regclass and contype='c'
and pg_get_constraintdef(oid) ilike '%shipping%'
limit 20
""")
for r in cur.fetchall(): print(r[0][:200])
