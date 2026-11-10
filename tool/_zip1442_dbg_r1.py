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
oid = "705d125d-e94b-4b1f-b388-82bf36adec47"
cur.execute(
    """
  select o.id::text, o.status, o.price_total, o.amount_paid_cents,
         o.shipping_cents_charged, o.shipping_method, o.stock_units_applied,
         o.stripe_refund_id, p.quantity, p.is_sold, p.list_on_marketplace
  from orders o join products p on p.id=o.product_id
  where o.id=%s::uuid
""",
    (oid,),
)
print("order", cur.fetchone())
cur.execute(
    """
  select event, left(coalesce(detail::text,''), 400)
  from stripe_checkout_events
  where order_id=%s::uuid
  order by created_at desc nulls last
  limit 10
""",
    (oid,),
)
for r in cur.fetchall():
    print("evt", r[0], r[1])
