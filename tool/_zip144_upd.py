import subprocess, re, psycopg2
from psycopg2.extras import RealDictCursor
ps = re.search(r'PS = r"""(.*?)"""', open(r"tool/_zip144_schema_nn.py",encoding="utf-8").read(), re.S).group(1)
pw = subprocess.check_output(["powershell","-NoProfile","-Command", ps], text=True).strip()
conn = psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
cur=conn.cursor(cursor_factory=RealDictCursor)
cur.execute("""
select column_name from information_schema.columns
where table_schema='public' and table_name='orders'
and column_name ~* 'updat|modif|touch|changed'
order by 1
""")
print('time cols', cur.fetchall())
cur.execute("""
select column_name from information_schema.columns
where table_schema='public' and table_name='order_shipping_adjustments'
order by ordinal_position
""")
print('adj cols', [r['column_name'] for r in cur.fetchall()])
