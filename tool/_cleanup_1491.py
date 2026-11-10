import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
conn, Cur = z.pg()
cur = conn.cursor(cursor_factory=Cur)
cur.execute(
    """
  update public.order_shipping_adjustments a
  set status='cancelled'
  from public.orders o, public.products p
  where a.order_id=o.id and o.product_id=p.id
    and p.title like 'TESTE-ZIP1491%%'
    and a.status='pending'
"""
)
print("cancelled_adj", cur.rowcount)
z.flags_off(cur)
cur.execute(
    """
  update public.fleaber_feature_flags set enabled=true
  where key in ('bundle_quote_before_pay_v1','bundle_awaiting_payment_deadline_enabled')
"""
)
cur.execute(
    """
  update public.fleaber_feature_flags set enabled=false
  where key in ('order_weight_confirm_enabled','order_shipping_delta_enabled')
"""
)
print("flags_ok")
