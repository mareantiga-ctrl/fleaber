"""Hotfix batata_bundle_checkout_begin — não tocar money cols imutáveis."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "z", ROOT / "tool/run_zip144_2_stripe_e2e_prod.py"
)
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
z.load_env()
conn, _ = z.pg()
conn.autocommit = True
cur = conn.cursor()

# Extract function from migration and replace the orders update block
sql = (ROOT / "supabase/migrations/20261104150000_bundle_quote_before_pay_batata.sql").read_text(
    encoding="utf-8"
)
# We'll replace just the function via a surgically patched definition
cur.execute(
    r"""
create or replace function public.batata_bundle_checkout_begin(
  p_bundle_id uuid,
  p_client_idempotency_key text default null,
  p_delivery jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_b public.product_bundles%rowtype;
  v_val jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_pid uuid;
  v_qty int;
  v_delivery jsonb;
  v_begin jsonb;
  v_attempt_id uuid;
  v_total int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  if not public.batata_flag_enabled('bundle_quote_before_pay_v1') then
    return jsonb_build_object('ok', false, 'error', 'flag_disabled');
  end if;

  perform public.batata_bundle_touch_expiry(p_bundle_id);
  select * into v_b from public.product_bundles where id = p_bundle_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_b.buyer_id is distinct from v_uid then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if v_b.status is distinct from 'awaiting_payment' then
    return jsonb_build_object('ok', false, 'error', 'not_awaiting_payment', 'status', v_b.status);
  end if;

  v_val := public.batata_bundle_validate_quote(p_bundle_id);
  if coalesce((v_val->>'ok')::boolean, false) is not true then
    perform public.batata_bundle_invalidate_stale_quote(p_bundle_id);
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_val->>'error', 'quote_invalid'),
      'message', coalesce(v_val->>'message', 'Cotação inválida'),
      'validation', v_val
    );
  end if;

  for v_pid, v_qty in
    select x.pid, count(*)::int from unnest(v_b.product_ids) x(pid) group by x.pid
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', v_pid, 'quantity', v_qty
    ));
  end loop;

  v_delivery := coalesce(p_delivery, '{}'::jsonb) || jsonb_build_object(
    'shipping_modality', v_b.quote_shipping_modality,
    'shipping_weight_band', v_b.quote_weight_band,
    'shipping_weight_kg', v_b.quote_weight_kg,
    'use_delivery_weight', true,
    'seller_confirmed_weight', true,
    'shipping_cents_override', v_b.shipping_cents,
    'delivery_point_ref', coalesce(
      nullif(trim(coalesce(p_delivery->>'delivery_point_ref', '')), ''),
      v_b.quote_delivery_point_ref
    ),
    'point_ref', coalesce(
      nullif(trim(coalesce(p_delivery->>'point_ref', '')), ''),
      v_b.quote_delivery_point_ref
    )
  );

  v_begin := public.batata_commerce_checkout_begin(
    v_lines,
    coalesce(v_b.quote_shipping_method, 'Envio Transportadora (DPD)'),
    'stripe',
    v_delivery,
    null,
    coalesce(p_client_idempotency_key, 'bundle:' || p_bundle_id::text),
    true,
    null
  );
  if coalesce((v_begin->>'ok')::boolean, false) is not true then
    return v_begin;
  end if;

  v_attempt_id := nullif(v_begin->>'checkout_attempt_id', '')::uuid;
  v_total := coalesce((v_begin->>'total_cents')::int, 0);

  if v_attempt_id is not null
     and v_b.grand_total_cents is not null
     and v_total is distinct from v_b.grand_total_cents then
    update public.commerce_checkout_attempts set
      items_cents = v_b.articles_cents,
      shipping_cents = v_b.shipping_cents,
      protection_fee_cents = v_b.protection_cents,
      total_cents = v_b.grand_total_cents
    where id = v_attempt_id;
    perform public.batata_commerce_seal_attempt_orders_shipping(v_attempt_id);
    v_total := v_b.grand_total_cents;
  end if;

  -- Não tocar shipping_cents_charged / price_total (guard money immutable).
  -- O selo do attempt já grava portes; aqui só metadados do conjunto.
  if v_attempt_id is not null then
    update public.orders o set
      bundle_id = p_bundle_id,
      payment_method = 'Compra em conjunto (cotação confirmada)',
      shipping_weight_kg = coalesce(o.shipping_weight_kg, v_b.quote_weight_kg),
      shipping_weight_band = coalesce(o.shipping_weight_band, v_b.quote_weight_band),
      shipping_modality = coalesce(o.shipping_modality, v_b.quote_shipping_modality)
    where o.checkout_attempt_id = v_attempt_id;

    update public.product_bundles set
      checkout_attempt_id = v_attempt_id
    where id = p_bundle_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'bundle_id', p_bundle_id,
    'checkout_attempt_id', v_attempt_id,
    'articles_cents', v_b.articles_cents,
    'shipping_cents', v_b.shipping_cents,
    'protection_cents', v_b.protection_cents,
    'total_cents', coalesce(v_b.grand_total_cents, v_total),
    'order_ids', v_begin->'order_ids',
    'begin', v_begin
  );
end;
$$;
"""
)
print("BEGIN_FIXED")
