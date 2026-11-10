-- =============================================================================
-- ZIP 149.1 — Prazo pagamento 48h pós-cotação + flag ON
-- (webhook idempotente = Edge; esta migração = SQL contratos)
-- =============================================================================

update public.fleaber_feature_flags
set
  enabled = true,
  note = 'ZIP149.1: prazo 48h após confirmação de portes (awaiting_payment). Validado em touch_expiry / begin — sem cron.'
where key = 'bundle_awaiting_payment_deadline_enabled';

insert into public.fleaber_feature_flags (key, enabled, note)
values (
  'bundle_awaiting_payment_deadline_enabled',
  true,
  'ZIP149.1: prazo 48h após confirmação de portes (awaiting_payment). Validado em touch_expiry / begin — sem cron.'
)
on conflict (key) do update
set enabled = true,
    note = excluded.note;

-- Confirm quote: pay_expires_at = now + 48h (antes 24h proposta)
create or replace function public.batata_bundle_seller_confirm_quote(
  p_bundle_id uuid,
  p_weight_kg numeric,
  p_weight_band text default null,
  p_shipping_modality text default 'shop_to_shop',
  p_shipping_method text default 'Envio Transportadora (DPD)',
  p_delivery_point_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_b public.product_bundles%rowtype;
  v_band text;
  v_modality text;
  v_ship_method text;
  v_articles_cents int;
  v_ship_cents int;
  v_prot_cents int;
  v_total int;
  v_fp text;
  v_lines jsonb := '[]'::jsonb;
  v_delivery jsonb;
  v_pid uuid;
  v_qty int;
  v_sub numeric;
  v_dead int;
  v_pay_exp timestamptz;
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
  if v_b.seller_id is distinct from v_uid and not coalesce(public.batata_is_admin(), false) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if v_b.status = 'expired' then
    return jsonb_build_object('ok', false, 'error', 'expired');
  end if;
  if v_b.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'error', 'status_blocked', 'status', v_b.status);
  end if;

  select count(*)::int into v_dead
  from unnest(v_b.product_ids) pid
  join public.products p on p.id = pid
  where coalesce(p.is_sold, false) or not coalesce(p.list_on_marketplace, false);
  if v_dead > 0 then
    return jsonb_build_object('ok', false, 'error', 'article_unavailable');
  end if;

  v_band := nullif(trim(coalesce(p_weight_band, '')), '');
  if v_band is null and p_weight_kg is not null and p_weight_kg > 0 then
    v_band := public.batata_dpd_weight_band(p_weight_kg);
  end if;
  if v_band is null or v_band = 'over_10' then
    return jsonb_build_object('ok', false, 'error', 'weight_invalid');
  end if;

  v_modality := lower(trim(coalesce(p_shipping_modality, 'shop_to_shop')));
  if v_modality not in ('shop_to_shop', 'shop_to_home') then
    v_modality := 'shop_to_shop';
  end if;
  v_ship_method := coalesce(nullif(trim(p_shipping_method), ''), 'Envio Transportadora (DPD)');

  for v_pid, v_qty in
    select x.pid, count(*)::int from unnest(v_b.product_ids) x(pid) group by x.pid
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', v_pid, 'quantity', v_qty
    ));
  end loop;

  v_sub := public.batata_product_bundles_catalog_subtotal(v_b.product_ids);
  v_articles_cents := round(greatest(coalesce(v_b.total_eur, v_sub), 0) * 100)::int;

  v_delivery := jsonb_build_object(
    'shipping_modality', v_modality,
    'shipping_weight_band', v_band,
    'shipping_weight_kg', p_weight_kg,
    'use_delivery_weight', true,
    'seller_confirmed_weight', true,
    'delivery_point_ref', nullif(trim(coalesce(p_delivery_point_ref, '')), '')
  );
  v_ship_cents := public.batata_commerce_quote_shipping_cents(
    v_ship_method, v_lines, v_delivery
  );
  v_prot_cents := public.batata_commerce_protection_fee_cents(v_articles_cents, v_ship_cents);
  v_total := v_articles_cents + v_ship_cents + v_prot_cents;
  v_fp := public.batata_bundle_quote_fingerprint(v_b.product_ids);

  -- ZIP 149.1: 48h para a compradora pagar (flag ON)
  v_pay_exp := case
    when public.batata_flag_enabled('bundle_awaiting_payment_deadline_enabled')
      then timezone('utc', now()) + interval '48 hours'
    else null
  end;

  update public.product_bundles set
    status = 'awaiting_payment',
    responded_at = timezone('utc', now()),
    quoted_at = timezone('utc', now()),
    quote_shipping_method = v_ship_method,
    quote_shipping_modality = v_modality,
    quote_weight_kg = p_weight_kg,
    quote_weight_band = v_band,
    quote_delivery_point_ref = nullif(trim(coalesce(p_delivery_point_ref, '')), ''),
    articles_cents = v_articles_cents,
    shipping_cents = v_ship_cents,
    protection_cents = v_prot_cents,
    grand_total_cents = v_total,
    quote_fingerprint = v_fp,
    quote_invalidated_at = null,
    quote_invalidation_reason = null,
    rule_version = 'quote_before_pay_v1',
    pay_expires_at = v_pay_exp
  where id = p_bundle_id;

  begin
    perform public.batata_emit_user_notification_trusted(
      v_b.buyer_id,
      'bundle_quote_ready',
      'Preço final do conjunto',
      format(
        'Artigos %s € + portes %s € + Proteção %s € = %s €. Tens 48 horas para pagar ou desistir.',
        to_char(v_articles_cents / 100.0, 'FM999990.00'),
        to_char(v_ship_cents / 100.0, 'FM999990.00'),
        to_char(v_prot_cents / 100.0, 'FM999990.00'),
        to_char(v_total / 100.0, 'FM999990.00')
      ),
      v_b.chat_id, null, null, v_uid,
      'bundle_quote_ready:' || p_bundle_id::text
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'ok', true,
    'bundle_id', p_bundle_id,
    'status', 'awaiting_payment',
    'articles_cents', v_articles_cents,
    'shipping_cents', v_ship_cents,
    'protection_cents', v_prot_cents,
    'grand_total_cents', v_total,
    'quote_weight_band', v_band,
    'quote_shipping_modality', v_modality,
    'pay_expires_at', v_pay_exp,
    'pay_deadline_hours', case when v_pay_exp is not null then 48 else null end,
    'stock_held', false,
    'c2_email_kind', 'bundle_quote_ready'
  );
end;
$$;

-- touch_expiry: notificar compradora na expiração do prazo de pagamento
create or replace function public.batata_bundle_touch_expiry(p_bundle_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.product_bundles%rowtype;
  v_expired int := 0;
  v_pay_expired int := 0;
  v_pay_deadline_on boolean := public.batata_flag_enabled('bundle_awaiting_payment_deadline_enabled');
  r record;
begin
  for r in
    select b.id
    from public.product_bundles b
    where (p_bundle_id is null or b.id = p_bundle_id)
      and b.status = 'pending'
      and b.seller_confirm_expires_at is not null
      and b.seller_confirm_expires_at <= timezone('utc', now())
    for update of b
  loop
    update public.product_bundles
    set status = 'expired',
        responded_at = coalesce(responded_at, timezone('utc', now())),
        quote_invalidation_reason = coalesce(quote_invalidation_reason, 'seller_confirm_timeout_48h')
    where id = r.id
    returning * into v_row;
    v_expired := v_expired + 1;
    begin
      perform public.batata_emit_user_notification_trusted(
        v_row.buyer_id, 'bundle_expired',
        'Pedido de conjunto expirou',
        'A vendedora não confirmou o peso e os portes em 48 horas. Não houve cobrança.',
        v_row.chat_id, null, null, null,
        'bundle_expired:' || v_row.id::text
      );
      perform public.batata_emit_user_notification_trusted(
        v_row.seller_id, 'bundle_expired',
        'Pedido de conjunto expirou',
        'Não confirmaste o peso/portes em 48 horas. O pedido expirou sem cobrança.',
        v_row.chat_id, null, null, null,
        'bundle_expired_seller:' || v_row.id::text
      );
    exception when others then
      null;
    end;
  end loop;

  if v_pay_deadline_on then
    for r in
      select b.id
      from public.product_bundles b
      where (p_bundle_id is null or b.id = p_bundle_id)
        and b.status = 'awaiting_payment'
        and b.pay_expires_at is not null
        and b.pay_expires_at <= timezone('utc', now())
      for update of b
    loop
      update public.product_bundles
      set status = 'expired',
          responded_at = coalesce(responded_at, timezone('utc', now())),
          quote_invalidation_reason = coalesce(quote_invalidation_reason, 'buyer_pay_timeout_48h')
      where id = r.id
      returning * into v_row;
      v_pay_expired := v_pay_expired + 1;
      begin
        perform public.batata_emit_user_notification_trusted(
          v_row.buyer_id, 'bundle_expired',
          'Cotação do conjunto expirou',
          'Passaram 48 horas sem pagamento. A cotação expirou. Não foste cobrada.',
          v_row.chat_id, null, null, null,
          'bundle_pay_expired:' || v_row.id::text
        );
        perform public.batata_emit_user_notification_trusted(
          v_row.seller_id, 'bundle_expired',
          'Cotação do conjunto expirou',
          'A compradora não pagou em 48 horas. A cotação expirou sem cobrança.',
          v_row.chat_id, null, null, null,
          'bundle_pay_expired_seller:' || v_row.id::text
        );
      exception when others then
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'expired_pending', v_expired,
    'expired_awaiting_payment', v_pay_expired,
    'pay_deadline_enabled', v_pay_deadline_on,
    'pay_deadline_hours', 48
  );
end;
$$;

comment on function public.batata_bundle_seller_confirm_quote(uuid, numeric, text, text, text, text) is
  'ZIP149.1: confirma cotação → awaiting_payment; pay_expires_at=+48h se flag ON.';
comment on function public.batata_bundle_touch_expiry(uuid) is
  'ZIP149.1: expira pending (48h seller) e awaiting_payment (48h pay) sem cron.';
