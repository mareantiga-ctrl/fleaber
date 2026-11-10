import subprocess, psycopg2, json
PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split("PS_PW = r\"\"\"")[1].split("\"\"\"")[0]
pw = subprocess.check_output(["powershell","-NoProfile","-Command", PS], text=True).strip()
c = psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
c.autocommit=True
cur=c.cursor()
cur.execute("select key, enabled from fleaber_feature_flags where key like %s order by 1", ("dpd%",))
print("flags", cur.fetchall())
cur.execute("select modality, weight_band, price_eur from dpd_shipping_rates where active order by 1,2")
print("rates", cur.fetchall())
cur.execute("""
select pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='batata_commerce_shipping_cents'
""")
print(cur.fetchone()[0][:800])
