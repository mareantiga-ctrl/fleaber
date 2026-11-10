"""Verify PROD bundle quote-before-pay readiness."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tool/reports/151-bundle-checkout-final"
OUT.mkdir(parents=True, exist_ok=True)

spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
conn, Cur = z.pg()
cur = conn.cursor(cursor_factory=Cur)

report: dict = {"ok": True, "checks": []}


def check(name: str, ok: bool, detail):
    report["checks"].append({"id": name, "ok": ok, "detail": detail})
    if not ok:
        report["ok"] = False
    print(("PASS" if ok else "FAIL"), name, detail)


# flags
cur.execute(
    """
  select key, enabled from public.fleaber_feature_flags
  where key in (
    'bundle_quote_before_pay_v1',
    'bundle_awaiting_payment_deadline_enabled',
    'order_shipping_delta_enabled',
    'order_weight_confirm_enabled'
  ) order by 1
"""
)
flags = {r["key"]: r["enabled"] for r in cur.fetchall()}
check(
    "flags",
    flags.get("bundle_quote_before_pay_v1") is True
    and flags.get("bundle_awaiting_payment_deadline_enabled") is True
    and flags.get("order_shipping_delta_enabled") is False
    and flags.get("order_weight_confirm_enabled") is False,
    flags,
)

# functions
need = [
    "batata_bundle_seller_confirm_quote",
    "batata_bundle_checkout_begin",
    "batata_bundle_touch_expiry",
    "batata_bundle_abandon",
    "batata_bundle_validate_quote",
    "batata_bundle_invalidate_stale_quote",
    "batata_bundle_mark_purchased",
]
cur.execute(
    """
  select proname from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and proname = any(%s)
""",
    (need,),
)
have = {r["proname"] for r in cur.fetchall()}
check("rpcs", set(need) <= have, sorted(have))

# status check allows awaiting_payment
cur.execute(
    """
  select pg_get_constraintdef(oid) as d
  from pg_constraint
  where conname='product_bundles_status_check'
"""
)
d = cur.fetchone()["d"]
check("status_check", "awaiting_payment" in d, d)

# confirm_quote uses 48h — probe source
cur.execute(
    """
  select pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='batata_bundle_seller_confirm_quote'
  limit 1
"""
)
defn = list(cur.fetchone().values())[0]
check(
    "confirm_quote_48h",
    "interval '48 hours'" in defn and "interval '24 hours'" not in defn,
    {
        "has_48": "interval '48 hours'" in defn,
        "has_24": "interval '24 hours'" in defn,
    },
)

# columns
cur.execute(
    """
  select column_name from information_schema.columns
  where table_name='product_bundles'
    and column_name in (
      'pay_expires_at','seller_confirm_expires_at','grand_total_cents','rule_version'
    )
"""
)
cols = {r["column_name"] for r in cur.fetchall()}
check(
    "columns",
    cols
    >= {
        "pay_expires_at",
        "seller_confirm_expires_at",
        "grand_total_cents",
        "rule_version",
    },
    sorted(cols),
)

(OUT / "prod_backend_verify.json").write_text(
    json.dumps(report, indent=2, default=str), encoding="utf-8"
)
print("WROTE", OUT / "prod_backend_verify.json", "ok=", report["ok"])
raise SystemExit(0 if report["ok"] else 1)
