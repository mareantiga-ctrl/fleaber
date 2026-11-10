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
tag = "TESTE-ZIP1442%"
cur.execute(
    """
  delete from public.order_shipping_adjustments a
  using public.orders o, public.products p
  where a.order_id=o.id and o.product_id=p.id and p.title like %s
""",
    (tag,),
)
print("adj", cur.rowcount)
cur.execute(
    """
  delete from public.orders o using public.products p
  where o.product_id=p.id and p.title like %s
""",
    (tag,),
)
print("orders", cur.rowcount)
cur.execute(
    """
  update public.chats c set product_id = null
  from public.products p
  where c.product_id = p.id and p.title like %s
""",
    (tag,),
)
print("chats_unlinked", cur.rowcount)
cur.execute("delete from public.products where title like %s", (tag,))
print("products", cur.rowcount)
# known orphan
cur.execute(
    "delete from public.orders where id=%s",
    ("49c50f28-8d7a-4b5a-9d34-422c622964f7",),
)
print("orphan", cur.rowcount)
