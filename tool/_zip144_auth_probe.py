import subprocess, re, json, psycopg2
from psycopg2.extras import RealDictCursor
ps = re.search(r'PS = r"""(.*?)"""', open(r"tool/_zip144_schema_nn.py",encoding="utf-8").read(), re.S).group(1)
pw = subprocess.check_output(["powershell","-NoProfile","-Command", ps], text=True).strip()
conn = psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
conn.autocommit=True
cur=conn.cursor(cursor_factory=RealDictCursor)
cur.execute("select pg_get_functiondef(oid) from pg_proc where proname='uid' and pronamespace=(select oid from pg_namespace where nspname='auth')")
print('AUTH.UID:', (cur.fetchone() or {}).get('pg_get_functiondef','')[:800])
cur.execute("""
select column_name, data_type from information_schema.columns
where table_schema='public' and table_name='user_notifications' order by ordinal_position
""")
print('NOTIF COLS:', [r['column_name'] for r in cur.fetchall()])
# try different jwt settings
uid='ee7dbdb2-d2e1-4538-800f-7546d72f064a'
for stmt in [
  f"select set_config('request.jwt.claim.sub','{uid}',true)",
  f"select set_config('request.jwt.claims','{{\"sub\":\"{uid}\",\"role\":\"authenticated\"}}',true)",
]:
  cur.execute(stmt)
cur.execute("select auth.uid() as uid, current_setting('request.jwt.claim.sub', true) as sub, current_setting('request.jwt.claims', true) as claims")
print('after set_config:', cur.fetchone())
# try GUC request.jwt.claim.sub via SET
cur.execute(f"SET request.jwt.claim.sub = '{uid}'")
cur.execute("select auth.uid() as uid")
print('after SET:', cur.fetchone())
# batata_is_admin
cur.execute("select pg_get_functiondef(oid) from pg_proc where proname='batata_is_admin' limit 1")
row=cur.fetchone()
print('ADMIN:', (row or {}).get('pg_get_functiondef','')[:600])
