import importlib.util
import json
import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()

seller_id = os.environ["PROD_TEST_SELLER_ID"]
buyer_id = os.environ["PROD_TEST_BUYER_H1132_ID"]
buyer = z.auth_password(
    os.environ["PROD_TEST_BUYER_H1132_EMAIL"],
    os.environ["PROD_TEST_BUYER_H1132_PASSWORD"],
)
seller = z.auth_password(
    os.environ["PROD_TEST_SELLER_EMAIL"],
    os.environ["PROD_TEST_SELLER_PASSWORD"],
)
conn, Cur = z.pg()
cur = conn.cursor(cursor_factory=Cur)
TAG = "TESTE-ZIP149DBG"

cur.execute("delete from public.orders o using public.products p where o.product_id=p.id and p.title like %s", (f"{TAG}%",))
cur.execute("delete from public.product_bundles b using public.products p where p.title like %s and p.id = any(b.product_ids)", (f"{TAG}%",))
cur.execute("delete from public.products where title like %s", (f"{TAG}%",))

pids = []
for title, price in [(f"{TAG} A", 5.0), (f"{TAG} B", 3.5)]:
    pid = str(uuid.uuid4())
    cur.execute(
        """
      insert into public.products (
        id, title, price, seller_id, quantity, is_draft, is_sold,
        shipping_weight_kg, shipping_weight_band, list_on_marketplace, description
      ) values (%s::uuid,%s,%s,%s::uuid,3,false,false,1.5,'0_3',true,%s)
    """,
        (pid, title, price, seller_id, TAG),
    )
    pids.append(pid)

code, rows = z.http(
    "POST",
    f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/product_bundles",
    {
        "apikey": os.environ["SUPABASE_ANON_KEY"],
        "Authorization": f"Bearer {buyer['access_token']}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    },
    {"seller_id": seller_id, "buyer_id": buyer_id, "product_ids": pids, "status": "pending"},
)
bid = rows[0]["id"]
print("bundle", bid)

code, quote = z.http(
    "POST",
    f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/rpc/batata_bundle_seller_confirm_quote",
    {
        "apikey": os.environ["SUPABASE_ANON_KEY"],
        "Authorization": f"Bearer {seller['access_token']}",
        "Content-Type": "application/json",
    },
    {
        "p_bundle_id": bid,
        "p_weight_kg": 2.0,
        "p_weight_band": "0_3",
        "p_shipping_modality": "shop_to_shop",
        "p_shipping_method": "Envio Transportadora (DPD)",
        "p_delivery_point_ref": "PUDO-DBG",
    },
)
print("quote", code, quote)

# Call begin as SQL with set local role to see exact error
cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (buyer_id,))
cur.execute("select set_config('request.jwt.claim.role', 'authenticated', true)")
cur.execute("select set_config('role', 'authenticated', true)")
# auth.uid() needs jwt - use supabase pattern
try:
    cur.execute("begin")
    cur.execute("set local role authenticated")
    cur.execute(
        "select auth.uid()"
    )
    print("uid_before", cur.fetchone())
except Exception as e:
    print("role_err", e)
    conn.rollback()

# Direct commerce begin without bundle wrapper
cur.execute(
    """
  select public.batata_commerce_checkout_begin(
    %s::jsonb,
    'Envio Transportadora (DPD)',
    'stripe',
    %s::jsonb,
    null,
    %s,
    true,
    null
  )
""",
    (
        json.dumps([{"product_id": pids[0], "quantity": 1}, {"product_id": pids[1], "quantity": 1}]),
        json.dumps({
            "shipping_modality": "shop_to_shop",
            "shipping_weight_band": "0_3",
            "shipping_weight_kg": 2.0,
            "use_delivery_weight": True,
            "shipping_cents_override": 299,
            "delivery_point_ref": "PUDO-DBG",
            "point_ref": "PUDO-DBG",
        }),
        f"dbg-{uuid.uuid4().hex[:8]}",
    ),
)
# This runs as postgres — should work
row = cur.fetchone()
print("direct_begin_as_postgres", row[0] if not hasattr(row, "keys") else list(row.values())[0])

code, begin = z.http(
    "POST",
    f"{os.environ['SUPABASE_URL'].rstrip('/')}/rest/v1/rpc/batata_bundle_checkout_begin",
    {
        "apikey": os.environ["SUPABASE_ANON_KEY"],
        "Authorization": f"Bearer {buyer['access_token']}",
        "Content-Type": "application/json",
    },
    {
        "p_bundle_id": bid,
        "p_client_idempotency_key": f"dbg-{uuid.uuid4().hex[:8]}",
        "p_delivery": {"delivery_point_ref": "PUDO-DBG", "point_ref": "PUDO-DBG"},
    },
)
print("bundle_begin", code, begin)
