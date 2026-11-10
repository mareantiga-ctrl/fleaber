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
cur.execute(
    """
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_commerce_checkout_revalidate'
"""
)
print("before", cur.fetchall())
# Drop 5-arg if exists
cur.execute(
    """
  drop function if exists public.batata_commerce_checkout_revalidate(
    jsonb, text, uuid, text, jsonb
  );
"""
)
# Ensure begin calls 4-arg with explicit null cast — already does
# Re-grant 4-arg
cur.execute(
    """
  revoke all on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text)
    from public;
  grant execute on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text)
    to anon, authenticated, service_role;
"""
)
cur.execute(
    """
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_commerce_checkout_revalidate'
"""
)
print("after", cur.fetchall())
# Fix begin call to use explicit null::uuid for 3rd arg to avoid ambiguity
cur.execute(
    """
  select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_commerce_checkout_begin'
"""
)
defn = cur.fetchone()[0]
if "batata_commerce_checkout_revalidate(\n    p_lines, p_shipping_method, null, p_guest_token\n  )" in defn.replace(
    "\r\n", "\n"
).replace("\n\n", "\n"):
    print("begin still uses null without cast — patching")
# Always patch begin revalidate call to null::uuid
import re

defn_n = defn.replace("\r\n", "\n")
defn_n = re.sub(r"\n{2,}", "\n", defn_n)
old = "public.batata_commerce_checkout_revalidate(\n    p_lines, p_shipping_method, null, p_guest_token\n  )"
new = "public.batata_commerce_checkout_revalidate(\n    p_lines, p_shipping_method, null::uuid, p_guest_token\n  )"
if old not in defn_n:
    # try single line
    old2 = "public.batata_commerce_checkout_revalidate(\n    p_lines, p_shipping_method, null, p_guest_token"
    if old2 in defn_n:
        defn_n = defn_n.replace(
            "p_lines, p_shipping_method, null, p_guest_token",
            "p_lines, p_shipping_method, null::uuid, p_guest_token",
            1,
        )
        print("patched via replace null")
    else:
        print("pattern not found; snippet:")
        i = defn_n.find("checkout_revalidate")
        print(repr(defn_n[i : i + 120]))
else:
    defn_n = defn_n.replace(old, new, 1)
    print("patched exact")

if not defn_n.rstrip().endswith(";"):
    defn_n = defn_n.rstrip() + ";\n"
cur.execute(defn_n)
print("begin_reapplied")
cur.execute("notify pgrst, 'reload schema'")
print("done")
