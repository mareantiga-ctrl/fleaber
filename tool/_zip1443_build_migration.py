"""Build surgical migration 144.3 from live begin_prod.sql + helpers."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
begin = (
    (ROOT / "tool/reports/144.3-checkout-align/begin_prod.sql")
    .read_text(encoding="utf-8")
    .replace("\r\n", "\n")
)
# pg_get_functiondef dump had blank line between every line
begin = re.sub(r"\n{2,}", "\n", begin)

old_sync = """  v_lines := v_sync->'lines';
  v_items_cents := coalesce((v_sync->>'items_cents')::int, v_items_cents);
  v_ship_cents := coalesce((v_sync->>'shipping_cents')::int, v_ship_cents);
  v_prot_cents := coalesce((v_sync->>'protection_fee_cents')::int, v_prot_cents);
  v_total_cents := coalesce(
    (v_sync->>'total_cents')::int,
    v_items_cents + v_ship_cents + v_prot_cents
  );
  -- E49: pagamento directo (off_platform) = sem Seguro Fleaber (contrato app B2)
  if v_rail = 'off_platform' then
    v_prot_cents := 0;
    v_total_cents := v_items_cents + v_ship_cents;
  end if;"""

new_sync = """  v_lines := v_sync->'lines';
  v_items_cents := coalesce((v_sync->>'items_cents')::int, v_items_cents);
  -- ZIP 144.3: portes DPD (peso/produto) — NÃO herdar flat 350¢ do sync legado
  begin
    v_ship_cents := public.batata_commerce_quote_shipping_cents(
      p_shipping_method,
      coalesce(p_lines, v_lines),
      coalesce(p_delivery, '{}'::jsonb)
    );
  exception when others then
    v_ship_cents := coalesce((v_sync->>'shipping_cents')::int, v_ship_cents);
  end;
  -- E49: pagamento directo (off_platform) = sem Seguro Fleaber (contrato app B2)
  if v_rail = 'off_platform' then
    v_prot_cents := 0;
  else
    v_prot_cents := public.batata_commerce_protection_fee_cents(
      v_items_cents, v_ship_cents
    );
  end if;
  v_total_cents := v_items_cents + v_ship_cents + v_prot_cents;"""

if old_sync not in begin:
    # show nearby for debug
    i = begin.find("v_ship_cents := coalesce((v_sync")
    raise SystemExit("sync block not found; nearby=" + repr(begin[i : i + 350]))

begin = begin.replace(old_sync, new_sync, 1)

idx = begin.find("set status = 'payment_processing'")
if idx < 0:
    raise SystemExit("payment_processing not found")
upd_start = begin.rfind("update public.commerce_checkout_attempts", 0, idx)
if upd_start < 0:
    raise SystemExit("update attempts not found")
seal = """  -- ZIP 144.3: selar peso + shipping_cents_charged (CPI/settle usam o mesmo selo)
  perform public.batata_commerce_seal_attempt_orders_shipping(v_attempt.id);
"""
begin = begin[:upd_start] + seal + begin[upd_start:]

# Clean helpers: only quote + seal + 4-arg revalidate (no 5-arg, no begin)
helpers_raw = (ROOT / "tool/reports/144.3-checkout-align/helpers.sql").read_text(
    encoding="utf-8"
)
# Cut helpers at first CREATE begin if any, and drop 5-arg revalidate section
cut = helpers_raw.find("CREATE OR REPLACE FUNCTION public.batata_commerce_checkout_begin")
if cut > 0:
    helpers_raw = helpers_raw[:cut]
# If helpers has 5-arg revalidate with p_delivery, keep only quote+seal then append clean 4-arg from file end
# Prefer: extract quote function + seal function only, then add revalidate from dedicated file
q0 = helpers_raw.find("create or replace function public.batata_commerce_quote_shipping_cents")
s0 = helpers_raw.find("create or replace function public.batata_commerce_seal_attempt_orders_shipping")
# find end of seal grants
s_end = helpers_raw.find(
    "to service_role, authenticated;",
    s0,
)
s_end = helpers_raw.find("\n", s_end) + 1 if s_end > 0 else len(helpers_raw)
helpers = (
    "-- ZIP 144.3 helpers\n"
    + helpers_raw[q0:s_end]
    + "\n"
    + (ROOT / "tool/reports/144.3-checkout-align/revalidate_4arg.sql").read_text(
        encoding="utf-8"
    )
)

out = (
    helpers
    + "\n\n-- Patched begin (from PROD + ZIP 144.3 deltas)\n"
    + begin
    + "\n\nnotify pgrst, 'reload schema';\n"
)
path = (
    ROOT
    / "supabase/migrations/20261104120000_checkout_amount_align_begin_dpd_batata.sql"
)
path.write_text(out, encoding="utf-8")
print("wrote", path, "bytes", len(out))
print("ok seal", "seal_attempt_orders_shipping" in begin)
print("ok quote", "quote_shipping_cents" in begin)
