import subprocess, psycopg2
PS = open("tool/run_zip144_2_stripe_e2e_prod.py", encoding="utf-8").read().split('PS_PW = r"""')[1].split('"""')[0]
pw = subprocess.check_output(["powershell","-NoProfile","-Command",PS], text=True).strip()
c=psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
c.autocommit=True
cur=c.cursor()
cur.execute("""select column_name from information_schema.columns where table_schema='public' and table_name='user_notifications' order by 1""")
print([r[0] for r in cur.fetchall()])
