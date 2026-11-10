import subprocess, re, psycopg2
ps = re.search(r'PS = r"""(.*?)"""', open(r"tool/apply_zip144_notify_allowlist_prod.py",encoding="utf-8").read(), re.S).group(1)
pw = subprocess.check_output(["powershell","-NoProfile","-Command", ps], text=True).strip()
conn = psycopg2.connect(host="aws-1-eu-west-1.pooler.supabase.com",port=5432,dbname="postgres",user="postgres.bpmpkzwnrbmuqnhgdscf",password=pw,sslmode="require")
conn.autocommit=True
cur=conn.cursor()
cur.execute("""
  delete from public.user_notifications
  where kind in ('shipping_delta_requested','shipping_delta_paid','shipping_delta_expired_cancelled','ship_deadline_auto_cancelled')
    and created_at > now() - interval '2 hours'
    and dedupe_key like 'ship_delta:%%'
""")
print('deleted_notifs', cur.rowcount)
cur.execute("""
  select key, enabled from public.fleaber_feature_flags
  where key like 'order_%%' order by 1
""")
print('flags', cur.fetchall())
cur.execute("select count(*) from cron.job where command ilike '%%shipping%%deadline%%' or jobname ilike '%%shipping%%deadline%%'")
print('cron', cur.fetchone())
# leftover teste products/orders
cur.execute("select count(*) from public.products where title like 'TESTE-ZIP143%%'")
print('leftover_products', cur.fetchone())
cur.execute("select count(*) from public.orders where delivery_point_ref='PUDO-TESTE-ZIP143'")
print('leftover_orders', cur.fetchone())
