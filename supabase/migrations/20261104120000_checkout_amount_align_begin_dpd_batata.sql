-- ZIP 144.3 helpers
create or replace function public.batata_commerce_quote_shipping_cents(
  p_shipping_method text,
  p_lines jsonb default null,
  p_delivery jsonb default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m text := lower(trim(coalesce(p_shipping_method, '')));
  v_hand boolean := false;
  v_carrier boolean := false;
  v_modality text;
  v_kg numeric;
  v_band text;
  v_quote jsonb;
  v_cents int;
  v_ref text;
begin
  if m = '' then
    raise exception 'invalid_shipping_method' using errcode = '22023';
  end if;

  v_hand := m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)'
  ) or m like '%mão%' or m like '%mao%';

  -- «Envio Transportadora» / DPD não é mão mesmo se substring coincidir
  if m like '%transportadora%' or m like '%dpd%' or m like '%carrier%'
     or m like '%3.50%' or m like '%3,50%' then
    v_hand := false;
    v_carrier := true;
  end if;

  if v_hand and not v_carrier then
    -- Pickup DPD com ponto: tratar como carrier S2S
    v_ref := nullif(trim(coalesce(p_delivery->>'delivery_point_ref', '')), '');
    if m = 'pickup' and v_ref is not null then
      v_carrier := true;
    else
      return 0;
    end if;
  end if;

  if not v_carrier and not (
    m in ('carrier', 'transportadora', 'ctt', 'correios', 'dpd', 'envio dpd')
    or m like '%transportadora%' or m like '%carrier%' or m like '%dpd%'
  ) then
    -- fallback legado exact allowlist
    return public.batata_commerce_shipping_cents(p_shipping_method);
  end if;

  v_ref := nullif(trim(coalesce(p_delivery->>'delivery_point_ref', '')), '');
  v_modality := lower(trim(coalesce(
    nullif(p_delivery->>'shipping_modality', ''),
    nullif(p_delivery->>'dpd_service', ''),
    case when v_ref is not null then 'shop_to_shop' else 'shop_to_shop' end
  )));
  if v_modality not in ('shop_to_shop', 'shop_to_home') then
    v_modality := case when v_ref is not null then 'shop_to_shop' else 'shop_to_shop' end;
  end if;

  -- Peso: máximo dos produtos nas lines (ou band explícita no delivery)
  v_band := nullif(trim(coalesce(p_delivery->>'shipping_weight_band', '')), '');
  select max(p.shipping_weight_kg)
    into v_kg
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
  join public.products p
    on p.id = nullif(trim(coalesce(e->>'product_id', '')), '')::uuid
  where p.shipping_weight_kg is not null;

  if v_kg is null then
    v_kg := nullif(trim(coalesce(p_delivery->>'shipping_weight_kg', '')), '')::numeric;
  end if;

  -- Sem peso: se rates live, exige peso; senão legado 350 via dpd quote (legacy branch)
  v_quote := public.batata_dpd_quote_shipping(v_modality, v_kg, v_band, false);
  if coalesce((v_quote->>'ok')::boolean, false) is not true then
    -- Fail-open legado só se weight_required e flag rates off já tratado em dpd_quote;
    -- se weight_required com rates live → erro claro
    if coalesce(v_quote->>'error', '') = 'weight_required' then
      -- Sem peso no produto: fallback 0_3 (carril Hub/anúncio sem peso = escalão mínimo)
      v_quote := public.batata_dpd_quote_shipping(v_modality, 2.0, '0_3', false);
    end if;
  end if;

  if coalesce((v_quote->>'ok')::boolean, false) is not true then
    raise exception '%', coalesce(v_quote->>'message', v_quote->>'error', 'invalid_shipping')
      using errcode = '22023';
  end if;

  v_cents := round((coalesce(v_quote->>'price_eur', '0'))::numeric * 100)::int;
  if v_cents < 0 then
    raise exception 'invalid_shipping_amount' using errcode = '22023';
  end if;
  return v_cents;
end;
$$;

revoke all on function public.batata_commerce_quote_shipping_cents(text, jsonb, jsonb)
  from public, anon;
grant execute on function public.batata_commerce_quote_shipping_cents(text, jsonb, jsonb)
  to authenticated, service_role, anon;

comment on function public.batata_commerce_quote_shipping_cents(text, jsonb, jsonb) is
  'ZIP 144.3: portes begin/revalidate alinhados a batata_dpd_quote_shipping (Célia/CPI).';

-- Revalidate: usar quote DPD + lines (peso)
create or replace function public.batata_commerce_checkout_revalidate(
  p_lines jsonb,
  p_shipping_method text,
  p_seller_id uuid default null,
  p_guest_token text default null,
  p_delivery jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor jsonb;
  v_buyer uuid;
  v_guest uuid;
  v_mode text;
  v_line jsonb;
  v_avail jsonb := '[]'::jsonb;
  v_unavail jsonb := '[]'::jsonb;
  v_items_cents int := 0;
  v_ship_cents int;
  v_prot_cents int;
  v_total_cents int;
  v_seller uuid := p_seller_id;
  v_product_id uuid;
  v_live_item_id uuid;
  v_req_id uuid;
  v_avail_req uuid;
  v_qty int;
  v_unit_cents int;
  v_line_cents int;
  v_check jsonb;
  v_price numeric;
  v_bag_changed boolean := false;
  v_idx int := 0;
  v_pseller uuid;
begin
  v_actor := public.batata_commerce_resolve_checkout_actor(p_guest_token);
  if coalesce((v_actor->>'ok')::boolean, false) is not true then
    return v_actor;
  end if;
  v_mode := v_actor->>'mode';
  v_buyer := nullif(v_actor->>'buyer_id', '')::uuid;
  v_guest := nullif(v_actor->>'guest_session_id', '')::uuid;

  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) < 1 then
    return jsonb_build_object('ok', false, 'error', 'empty_lines');
  end if;

  begin
    v_ship_cents := public.batata_commerce_quote_shipping_cents(
      p_shipping_method, p_lines, coalesce(p_delivery, '{}'::jsonb)
    );
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_shipping_method',
      'message', sqlerrm
    );
  end;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_idx := v_idx + 1;
    v_product_id := nullif(trim(coalesce(v_line->>'product_id', '')), '')::uuid;
    v_live_item_id := nullif(trim(coalesce(v_line->>'live_item_id', '')), '')::uuid;
    v_req_id := nullif(trim(coalesce(v_line->>'reservation_request_id', '')), '')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);

    if v_req_id is not null then
      if not public.batata_commerce_reservation_usable_by_actor(
           v_req_id, v_buyer, v_guest
         ) then
        return jsonb_build_object(
          'ok', false,
          'error', 'reservation_not_authorized',
          'reservation_request_id', v_req_id,
          'message', 'reservation_id_alone_does_not_authorize_checkout'
        );
      end if;
    end if;

    if v_product_id is null and v_live_item_id is not null then
      select coalesce(product_id, checkout_product_id) into v_product_id
      from public.live_items where id = v_live_item_id;
    end if;

    if v_product_id is null then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1, 'reason', 'missing_product',
        'reservation_request_id', v_req_id
      ));
      continue;
    end if;

    select seller_id into v_pseller from public.products where id = v_product_id;
    if v_seller is null then
      v_seller := v_pseller;
    elsif v_pseller is distinct from v_seller then
      return jsonb_build_object('ok', false, 'error', 'multi_seller_bag');
    end if;

    select price into v_price from public.products where id = v_product_id;
    if (v_price is null or v_price <= 0) and v_live_item_id is not null then
      select price into v_price from public.live_items where id = v_live_item_id;
    end if;
    if v_price is null or v_price <= 0 then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1, 'product_id', v_product_id, 'reason', 'missing_price'
      ));
      continue;
    end if;

    v_unit_cents := round(v_price * 100)::int;
    v_line_cents := v_unit_cents * v_qty;
    v_avail_req := case when v_mode = 'guest' then null else v_req_id end;

    v_check := public.batata_commerce_line_availability(
      v_product_id, v_qty, v_buyer, v_avail_req, null
    );

    if coalesce((v_check->>'available')::boolean, false) then
      v_items_cents := v_items_cents + v_line_cents;
      v_avail := v_avail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'unit_cents', v_unit_cents,
        'line_cents', v_line_cents,
        'guaranteed', coalesce((v_check->>'guaranteed')::boolean, false) and v_mode = 'authenticated'
      ));
    else
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'reason', coalesce(v_check->>'reason', 'unavailable')
      ));
    end if;
  end loop;

  if jsonb_array_length(v_avail) = 0 then
    return jsonb_build_object(
      'ok', true,
      'bag_changed', true,
      'all_unavailable', true,
      'mode', v_mode,
      'available_lines', v_avail,
      'unavailable_lines', v_unavail,
      'seller_id', v_seller,
      'quote', jsonb_build_object(
        'items_cents', 0, 'shipping_cents', 0,
        'protection_fee_cents', 0, 'total_cents', 0
      )
    );
  end if;

  v_prot_cents := public.batata_commerce_protection_fee_cents(v_items_cents, v_ship_cents);
  v_total_cents := v_items_cents + v_ship_cents + v_prot_cents;

  return jsonb_build_object(
    'ok', true,
    'bag_changed', v_bag_changed,
    'all_unavailable', false,
    'mode', v_mode,
    'available_lines', v_avail,
    'unavailable_lines', v_unavail,
    'seller_id', v_seller,
    'shipping_method', p_shipping_method,
    'quote', jsonb_build_object(
      'items_cents', v_items_cents,
      'shipping_cents', v_ship_cents,
      'protection_fee_cents', v_prot_cents,
      'total_cents', v_total_cents
    )
  );
end;
$$;

-- Compat: assinatura antiga 4 args continua a funcionar (p_delivery null)
-- Drop+recreate grants for both overloads if needed
revoke all on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text) from public;
grant execute on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text)
  to anon, authenticated, service_role;
revoke all on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text, jsonb)
  to anon, authenticated, service_role;

-- Helper: selar peso + portes cobrados nas orders do attempt (pós-insert begin)
create or replace function public.batata_commerce_seal_attempt_orders_shipping(
  p_attempt_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_att record;
  v_ship int;
  v_kg numeric;
  v_band text;
  v_mod text;
  v_quote jsonb;
begin
  select * into v_att
  from public.commerce_checkout_attempts
  where id = p_attempt_id;
  if not found then
    return;
  end if;

  v_ship := coalesce(v_att.shipping_cents, 0);
  v_mod := case
    when nullif(trim(coalesce(v_att.delivery_point_ref, '')), '') is not null
      then 'shop_to_shop'
    else 'shop_to_shop'
  end;

  -- Peso: max dos produtos das orders do attempt
  select max(p.shipping_weight_kg),
         max(p.shipping_weight_band)
    into v_kg, v_band
  from public.orders o
  join public.products p on p.id = o.product_id
  where o.checkout_attempt_id = p_attempt_id;

  if v_kg is null then
    v_kg := 2.0;
  end if;
  if v_band is null or v_band not in ('0_3', '3_6', '6_10') then
    v_band := public.batata_dpd_weight_band(v_kg);
  end if;

  update public.orders o
  set
    shipping_cents_charged = v_ship,
    shipping_weight_kg = coalesce(o.shipping_weight_kg, v_kg),
    shipping_weight_charged_kg = coalesce(o.shipping_weight_charged_kg, v_kg),
    shipping_weight_band = coalesce(o.shipping_weight_band, v_band),
    shipping_weight_charged_band = coalesce(o.shipping_weight_charged_band, v_band),
    shipping_modality = coalesce(o.shipping_modality, v_mod),
    dpd_service = coalesce(o.dpd_service, v_mod)
  where o.checkout_attempt_id = p_attempt_id;
end;
$$;

revoke all on function public.batata_commerce_seal_attempt_orders_shipping(uuid)
  from public, anon;
grant execute on function public.batata_commerce_seal_attempt_orders_shipping(uuid)
  to service_role, authenticated;

CREATE OR REPLACE FUNCTION public.batata_commerce_checkout_revalidate(p_lines jsonb, p_shipping_method text, p_seller_id uuid DEFAULT NULL::uuid, p_guest_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_actor jsonb;
  v_buyer uuid;
  v_guest uuid;
  v_mode text;
  v_line jsonb;
  v_avail jsonb := '[]'::jsonb;
  v_unavail jsonb := '[]'::jsonb;
  v_items_cents int := 0;
  v_ship_cents int;
  v_prot_cents int;
  v_total_cents int;
  v_seller uuid := p_seller_id;
  v_product_id uuid;
  v_live_item_id uuid;
  v_req_id uuid;
  v_avail_req uuid;
  v_qty int;
  v_unit_cents int;
  v_line_cents int;
  v_check jsonb;
  v_price numeric;
  v_bag_changed boolean := false;
  v_idx int := 0;
  v_pseller uuid;
begin
  v_actor := public.batata_commerce_resolve_checkout_actor(p_guest_token);
  if coalesce((v_actor->>'ok')::boolean, false) is not true then
    return v_actor;
  end if;
  v_mode := v_actor->>'mode';
  v_buyer := nullif(v_actor->>'buyer_id', '')::uuid;
  v_guest := nullif(v_actor->>'guest_session_id', '')::uuid;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) < 1 then
    return jsonb_build_object('ok', false, 'error', 'empty_lines');
  end if;
  begin
    v_ship_cents := public.batata_commerce_quote_shipping_cents(
      p_shipping_method, p_lines, '{}'::jsonb
    );
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_shipping_method',
      'message', sqlerrm
    );
  end;
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_idx := v_idx + 1;
    v_product_id := nullif(trim(coalesce(v_line->>'product_id', '')), '')::uuid;
    v_live_item_id := nullif(trim(coalesce(v_line->>'live_item_id', '')), '')::uuid;
    v_req_id := nullif(trim(coalesce(v_line->>'reservation_request_id', '')), '')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    -- Phase 6.5.1: knowing reservation_id alone never authorizes
    if v_req_id is not null then
      if not public.batata_commerce_reservation_usable_by_actor(
           v_req_id, v_buyer, v_guest
         ) then
        return jsonb_build_object(
          'ok', false,
          'error', 'reservation_not_authorized',
          'reservation_request_id', v_req_id,
          'message', 'reservation_id_alone_does_not_authorize_checkout'
        );
      end if;
    end if;
    if v_product_id is null and v_live_item_id is not null then
      select coalesce(product_id, checkout_product_id) into v_product_id
      from public.live_items where id = v_live_item_id;
    end if;
    if v_product_id is null then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1, 'reason', 'missing_product',
        'reservation_request_id', v_req_id
      ));
      continue;
    end if;
    select seller_id into v_pseller from public.products where id = v_product_id;
    if v_seller is null then
      v_seller := v_pseller;
    elsif v_pseller is distinct from v_seller then
      return jsonb_build_object('ok', false, 'error', 'multi_seller_bag');
    end if;
    select price into v_price from public.products where id = v_product_id;
    if (v_price is null or v_price <= 0) and v_live_item_id is not null then
      select price into v_price from public.live_items where id = v_live_item_id;
    end if;
    if v_price is null or v_price <= 0 then
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1, 'product_id', v_product_id, 'reason', 'missing_price'
      ));
      continue;
    end if;
    v_unit_cents := round(v_price * 100)::int;
    v_line_cents := v_unit_cents * v_qty;
    -- Guests: stock check without guaranteed cover; keep authorized req id in lines
    v_avail_req := case when v_mode = 'guest' then null else v_req_id end;
    v_check := public.batata_commerce_line_availability(
      v_product_id, v_qty, v_buyer, v_avail_req, null
    );
    if coalesce((v_check->>'available')::boolean, false) then
      v_items_cents := v_items_cents + v_line_cents;
      v_avail := v_avail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'unit_cents', v_unit_cents,
        'line_cents', v_line_cents,
        'guaranteed', coalesce((v_check->>'guaranteed')::boolean, false) and v_mode = 'authenticated'
      ));
    else
      v_bag_changed := true;
      v_unavail := v_unavail || jsonb_build_array(jsonb_build_object(
        'index', v_idx - 1,
        'product_id', v_product_id,
        'live_item_id', v_live_item_id,
        'reservation_request_id', v_req_id,
        'quantity', v_qty,
        'reason', coalesce(v_check->>'reason', 'unavailable')
      ));
    end if;
  end loop;
  if jsonb_array_length(v_avail) = 0 then
    return jsonb_build_object(
      'ok', true,
      'bag_changed', true,
      'all_unavailable', true,
      'mode', v_mode,
      'available_lines', v_avail,
      'unavailable_lines', v_unavail,
      'seller_id', v_seller,
      'quote', jsonb_build_object(
        'items_cents', 0, 'shipping_cents', 0,
        'protection_fee_cents', 0, 'total_cents', 0
      )
    );
  end if;
  v_prot_cents := public.batata_commerce_protection_fee_cents(v_items_cents, v_ship_cents);
  v_total_cents := v_items_cents + v_ship_cents + v_prot_cents;
  return jsonb_build_object(
    'ok', true,
    'bag_changed', v_bag_changed,
    'all_unavailable', false,
    'mode', v_mode,
    'available_lines', v_avail,
    'unavailable_lines', v_unavail,
    'seller_id', v_seller,
    'shipping_method', p_shipping_method,
    'quote', jsonb_build_object(
      'items_cents', v_items_cents,
      'shipping_cents', v_ship_cents,
      'protection_fee_cents', v_prot_cents,
      'total_cents', v_total_cents
    )
  );
end;
$function$;

-- Patched begin (from PROD + ZIP 144.3 deltas)
CREATE OR REPLACE FUNCTION public.batata_commerce_checkout_begin(p_lines jsonb, p_shipping_method text, p_payment_rail text, p_delivery jsonb DEFAULT '{}'::jsonb, p_live_id uuid DEFAULT NULL::uuid, p_client_idempotency_key text DEFAULT NULL::text, p_confirm_remainder boolean DEFAULT false, p_guest_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_actor jsonb;
  v_buyer uuid;
  v_guest uuid;
  v_mode text;
  v_rail text := lower(trim(coalesce(p_payment_rail, '')));
  v_ceiling interval;
  v_attempt public.commerce_checkout_attempts%rowtype;
  v_reval jsonb;
  v_lines jsonb;
  v_line jsonb;
  v_seller uuid;
  v_ship_cents int;
  v_items_cents int := 0;
  v_prot_cents int;
  v_total_cents int;
  v_expires timestamptz;
  v_order_ids uuid[] := array[]::uuid[];
  v_product_ids uuid[] := array[]::uuid[];
  v_pid uuid;
  v_liid uuid;
  v_req_id uuid;
  v_qty int;
  v_unit_cents int;
  v_line_cents int;
  v_check jsonb;
  v_guaranteed boolean;
  v_order_id uuid;
  v_hold_id uuid;
  v_pm text;
  v_sync jsonb;
  v_existing uuid;
  v_snap_at timestamptz;
  v_lock_row record;
  v_line_live_id uuid;
  v_idem text := nullif(trim(coalesce(p_client_idempotency_key, '')), '');
begin
  v_actor := public.batata_commerce_resolve_checkout_actor(p_guest_token);
  if coalesce((v_actor->>'ok')::boolean, false) is not true then
    return v_actor;
  end if;
  v_mode := v_actor->>'mode';
  v_buyer := nullif(v_actor->>'buyer_id', '')::uuid;
  v_guest := nullif(v_actor->>'guest_session_id', '')::uuid;
  if v_buyer is null and v_guest is null then
    return jsonb_build_object('ok', false, 'error', 'identity_required');
  end if;
  -- Phase 6.5.1: gate on original client lines (before revalidate can alter them)
  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    v_req_id := nullif(trim(coalesce(v_line->>'reservation_request_id', '')), '')::uuid;
    if v_req_id is not null then
      if not public.batata_commerce_reservation_usable_by_actor(
           v_req_id, v_buyer, v_guest
         ) then
        return jsonb_build_object(
          'ok', false,
          'error', 'reservation_not_authorized',
          'reservation_request_id', v_req_id,
          'message', 'reservation_id_alone_does_not_authorize_checkout'
        );
      end if;
    end if;
  end loop;
  if v_rail not in ('stripe', 'off_platform', 'ifthenpay') then
    return jsonb_build_object('ok', false, 'error', 'invalid_payment_rail');
  end if;
  if v_rail = 'ifthenpay' then
    return jsonb_build_object(
      'ok', false,
      'error', 'ifthenpay_integration_pending',
      'message', 'Architecturally prepared; external Ifthenpay integration not enabled'
    );
  end if;
  v_ceiling := case when v_rail = 'off_platform' then interval '15 minutes'
                    when v_rail = 'ifthenpay' then interval '15 minutes'
                    else interval '30 minutes' end;
  if v_idem is not null then
    perform pg_advisory_xact_lock(
      hashtext(
        'uc_checkout_idem:'
        || coalesce(v_buyer::text, '')
        || ':'
        || coalesce(v_guest::text, '')
        || ':'
        || v_idem
      )
    );
  end if;
  if v_idem is not null then
    if v_buyer is not null then
      select id into v_existing
      from public.commerce_checkout_attempts
      where buyer_id = v_buyer
        and client_idempotency_key = v_idem
        and status in ('drafted', 'payment_started_valid', 'payment_processing')
        and expires_at > timezone('utc', now())
      order by created_at desc limit 1;
    else
      select id into v_existing
      from public.commerce_checkout_attempts
      where guest_session_id = v_guest
        and client_idempotency_key = v_idem
        and status in ('drafted', 'payment_started_valid', 'payment_processing')
        and expires_at > timezone('utc', now())
      order by created_at desc limit 1;
    end if;
    if v_existing is not null then
      return public.batata_commerce_checkout_reuse_response(v_existing, v_mode);
    end if;
  end if;
  v_reval := public.batata_commerce_checkout_revalidate(
    p_lines, p_shipping_method, null, p_guest_token
  );
  if coalesce((v_reval->>'ok')::boolean, false) is not true then
    return v_reval;
  end if;
  if coalesce((v_reval->>'all_unavailable')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'all_unavailable', 'revalidation', v_reval);
  end if;
  if coalesce((v_reval->>'bag_changed')::boolean, false)
     and not coalesce(p_confirm_remainder, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'bag_changed_confirmation_required',
      'revalidation', v_reval
    );
  end if;
  v_lines := v_reval->'available_lines';
  v_seller := nullif(v_reval->>'seller_id', '')::uuid;
  v_ship_cents := coalesce((v_reval->'quote'->>'shipping_cents')::int, 0);
  v_items_cents := coalesce((v_reval->'quote'->>'items_cents')::int, 0);
  v_prot_cents := coalesce((v_reval->'quote'->>'protection_fee_cents')::int, 0);
  v_total_cents := coalesce((v_reval->'quote'->>'total_cents')::int, 0);
  v_expires := timezone('utc', now()) + v_ceiling;
  v_pm := case when v_rail = 'stripe' then 'Pagamento na App'
               else 'Pagamento Direto ao Vendedor (MB WAY/Transf)' end;
  v_sync := public.batata_commerce_checkout_sync_lines_under_locks(
    v_lines, v_buyer, v_guest, p_shipping_method
  );
  if coalesce((v_sync->>'ok')::boolean, false) is not true then
    return jsonb_build_object(
      'ok', false,
      'error', coalesce(v_sync->>'error', 'reservation_lock_sync_failed'),
      'detail', v_sync
    );
  end if;
  v_lines := v_sync->'lines';
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
  v_total_cents := v_items_cents + v_ship_cents + v_prot_cents;
  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    if v_pid is not null and not (v_pid = any (v_product_ids)) then
      v_product_ids := array_append(v_product_ids, v_pid);
    end if;
  end loop;
  for v_lock_row in select unnest(v_product_ids) as pid order by 1
  loop
    perform pg_advisory_xact_lock(hashtext(v_lock_row.pid::text || ':checkout_stock'));
    perform 1 from public.products p where p.id = v_lock_row.pid for update;
  end loop;
  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    if v_req_id is not null then
      if not public.batata_commerce_reservation_usable_by_actor(
           v_req_id, v_buyer, v_guest
         ) then
        return jsonb_build_object(
          'ok', false,
          'error', 'reservation_not_authorized',
          'reservation_request_id', v_req_id,
          'message', 'reservation_id_alone_does_not_authorize_checkout'
        );
      end if;
    end if;
    v_check := public.batata_commerce_line_availability(
      v_pid, v_qty, v_buyer, case when v_mode = 'guest' then null else v_req_id end, null
    );
    if not coalesce((v_check->>'available')::boolean, false) then
      return jsonb_build_object(
        'ok', false,
        'error', 'stock_race_lost',
        'product_id', v_pid,
        'revalidation', public.batata_commerce_checkout_revalidate(
          p_lines, p_shipping_method, v_seller, p_guest_token
        )
      );
    end if;
  end loop;
  v_snap_at := case
    when coalesce(nullif(trim(p_delivery->>'line1'), ''), '') <> ''
      or coalesce(nullif(trim(p_delivery->>'recipient_name'), ''), '') <> ''
    then timezone('utc', now())
    else null
  end;
  begin
    insert into public.commerce_checkout_attempts (
      buyer_id, guest_session_id, seller_id, payment_rail, status,
      shipping_method, items_cents, shipping_cents, protection_fee_cents, total_cents,
      live_id, client_idempotency_key, expires_at,
      delivery_recipient_name, delivery_line1, delivery_line2, delivery_postal_code,
      delivery_city, delivery_country, delivery_phone,
      delivery_point_ref, delivery_point_provider, delivery_point_label,
      delivery_snapshot_at
    ) values (
      v_buyer, v_guest, v_seller, v_rail, 'payment_started_valid',
      p_shipping_method, v_items_cents, v_ship_cents, v_prot_cents, v_total_cents,
      p_live_id, v_idem, v_expires,
      nullif(trim(p_delivery->>'recipient_name'), ''),
      nullif(trim(p_delivery->>'line1'), ''),
      nullif(trim(p_delivery->>'line2'), ''),
      nullif(trim(p_delivery->>'postal_code'), ''),
      nullif(trim(p_delivery->>'city'), ''),
      nullif(trim(p_delivery->>'country'), ''),
      nullif(trim(p_delivery->>'phone'), ''),
      nullif(trim(p_delivery->>'point_ref'), ''),
      nullif(trim(p_delivery->>'point_provider'), ''),
      nullif(trim(p_delivery->>'point_label'), ''),
      v_snap_at
    ) returning * into v_attempt;
  exception when unique_violation then
    if v_buyer is not null then
      select id into v_existing
      from public.commerce_checkout_attempts
      where buyer_id = v_buyer and client_idempotency_key = v_idem
      order by created_at desc limit 1;
    else
      select id into v_existing
      from public.commerce_checkout_attempts
      where guest_session_id = v_guest and client_idempotency_key = v_idem
      order by created_at desc limit 1;
    end if;
    return public.batata_commerce_checkout_reuse_response(v_existing, v_mode);
  end;
  for v_line in select * from jsonb_array_elements(v_lines)
  loop
    v_pid := (v_line->>'product_id')::uuid;
    v_liid := nullif(v_line->>'live_item_id', '')::uuid;
    v_req_id := nullif(v_line->>'reservation_request_id', '')::uuid;
    if v_req_id is not null then
      if not public.batata_commerce_reservation_usable_by_actor(
           v_req_id, v_buyer, v_guest
         ) then
        return jsonb_build_object(
          'ok', false,
          'error', 'reservation_not_authorized',
          'reservation_request_id', v_req_id,
          'message', 'reservation_id_alone_does_not_authorize_checkout'
        );
      end if;
    end if;
    v_qty := greatest(coalesce((v_line->>'quantity')::int, 1), 1);
    v_unit_cents := coalesce((v_line->>'unit_cents')::int, 0);
    v_line_cents := coalesce((v_line->>'line_cents')::int, v_unit_cents * v_qty);
    v_guaranteed := coalesce((v_line->>'guaranteed')::boolean, false) and v_mode = 'authenticated';
    v_line_live_id := p_live_id;
    if v_liid is not null then
      select live_id into v_line_live_id from public.live_items where id = v_liid;
      v_line_live_id := coalesce(v_line_live_id, p_live_id);
    end if;
    insert into public.orders (
      product_id, buyer_id, seller_id, price_total, shipping_method, payment_method,
      status, is_reservation, quantity, live_id, live_item_id,
      checkout_attempt_id, guest_session_id,
      delivery_recipient_name, delivery_line1, delivery_line2, delivery_postal_code,
      delivery_city, delivery_country, delivery_phone,
      delivery_point_ref, delivery_point_provider, delivery_point_label,
      delivery_snapshot_at
    ) values (
      v_pid, v_buyer, v_seller,
      (v_line_cents::numeric / 100.0),
      p_shipping_method, v_pm,
      'reserva_pendente', false, v_qty, v_line_live_id, v_liid,
      v_attempt.id, v_guest,
      v_attempt.delivery_recipient_name, v_attempt.delivery_line1, v_attempt.delivery_line2,
      v_attempt.delivery_postal_code, v_attempt.delivery_city, v_attempt.delivery_country,
      v_attempt.delivery_phone, v_attempt.delivery_point_ref, v_attempt.delivery_point_provider,
      v_attempt.delivery_point_label, v_attempt.delivery_snapshot_at
    ) returning id into v_order_id;
    v_order_ids := array_append(v_order_ids, v_order_id);
    insert into public.commerce_checkout_holds (
      attempt_id, buyer_id, guest_session_id, seller_id, product_id, live_item_id,
      reservation_request_id, quantity, covers_guaranteed, status, expires_at
    ) values (
      v_attempt.id, v_buyer, v_guest, v_seller, v_pid, v_liid,
      v_req_id, v_qty, v_guaranteed, 'active', v_expires
    ) returning id into v_hold_id;
    if v_req_id is not null then
      update public.live_reservation_requests lrr
      set notes = trim(both ' |' from (
            coalesce(nullif(trim(lrr.notes), ''), '')
            || case when coalesce(lrr.notes, '') = '' then '' else ' | ' end
            || 'stripe_checkout:' || v_order_id::text
            || ' | checkout_attempt:' || v_attempt.id::text
          )),
          updated_at = timezone('utc', now())
      where lrr.id = v_req_id
        and (
          (v_buyer is not null and lrr.buyer_id = v_buyer)
          or (v_guest is not null and lrr.guest_session_id = v_guest)
        );
    end if;
  end loop;
    -- ZIP 144.3: selar peso + shipping_cents_charged (CPI/settle usam o mesmo selo)
  perform public.batata_commerce_seal_attempt_orders_shipping(v_attempt.id);
update public.commerce_checkout_attempts
  set status = 'payment_processing',
      updated_at = timezone('utc', now())
  where id = v_attempt.id
  returning * into v_attempt;
  return jsonb_build_object(
    'ok', true,
    'mode', v_mode,
    'checkout_attempt_id', v_attempt.id,
    'status', v_attempt.status,
    'items_cents', v_attempt.items_cents,
    'shipping_cents', v_attempt.shipping_cents,
    'protection_fee_cents', v_attempt.protection_fee_cents,
    'total_cents', v_attempt.total_cents,
    'expires_at', v_attempt.expires_at,
    'order_ids', to_jsonb(v_order_ids),
    'payment_rail', v_attempt.payment_rail
  );
end;
$function$;

notify pgrst, 'reload schema';

-- ZIP 144.3 hotfix: remover overload 5-arg que tornava begin amb�guo
drop function if exists public.batata_commerce_checkout_revalidate(jsonb, text, uuid, text, jsonb);

