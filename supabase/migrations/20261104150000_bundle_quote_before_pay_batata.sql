-- =============================================================================
-- ZIP 149 — Conjuntos: cotação antes do pagamento (sem reserva, 48h, 1× Stripe)
-- Regra: pedido ≠ aguarda confirmação de peso/portes da vendedora →
-- awaiting_payment com preço final → compradora paga numa única transacção.
-- Só o pagamento (begin + webhook) consome stock. Sem shipping_delta em conjuntos.
-- =============================================================================

-- Feature flags (sem cron; pay window OFF até aprovação)
insert into public.fleaber_feature_flags (key, enabled, note)
values
  (
    'bundle_quote_before_pay_v1',
    true,
    'ZIP149: conjuntos sem pagamento/reserva até confirmação de portes; 48h seller'
  ),
  (
    'bundle_awaiting_payment_deadline_enabled',
    false,
    'ZIP149: prazo pós-cotação (proposto 24h) — OFF até aprovação produto'
  )
on conflict (key) do update
set note = excluded.note;

alter table public.product_bundles
  drop constraint if exists product_bundles_status_check;

alter table public.product_bundles
  add constraint product_bundles_status_check
  check (
    lower(trim(status)) in (
      'pending',
      'awaiting_payment',
      'accepted',
      'rejected',
      'cancelled',
      'cancelado',
      'expired',
      'purchased'
    )
  );

alter table public.product_bundles
  add column if not exists seller_confirm_expires_at timestamptz,
  add column if not exists quoted_at timestamptz,
  add column if not exists quote_shipping_method text,
  add column if not exists quote_shipping_modality text,
  add column if not exists quote_weight_kg numeric,
  add column if not exists quote_weight_band text,
  add column if not exists quote_delivery_point_ref text,
  add column if not exists articles_cents integer,
  add column if not exists shipping_cents integer,
  add column if not exists protection_cents integer,
  add column if not exists grand_total_cents integer,
  add column if not exists quote_fingerprint text,
  add column if not exists quote_invalidated_at timestamptz,
  add column if not exists quote_invalidation_reason text,
  add column if not exists pay_expires_at timestamptz,
  add column if not exists rule_version text,
  add column if not exists checkout_attempt_id uuid;

comment on column public.product_bundles.seller_confirm_expires_at is
  'ZIP149: pedido expira se vendedora não confirmar peso/portes a tempo (48h).';
comment on column public.product_bundles.pay_expires_at is
  'ZIP149: opcional; só preenchido se bundle_awaiting_payment_deadline_enabled.';
comment on column public.product_bundles.rule_version is
  'ZIP149: quote_before_pay_v1 nos pedidos novos.';

-- Pedidos pending sem prazo → 48h a partir de created_at (só backfill)
update public.product_bundles
set seller_confirm_expires_at = created_at + interval '48 hours',
    rule_version = coalesce(rule_version, 'quote_before_pay_v1')
where status = 'pending'
  and seller_confirm_expires_at is null;

-- -----------------------------------------------------------------------------
-- Preferência de peso/band do delivery (confirmação vendedora) no quote DPD
-- -----------------------------------------------------------------------------
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
  v_use_delivery_weight boolean := false;
begin
  if m = '' then
    raise exception 'invalid_shipping_method' using errcode = '22023';
  end if;

  -- Override absoluto (cotação selada do conjunto)
  if p_delivery is not null
     and nullif(trim(coalesce(p_delivery->>'shipping_cents_override', '')), '') is not null then
    v_cents := (p_delivery->>'shipping_cents_override')::int;
    if v_cents is null or v_cents < 0 then
      raise exception 'invalid_shipping_amount' using errcode = '22023';
    end if;
    return v_cents;
  end if;

  v_hand := m in (
    'hand', 'mao', 'mão', 'pickup', 'entrega_mao', 'entrega_mão',
    'entrega em mao', 'entrega em mão', 'levantamento',
    'entrega em mão (€0.00)', 'entrega em mao (€0.00)'
  ) or m like '%mão%' or m like '%mao%';

  if m like '%transportadora%' or m like '%dpd%' or m like '%carrier%'
     or m like '%3.50%' or m like '%3,50%' then
    v_hand := false;
    v_carrier := true;
  end if;

  if v_hand and not v_carrier then
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
    return public.batata_commerce_shipping_cents(p_shipping_method);
  end if;

  v_ref := nullif(trim(coalesce(p_delivery->>'delivery_point_ref', '')), '');
  v_modality := lower(trim(coalesce(
    nullif(p_delivery->>'shipping_modality', ''),
    nullif(p_delivery->>'dpd_service', ''),
    case when v_ref is not null then 'shop_to_shop' else 'shop_to_shop' end
  )));
  if v_modality not in ('shop_to_shop', 'shop_to_home') then
    v_modality := 'shop_to_shop';
  end if;

  v_use_delivery_weight := coalesce((p_delivery->>'use_delivery_weight')::boolean, false)
    or coalesce((p_delivery->>'seller_confirmed_weight')::boolean, false);

  v_band := nullif(trim(coalesce(p_delivery->>'shipping_weight_band', '')), '');
  if v_use_delivery_weight then
    v_kg := nullif(trim(coalesce(p_delivery->>'shipping_weight_kg', '')), '')::numeric;
  else
    select max(p.shipping_weight_kg)
      into v_kg
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    join public.products p
      on p.id = nullif(trim(coalesce(e->>'product_id', '')), '')::uuid
    where p.shipping_weight_kg is not null;
    if v_kg is null then
      v_kg := nullif(trim(coalesce(p_delivery->>'shipping_weight_kg', '')), '')::numeric;
    end if;
  end if;

  v_quote := public.batata_dpd_quote_shipping(v_modality, v_kg, v_band, false);
  if coalesce((v_quote->>'ok')::boolean, false) is not true then
    if coalesce(v_quote->>'error', '') = 'weight_required' then
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

-- -----------------------------------------------------------------------------
-- Fingerprint de composição + preços unitários (invalidação)
-- -----------------------------------------------------------------------------
create or replace function public.batata_bundle_quote_fingerprint(p_product_ids uuid[])
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_parts text[] := array[]::text[];
  v_pid uuid;
  v_price numeric;
  v_sold boolean;
  v_listed boolean;
  v_qty int;
begin
  if p_product_ids is null or coalesce(array_length(p_product_ids, 1), 0) < 1 then
    return '';
  end if;
  for v_pid, v_qty in
    select x.pid, count(*)::int
    from unnest(p_product_ids) as x(pid)
    group by x.pid
    order by x.pid
  loop
    select p.price, coalesce(p.is_sold, false), coalesce(p.list_on_marketplace, false)
      into v_price, v_sold, v_listed
    from public.products p where p.id = v_pid;
    v_parts := array_append(
      v_parts,
      v_pid::text || ':' || coalesce(v_qty, 0)::text || ':' ||
      coalesce(to_char(v_price, 'FM999999990.00'), 'x') || ':' ||
      case when v_sold then 'S' else 'A' end || case when v_listed then 'L' else 'U' end
    );
  end loop;
  return encode(digest(array_to_string(v_parts, '|'), 'sha256'), 'hex');
end;
$$;

revoke all on function public.batata_bundle_quote_fingerprint(uuid[]) from public;
grant execute on function public.batata_bundle_quote_fingerprint(uuid[])
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Expiração server-side (sem cron permanente)
-- -----------------------------------------------------------------------------
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
  v_nid uuid;
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
      v_nid := public.batata_emit_user_notification_trusted(
        v_row.buyer_id,
        'bundle_expired',
        'Pedido de conjunto expirou',
        'A vendedora não confirmou o peso e os portes em 48 horas. Não houve cobrança.',
        v_row.chat_id, null, null, null,
        'bundle_expired:' || v_row.id::text
      );
    exception when others then
      v_nid := null;
    end;
    begin
      perform public.batata_emit_user_notification_trusted(
        v_row.seller_id,
        'bundle_expired',
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
          quote_invalidation_reason = coalesce(quote_invalidation_reason, 'buyer_pay_timeout')
      where id = r.id;
      v_pay_expired := v_pay_expired + 1;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'expired_pending', v_expired,
    'expired_awaiting_payment', v_pay_expired,
    'pay_deadline_enabled', v_pay_deadline_on
  );
end;
$$;

revoke all on function public.batata_bundle_touch_expiry(uuid) from public;
grant execute on function public.batata_bundle_touch_expiry(uuid)
  to authenticated, service_role, anon;

-- -----------------------------------------------------------------------------
-- Invalidvalidate quote (artigos vendidos / preço mudou)
-- -----------------------------------------------------------------------------
create or replace function public.batata_bundle_validate_quote(p_bundle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.product_bundles%rowtype;
  v_fp text;
  v_dead int := 0;
  v_held int := 0;
  v_pid uuid;
  v_need int;
  v_check jsonb;
begin
  perform public.batata_bundle_touch_expiry(p_bundle_id);
  select * into v_b from public.product_bundles where id = p_bundle_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_b.status = 'expired' then
    return jsonb_build_object('ok', false, 'error', 'expired', 'status', 'expired');
  end if;
  if v_b.status is distinct from 'awaiting_payment' then
    return jsonb_build_object('ok', false, 'error', 'not_awaiting_payment', 'status', v_b.status);
  end if;

  v_fp := public.batata_bundle_quote_fingerprint(v_b.product_ids);
  if v_fp is distinct from v_b.quote_fingerprint then
    return jsonb_build_object(
      'ok', false,
      'error', 'quote_stale_price_or_composition',
      'message', 'Preço ou composição mudou. É necessária nova confirmação da vendedora.'
    );
  end if;

  select count(*)::int into v_dead
  from unnest(v_b.product_ids) as pid
  join public.products p on p.id = pid
  where coalesce(p.is_sold, false) = true
     or coalesce(p.list_on_marketplace, false) = false;
  if v_dead > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'article_unavailable',
      'message', 'Um ou mais artigos já não estão disponíveis.'
    );
  end if;

  for v_pid, v_need in
    select x.pid, count(*)::int
    from unnest(v_b.product_ids) as x(pid)
    group by x.pid
  loop
    -- Disponível = stock − holds de outros (pedido de conjunto NÃO holda)
    v_check := public.batata_product_checkout_available(v_pid, null, v_need, null);
    if coalesce((v_check->>'ok')::boolean, false) is not true then
      v_held := v_held + 1;
    end if;
  end loop;
  if v_held > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'stock_insufficient',
      'message', 'Stock insuficiente (vendido ou em checkout por outra pessoa).'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'bundle_id', p_bundle_id,
    'status', v_b.status,
    'articles_cents', v_b.articles_cents,
    'shipping_cents', v_b.shipping_cents,
    'protection_cents', v_b.protection_cents,
    'grand_total_cents', v_b.grand_total_cents,
    'quote_weight_band', v_b.quote_weight_band,
    'quote_shipping_modality', v_b.quote_shipping_modality
  );
end;
$$;

revoke all on function public.batata_bundle_validate_quote(uuid) from public;
grant execute on function public.batata_bundle_validate_quote(uuid)
  to authenticated, service_role;

-- Invalidvalida e, se stale, reabre pending (nova confirmação)
create or replace function public.batata_bundle_invalidate_stale_quote(p_bundle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_b public.product_bundles%rowtype;
  v_val jsonb;
  v_reason text;
begin
  select * into v_b from public.product_bundles where id = p_bundle_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_uid is not null
     and v_uid is distinct from v_b.buyer_id
     and v_uid is distinct from v_b.seller_id
     and not public.batata_notify_is_service_role() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  v_val := public.batata_bundle_validate_quote(p_bundle_id);
  if coalesce((v_val->>'ok')::boolean, false) then
    return jsonb_build_object('ok', true, 'valid', true, 'bundle_id', p_bundle_id);
  end if;

  v_reason := coalesce(v_val->>'error', 'quote_invalid');
  if v_b.status = 'awaiting_payment' then
    update public.product_bundles set
      status = 'pending',
      quoted_at = null,
      articles_cents = null,
      shipping_cents = null,
      protection_cents = null,
      grand_total_cents = null,
      quote_fingerprint = null,
      quote_weight_kg = null,
      quote_weight_band = null,
      quote_shipping_method = null,
      quote_shipping_modality = null,
      quote_delivery_point_ref = null,
      pay_expires_at = null,
      checkout_attempt_id = null,
      quote_invalidated_at = timezone('utc', now()),
      quote_invalidation_reason = v_reason,
      seller_confirm_expires_at = timezone('utc', now()) + interval '48 hours',
      responded_at = null
    where id = p_bundle_id;

    begin
      perform public.batata_emit_user_notification_trusted(
        v_b.buyer_id, 'bundle_quote_invalidated',
        'Conjunto desatualizado',
        'Um artigo foi vendido ou o preço mudou. A vendedora tem de voltar a confirmar o conjunto.',
        v_b.chat_id, null, null, null,
        'bundle_quote_invalidated:' || p_bundle_id::text || ':' || v_reason
      );
      perform public.batata_emit_user_notification_trusted(
        v_b.seller_id, 'bundle_quote_invalidated',
        'Conjunto desatualizado',
        'A composição ou o preço mudou. Confirma de novo o peso e os portes.',
        v_b.chat_id, null, null, null,
        'bundle_quote_invalidated_seller:' || p_bundle_id::text || ':' || v_reason
      );
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'valid', false,
    'invalidated', (v_b.status = 'awaiting_payment'),
    'reason', v_reason,
    'validation', v_val
  );
end;
$$;

revoke all on function public.batata_bundle_invalidate_stale_quote(uuid) from public;
grant execute on function public.batata_bundle_invalidate_stale_quote(uuid)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Vendedora confirma peso + portes → awaiting_payment (SEM criar orders/hold)
-- -----------------------------------------------------------------------------
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

  -- Multiset → lines
  for v_pid, v_qty in
    select x.pid, count(*)::int from unnest(v_b.product_ids) x(pid) group by x.pid
  loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'product_id', v_pid, 'quantity', v_qty
    ));
  end loop;

  v_sub := public.batata_product_bundles_catalog_subtotal(v_b.product_ids);
  -- Desconto já em total_eur / discount_*
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
    -- Prazo de pagamento: só se flag ON (proposta 24h — ver relatório)
    pay_expires_at = case
      when public.batata_flag_enabled('bundle_awaiting_payment_deadline_enabled')
        then timezone('utc', now()) + interval '24 hours'
      else null
    end
  where id = p_bundle_id;

  begin
    perform public.batata_emit_user_notification_trusted(
      v_b.buyer_id,
      'bundle_quote_ready',
      'Preço final do conjunto',
      format(
        'Artigos %s € + portes %s € + Proteção %s € = %s €. Podes pagar ou desistir.',
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
    'pay_expires_at', (
      select pay_expires_at from public.product_bundles where id = p_bundle_id
    ),
    'stock_held', false,
    'c2_email_kind', 'bundle_quote_ready'
  );
end;
$$;

revoke all on function public.batata_bundle_seller_confirm_quote(uuid, numeric, text, text, text, text)
  from public;
grant execute on function public.batata_bundle_seller_confirm_quote(uuid, numeric, text, text, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Desistência compradora / cancelamento vendedora
-- -----------------------------------------------------------------------------
create or replace function public.batata_bundle_abandon(
  p_bundle_id uuid,
  p_reason text default 'abandoned'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_b public.product_bundles%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  perform public.batata_bundle_touch_expiry(p_bundle_id);
  select * into v_b from public.product_bundles where id = p_bundle_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_uid is distinct from v_b.buyer_id and v_uid is distinct from v_b.seller_id then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if v_b.status not in ('pending', 'awaiting_payment') then
    return jsonb_build_object('ok', false, 'error', 'status_blocked', 'status', v_b.status);
  end if;

  update public.product_bundles set
    status = 'cancelled',
    responded_at = timezone('utc', now()),
    quote_invalidation_reason = coalesce(nullif(trim(p_reason), ''), 'abandoned')
  where id = p_bundle_id;

  return jsonb_build_object('ok', true, 'bundle_id', p_bundle_id, 'status', 'cancelled');
end;
$$;

revoke all on function public.batata_bundle_abandon(uuid, text) from public;
grant execute on function public.batata_bundle_abandon(uuid, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Checkout begin do conjunto (único caminho de hold + Stripe)
-- -----------------------------------------------------------------------------
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

  -- Montante autorizado = cotação selada (artigos+portes+proteção)
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

  -- Ligar linhas ao conjunto (só bundle_id — money/shipping selados pelo begin).
  if v_attempt_id is not null then
    update public.orders o
      set bundle_id = p_bundle_id
    where o.checkout_attempt_id = v_attempt_id
      and (o.bundle_id is distinct from p_bundle_id);

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

revoke all on function public.batata_bundle_checkout_begin(uuid, text, jsonb) from public;
grant execute on function public.batata_bundle_checkout_begin(uuid, text, jsonb)
  to authenticated, service_role;

-- Marcar purchased após pagamento
create or replace function public.batata_bundle_mark_purchased(p_bundle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.product_bundles%rowtype;
begin
  update public.product_bundles
  set status = 'purchased',
      responded_at = coalesce(responded_at, timezone('utc', now()))
  where id = p_bundle_id
    and status in ('awaiting_payment', 'pending', 'accepted')
  returning * into v_b;
  if not found then
    select * into v_b from public.product_bundles where id = p_bundle_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'not_found');
    end if;
    return jsonb_build_object('ok', true, 'status', v_b.status, 'already', true);
  end if;
  return jsonb_build_object('ok', true, 'bundle_id', p_bundle_id, 'status', 'purchased');
end;
$$;

revoke all on function public.batata_bundle_mark_purchased(uuid) from public;
grant execute on function public.batata_bundle_mark_purchased(uuid)
  to service_role, authenticated;

-- -----------------------------------------------------------------------------
-- Guard: novos status + INSERT define 48h; bloquear accepted legado sem RPC
-- -----------------------------------------------------------------------------
create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
  v_dead int := 0;
  v_new_st text;
  v_old_st text;
  v_sub numeric(12, 2);
  v_pct numeric(5, 2);
  v_disc numeric(12, 2);
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      if lower(trim(coalesce(NEW.status, 'pending'))) is distinct from 'pending' then
        raise exception 'bundle_status_pending_only' using errcode = '23514';
      end if;
      NEW.status := 'pending';
      NEW.discount_pct := 0;
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;
    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;

    select count(*)::int into v_dead
    from unnest(NEW.product_ids) as pid
    join public.products p on p.id = pid
    where coalesce(p.list_on_marketplace, false) = false
       or coalesce(p.is_sold, false) = true;
    if v_dead > 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;

    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
    NEW.seller_confirm_expires_at := coalesce(
      NEW.seller_confirm_expires_at,
      timezone('utc', now()) + interval '48 hours'
    );
    NEW.rule_version := coalesce(NEW.rule_version, 'quote_before_pay_v1');
    return NEW;
  end if;

  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    -- ZIP149: «accepted» legado bloqueado no cliente — usar RPC confirm_quote
    if v_new_st = 'accepted' then
      raise exception 'bundle_use_confirm_quote_rpc' using errcode = 'P0001';
    end if;
    if v_new_st = 'awaiting_payment' and v_uid is distinct from OLD.seller_id then
      raise exception 'bundle_quote_seller_only' using errcode = '42501';
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado', 'expired')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_party' using errcode = '42501';
    end if;
    if v_new_st = 'purchased'
       and v_uid is distinct from OLD.buyer_id
       and not public.batata_notify_is_service_role() then
      -- compradora ou service; vendedora não marca purchased à mão
      null;
    end if;
  end if;

  if v_uid is distinct from OLD.seller_id then
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.total_eur := OLD.total_eur;
  else
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    else
      v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
      v_disc := round(v_sub * (v_pct / 100.0), 2);
      NEW.subtotal_eur := v_sub;
      NEW.discount_pct := v_pct;
      NEW.discount_eur := v_disc;
      NEW.total_eur := greatest(v_sub - v_disc, 0);
    end if;
  end if;

  if v_old_st in (
    'awaiting_payment', 'accepted', 'rejected', 'cancelled', 'cancelado',
    'expired', 'purchased'
  ) and v_new_st is distinct from v_old_st then
    -- Terminal / cotado: só RPCs (security definer com role autenticado ainda passa
    -- aqui). Permitir pending←awaiting_payment (invalidate) e purchased/cancelled/expired.
    if not (
      (v_old_st = 'awaiting_payment' and v_new_st in ('pending', 'cancelled', 'expired', 'purchased'))
      or (v_old_st = 'pending' and v_new_st in ('awaiting_payment', 'cancelled', 'expired'))
      or (v_new_st in ('cancelled', 'expired', 'purchased'))
    ) then
      NEW.status := OLD.status;
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    end if;
  end if;

  return NEW;
end;
$fn$;

-- -----------------------------------------------------------------------------
-- Bloquear holds de conjunto sem checkout_attempt (anti-reserva no accept legado)
-- -----------------------------------------------------------------------------
create or replace function public.batata_orders_bundle_no_prepay_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_flag_enabled('bundle_quote_before_pay_v1') then
    return NEW;
  end if;
  if TG_OP = 'INSERT' or TG_OP = 'UPDATE' then
    if NEW.bundle_id is not null
       and coalesce(auth.role(), '') = 'authenticated'
       and lower(trim(coalesce(NEW.status, ''))) in ('reservado', 'aguarda_confirmacao')
       and NEW.checkout_attempt_id is null
       and coalesce(NEW.is_reservation, false) = true then
      raise exception 'bundle_no_stock_hold_until_pay'
        using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_batata_orders_bundle_no_prepay_hold on public.orders;
create trigger trg_batata_orders_bundle_no_prepay_hold
  before insert or update of status, bundle_id, checkout_attempt_id, is_reservation
  on public.orders
  for each row
  execute function public.batata_orders_bundle_no_prepay_hold();

-- -----------------------------------------------------------------------------
-- Sem shipping_delta em conjuntos (portes já na cotação pré-pagamento)
-- -----------------------------------------------------------------------------
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
  v_charge integer;
  v_grossup integer;
  v_adj_id uuid;
  v_flag_w boolean;
  v_flag_d boolean;
  v_nid uuid;
  v_expires timestamptz;
  v_fee jsonb;
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
  if v_order.seller_id is distinct from v_uid and not coalesce(public.batata_is_admin(), false) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if lower(coalesce(v_order.status, '')) not in ('pago', 'premio_rifa') then
    return jsonb_build_object('ok', false, 'error', 'status_blocked');
  end if;

  -- ZIP149: conjuntos com regra nova — portes já cobrados na cotação; sem 2.º pagamento
  if v_order.bundle_id is not null
     and exists (
       select 1 from public.product_bundles b
       where b.id = v_order.bundle_id
         and coalesce(b.rule_version, '') = 'quote_before_pay_v1'
     ) then
    update public.orders set
      shipping_weight_actual_kg = p_actual_kg,
      shipping_weight_actual_band = coalesce(
        nullif(trim(coalesce(p_actual_band, '')), ''),
        public.batata_dpd_weight_band(p_actual_kg)
      ),
      weight_confirmed_at = now(),
      weight_confirm_status = 'confirmed_same',
      shipping_delta_status = 'none'
    where id = p_order_id;
    return jsonb_build_object(
      'ok', true,
      'result', 'bundle_prequoted_no_delta',
      'message', 'Conjunto: portes já incluídos na cotação pré-pagamento.'
    );
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

  if v_band = v_charged or (p_action = 'confirm' and v_band = v_charged) then
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
      0, 0, 0,
      v_order.buyer_id, v_order.seller_id, now() + interval '48 hours', now()
    );
    perform public.batata_ship_clock_resume(p_order_id);
    return jsonb_build_object('ok', true, 'result', 'assumed', 'band', v_band);
  end if;

  if not v_flag_d then
    return jsonb_build_object('ok', false, 'error', 'shipping_delta_disabled');
  end if;

  select price_eur into v_price_from
  from public.dpd_shipping_rates
  where modality = v_modality and weight_band = v_charged and active
  limit 1;
  select price_eur into v_price_to
  from public.dpd_shipping_rates
  where modality = v_modality and weight_band = v_band and active
  limit 1;
  if v_price_from is null or v_price_to is null then
    return jsonb_build_object('ok', false, 'error', 'rate_missing');
  end if;
  v_delta_cents := greatest(round((v_price_to - v_price_from) * 100)::int, 0);
  if v_delta_cents <= 0 then
    update public.orders set
      weight_confirm_status = 'confirmed_same',
      shipping_delta_status = 'none'
    where id = p_order_id;
    return jsonb_build_object('ok', true, 'result', 'confirmed_same', 'band', v_band);
  end if;

  v_fee := public.batata_shipping_delta_charge_cents(v_delta_cents);
  v_grossup := coalesce((v_fee->>'stripe_fee_grossup_cents')::int, 0);
  v_charge := coalesce((v_fee->>'amount_charge_cents')::int, v_delta_cents);
  v_expires := timezone('utc', now()) + interval '48 hours';

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
    'expires_at', v_expires,
    'band_from', v_charged,
    'band_to', v_band,
    'notification_id', v_nid,
    'c2_email_kind', 'shipping_delta_requested'
  );
end;
$$;

-- Allowlist notify kinds (cliente / trusted)
create or replace function public.batata_emit_user_notification(
  p_recipient_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_chat_id uuid default null,
  p_product_id uuid default null,
  p_offer_id uuid default null,
  p_actor_id uuid default null,
  p_dedupe_key text default null,
  p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_service boolean := public.batata_notify_is_service_role();
  v_actor uuid := coalesce(p_actor_id, v_uid);
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_other uuid;
  v_buyer uuid;
  v_seller uuid;
  v_bundle uuid;
begin
  if v_service then
    return public.batata_emit_user_notification_trusted(
      p_recipient_id, p_kind, p_title, p_body,
      p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
    );
  end if;

  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_recipient_id is null or v_kind = '' then
    raise exception 'invalid_args';
  end if;
  if p_recipient_id = v_uid then
    raise exception 'not_allowed: cannot notify self';
  end if;

  if v_kind in (
    'bundle_proposal',
    'bundle_proposal_counter',
    'bundle_purchase_request',
    'bundle_quote_ready',
    'bundle_expired',
    'bundle_quote_invalidated',
    'chat_message',
    'price_offer_outcome'
  ) then
    if p_chat_id is null then
      raise exception 'chat_id_required';
    end if;
    v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
    if v_other is null or v_other <> p_recipient_id then
      raise exception 'not_allowed: chat party';
    end if;
  elsif v_kind in ('seguro_fleaber_paid', 'order_paid_seller', 'order_paid_buyer') then
    if p_order_id is not null then
      select buyer_id, seller_id into v_buyer, v_seller
      from public.orders where id = p_order_id;
      if v_buyer is null then
        raise exception 'order_not_found';
      end if;
      if v_uid <> v_buyer and v_uid <> v_seller then
        raise exception 'not_allowed: order party';
      end if;
      if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
        raise exception 'not_allowed: recipient not on order';
      end if;
    elsif p_chat_id is not null then
      v_other := public.batata_notify_chat_other_party(p_chat_id, v_uid);
      if v_other is null or v_other <> p_recipient_id then
        raise exception 'not_allowed: chat party';
      end if;
    else
      raise exception 'order_or_chat_required';
    end if;
  elsif v_kind = 'reservation_order_shipped' then
    if p_order_id is null then
      raise exception 'order_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = p_order_id;
    if v_buyer is null or v_uid <> v_seller then
      raise exception 'not_allowed: only seller ships';
    end if;
    if p_recipient_id <> v_buyer then
      raise exception 'not_allowed: ship notify buyer only';
    end if;
  elsif v_kind in ('price_offer', 'price_offer_counter') then
    if p_offer_id is null then
      raise exception 'offer_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.product_offers where id = p_offer_id;
    if v_buyer is null then
      raise exception 'offer_not_found';
    end if;
    if v_uid <> v_buyer and v_uid <> v_seller then
      raise exception 'not_allowed: offer party';
    end if;
    if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
      raise exception 'not_allowed: recipient';
    end if;
  elsif v_kind in (
    'shipping_delta_requested',
    'shipping_delta_paid',
    'shipping_delta_expired_cancelled',
    'ship_deadline_auto_cancelled'
  ) then
    if p_order_id is null then
      raise exception 'order_id_required';
    end if;
    select buyer_id, seller_id into v_buyer, v_seller
    from public.orders where id = p_order_id;
    if v_buyer is null then
      raise exception 'order_not_found';
    end if;
    if v_uid <> v_buyer and v_uid <> v_seller then
      raise exception 'not_allowed: order party';
    end if;
    if p_recipient_id <> v_buyer and p_recipient_id <> v_seller then
      raise exception 'not_allowed: recipient not on order';
    end if;
  else
    raise exception 'kind_not_allowed_for_client';
  end if;

  return public.batata_emit_user_notification_trusted(
    p_recipient_id, p_kind, p_title, p_body,
    p_chat_id, p_product_id, p_offer_id, v_actor, p_dedupe_key
  );
end;
$$;

comment on function public.batata_bundle_seller_confirm_quote(uuid, numeric, text, text, text, text) is
  'ZIP149: vendedora confirma peso/portes → awaiting_payment sem hold de stock.';
comment on function public.batata_bundle_checkout_begin(uuid, text, jsonb) is
  'ZIP149: único caminho de hold+Stripe para conjunto cotado; revalida stock/preço.';
comment on function public.batata_bundle_touch_expiry(uuid) is
  'ZIP149: expira pending>48h no servidor (sem cron permanente).';
