-- =============================================================================
-- ZIP 142 — Política taxa Stripe no delta (default: NÃO repercutir ao comprador)
-- PSD2 / PT: surcharge de meios de pagamento consumer IFR é proibido.
-- Flag OFF por defeito. Gross-up 1,5%+0,25 só se GO legal + flag ON.
-- NÃO activa cron / DPD / PROD.
-- =============================================================================

insert into public.fleaber_feature_flags (key, enabled, note)
values
  ('order_shipping_delta_pass_stripe_fee', false,
   'ZIP142: se true, gross-up taxa Stripe no PI delta (requer GO legal PSD2). Default false = comprador paga só diferença portes; taxa absorvida.')
on conflict (key) do update
  set note = excluded.note,
      updated_at = now();
-- NÃO forçar enabled=false se já estiver true em ambiente de teste deliberado —
-- update só note.

create or replace function public.batata_shipping_delta_charge_cents(
  p_shipping_delta_cents integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pass boolean := public.batata_flag_enabled('order_shipping_delta_pass_stripe_fee');
  v_fee_fixed integer := 25;
  v_fee_bps integer := 150;
  v_delta integer := greatest(coalesce(p_shipping_delta_cents, 0), 0);
  v_charge integer;
  v_grossup integer;
begin
  if not v_pass then
    return jsonb_build_object(
      'shipping_delta_cents', v_delta,
      'stripe_fee_grossup_cents', 0,
      'amount_charge_cents', v_delta,
      'pass_stripe_fee', false,
      'fee_policy', 'absorb_stripe_fee_psd2_safe',
      'list_rate_note', 'Stripe PT lista: card EEE padrão / MB WAY = 1,5%+0,25€ (premium 2,8%+0,25). Não cobrado ao buyer.'
    );
  end if;
  v_charge := ceil(((v_delta + v_fee_fixed)::numeric * 10000)
    / (10000 - v_fee_bps))::int;
  v_grossup := v_charge - v_delta;
  return jsonb_build_object(
    'shipping_delta_cents', v_delta,
    'stripe_fee_grossup_cents', v_grossup,
    'amount_charge_cents', v_charge,
    'pass_stripe_fee', true,
    'fee_policy', 'grossup_list_rate_go_required',
    'fee_fixed_cents', v_fee_fixed,
    'fee_bps', v_fee_bps
  );
end;
$$;

revoke all on function public.batata_shipping_delta_charge_cents(integer)
  from public, anon;
grant execute on function public.batata_shipping_delta_charge_cents(integer)
  to authenticated, service_role;

-- Recria seller confirm a usar a política (sem hardcode gross-up activo)
create or replace function public.batata_seller_confirm_shipping_weight(
  p_order_id uuid,
  p_actual_kg numeric default null,
  p_actual_band text default null,
  p_action text default 'confirm'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_band text;
  v_charged text;
  v_modality text;
  v_price_from numeric;
  v_price_to numeric;
  v_delta_cents integer;
  v_quote jsonb;
  v_charge integer;
  v_grossup integer;
  v_adj_id uuid;
  v_flag_w boolean;
  v_flag_d boolean;
  v_expires timestamptz;
  v_nid uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  v_flag_w := public.batata_flag_enabled('order_weight_confirm_enabled');
  v_flag_d := public.batata_flag_enabled('order_shipping_delta_enabled');
  if not v_flag_w then
    return jsonb_build_object('ok', false, 'error', 'weight_confirm_disabled');
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.seller_id is distinct from v_uid and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if lower(coalesce(v_order.status, '')) not in ('pago', 'premio_rifa') then
    return jsonb_build_object('ok', false, 'error', 'status_blocked');
  end if;
  if coalesce(v_order.weight_confirm_status, '') in ('confirmed_same', 'assumed_by_seller', 'delta_paid') then
    return jsonb_build_object('ok', false, 'error', 'already_confirmed');
  end if;
  if exists (
    select 1 from public.order_shipping_adjustments a
    where a.order_id = p_order_id and a.status = 'pending'
  ) then
    return jsonb_build_object('ok', false, 'error', 'delta_already_pending');
  end if;

  v_band := nullif(trim(coalesce(p_actual_band, '')), '');
  if v_band is null and p_actual_kg is not null and p_actual_kg > 0 then
    v_band := public.batata_dpd_weight_band(p_actual_kg);
  end if;
  if v_band is null or v_band = 'over_10' then
    return jsonb_build_object('ok', false, 'error', 'weight_invalid',
      'message', 'Indica peso ou escalão válido (máx. 10 kg).');
  end if;

  v_charged := coalesce(v_order.shipping_weight_charged_band, v_order.shipping_weight_band);
  if v_charged is null then
    return jsonb_build_object('ok', false, 'error', 'no_charged_band');
  end if;
  v_modality := coalesce(v_order.shipping_modality,
    case when coalesce(v_order.delivery_point_ref, '') <> '' then 'shop_to_shop' else 'shop_to_home' end);

  update public.orders set
    shipping_weight_actual_kg = p_actual_kg,
    shipping_weight_actual_band = v_band,
    weight_confirmed_at = now()
  where id = p_order_id;

  if v_band = v_charged then
    update public.orders set
      weight_confirm_status = 'confirmed_same',
      shipping_delta_status = 'none'
    where id = p_order_id;
    perform public.batata_ship_clock_resume(p_order_id);
    return jsonb_build_object('ok', true, 'result', 'confirmed_same', 'band', v_band);
  end if;

  if p_action = 'assume' then
    update public.orders set
      weight_confirm_status = 'assumed_by_seller',
      shipping_delta_status = 'assumed'
    where id = p_order_id;
    insert into public.order_shipping_adjustments (
      order_id, status, band_from, band_to, modality,
      shipping_delta_cents, stripe_fee_grossup_cents, amount_charge_cents,
      buyer_id, seller_id, expires_at, assumed_at
    ) values (
      p_order_id, 'assumed', v_charged, v_band, v_modality,
      0, 0, 0, v_order.buyer_id, v_order.seller_id, now(), now()
    );
    perform public.batata_ship_clock_resume(p_order_id);
    return jsonb_build_object('ok', true, 'result', 'assumed_by_seller', 'band', v_band);
  end if;

  if p_action = 'request_delta' then
    if not v_flag_d then
      return jsonb_build_object('ok', false, 'error', 'shipping_delta_disabled');
    end if;
    select price_eur into v_price_from from public.dpd_shipping_rates
      where modality = v_modality and weight_band = v_charged and active limit 1;
    select price_eur into v_price_to from public.dpd_shipping_rates
      where modality = v_modality and weight_band = v_band and active limit 1;
    if v_price_from is null or v_price_to is null then
      return jsonb_build_object('ok', false, 'error', 'rate_missing');
    end if;
    if v_price_to <= v_price_from then
      update public.orders set weight_confirm_status = 'confirmed_same', shipping_delta_status = 'none'
      where id = p_order_id;
      perform public.batata_ship_clock_resume(p_order_id);
      return jsonb_build_object('ok', true, 'result', 'confirmed_same', 'note', 'no_price_increase');
    end if;
    v_delta_cents := round((v_price_to - v_price_from) * 100)::int;
    v_quote := public.batata_shipping_delta_charge_cents(v_delta_cents);
    v_charge := coalesce((v_quote->>'amount_charge_cents')::int, v_delta_cents);
    v_grossup := coalesce((v_quote->>'stripe_fee_grossup_cents')::int, 0);
    v_expires := now() + interval '48 hours';

    insert into public.order_shipping_adjustments (
      order_id, status, band_from, band_to, modality,
      shipping_delta_cents, stripe_fee_grossup_cents, amount_charge_cents,
      buyer_id, seller_id, expires_at
    ) values (
      p_order_id, 'pending', v_charged, v_band, v_modality,
      v_delta_cents, v_grossup, v_charge,
      v_order.buyer_id, v_order.seller_id, v_expires
    ) returning id into v_adj_id;

    update public.orders set
      weight_confirm_status = 'delta_requested',
      shipping_delta_status = 'pending'
    where id = p_order_id;

    perform public.batata_ship_clock_pause(p_order_id);

    begin
      v_nid := public.batata_emit_user_notification(
        p_recipient_id := v_order.buyer_id,
        p_kind := 'shipping_delta_requested',
        p_title := 'Diferença de portes a pagar',
        p_body := format(
          'O vendedor pediu %s € de diferença de portes (escalão %s→%s). Tens 48 horas.',
          to_char(v_charge / 100.0, 'FM999990.00'),
          v_charged,
          v_band
        ),
        p_chat_id := null,
        p_product_id := v_order.product_id,
        p_offer_id := null,
        p_actor_id := v_uid,
        p_dedupe_key := 'ship_delta:' || p_order_id::text || ':requested',
        p_order_id := p_order_id
      );
    exception when others then
      v_nid := null;
    end;

    return jsonb_build_object(
      'ok', true,
      'result', 'delta_requested',
      'adjustment_id', v_adj_id,
      'shipping_delta_cents', v_delta_cents,
      'stripe_fee_grossup_cents', v_grossup,
      'amount_charge_cents', v_charge,
      'fee_policy', v_quote->>'fee_policy',
      'pass_stripe_fee', (v_quote->>'pass_stripe_fee')::boolean,
      'expires_at', v_expires,
      'band_from', v_charged,
      'band_to', v_band,
      'notification_id', v_nid,
      'c2_email_kind', 'shipping_delta_requested',
      'c2_email_status', 'pending_c2_template',
      'fleaber_protection_cents', 0
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'invalid_action');
end;
$$;

revoke all on function public.batata_seller_confirm_shipping_weight(uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_seller_confirm_shipping_weight(uuid, numeric, text, text)
  to authenticated, service_role;

comment on function public.batata_shipping_delta_charge_cents(integer) is
  'ZIP142: montante PI delta. Default absorve taxa Stripe (PSD2). Flag order_shipping_delta_pass_stripe_fee OFF.';
