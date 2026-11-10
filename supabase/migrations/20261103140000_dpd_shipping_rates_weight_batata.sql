-- =============================================================================
-- DPD ZIP 135 — tarifas admin, peso anúncio/encomenda, flags comerciais OFF
-- Aditivo / compatível. NÃO activa create nem cobrança novas tarifas.
-- =============================================================================

-- Tarifas ao comprador (IVA incluído) — editáveis em admin
create table if not exists public.dpd_shipping_rates (
  id uuid primary key default gen_random_uuid(),
  modality text not null
    check (modality in ('shop_to_shop', 'shop_to_home')),
  weight_band text not null
    check (weight_band in ('0_3', '3_6', '6_10')),
  max_kg numeric(6,2) not null,
  price_eur numeric(10,2) not null check (price_eur >= 0),
  active boolean not null default true,
  notes text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  unique (modality, weight_band)
);

comment on table public.dpd_shipping_rates is
  'Portes DPD ao comprador (IVA incl.). Shop2Home só cobrar se DPD_HOME_CHARGES_ENABLED=1.';

insert into public.dpd_shipping_rates (modality, weight_band, max_kg, price_eur, notes)
values
  ('shop_to_shop', '0_3', 3, 2.99, 'Pickup→Pickup até 3 kg'),
  ('shop_to_shop', '3_6', 6, 3.49, 'Pickup→Pickup 3–6 kg'),
  ('shop_to_shop', '6_10', 10, 4.99, 'Pickup→Pickup 6–10 kg'),
  ('shop_to_home', '0_3', 3, 4.49, 'Pickup→Casa até 3 kg — validar combustível antes de activar'),
  ('shop_to_home', '3_6', 6, 5.99, 'Pickup→Casa 3–6 kg — validar combustível antes de activar'),
  ('shop_to_home', '6_10', 10, 8.99, 'Pickup→Casa 6–10 kg — validar combustível antes de activar')
on conflict (modality, weight_band) do update
  set max_kg = excluded.max_kg,
      price_eur = excluded.price_eur,
      notes = excluded.notes,
      updated_at = now();

alter table public.dpd_shipping_rates enable row level security;

drop policy if exists dpd_shipping_rates_select_authenticated on public.dpd_shipping_rates;
create policy dpd_shipping_rates_select_authenticated
  on public.dpd_shipping_rates for select
  to authenticated
  using (active = true or public.batata_is_admin());

drop policy if exists dpd_shipping_rates_admin_write on public.dpd_shipping_rates;
create policy dpd_shipping_rates_admin_write
  on public.dpd_shipping_rates for all
  to authenticated
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

grant select on public.dpd_shipping_rates to authenticated, service_role;
grant insert, update, delete on public.dpd_shipping_rates to service_role;

-- Produtos: peso aproximado OU escalão
alter table public.products
  add column if not exists shipping_weight_kg numeric(8,3),
  add column if not exists shipping_weight_band text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_shipping_weight_band_chk'
  ) then
    alter table public.products
      add constraint products_shipping_weight_band_chk
      check (
        shipping_weight_band is null
        or shipping_weight_band in ('0_3', '3_6', '6_10')
      );
  end if;
end $$;

comment on column public.products.shipping_weight_kg is
  'Peso aproximado kg declarado pelo vendedor (opcional se band preenchido).';
comment on column public.products.shipping_weight_band is
  'Escalão 0_3|3_6|6_10 — se só band, cálculo usa max_kg do escalão.';

-- Encomendas: peso cobrado / consolidado + envio grátis vendedor
alter table public.orders
  add column if not exists shipping_weight_kg numeric(8,3),
  add column if not exists shipping_weight_band text,
  add column if not exists shipping_free_by_seller boolean not null default false,
  add column if not exists shipping_quote_pending boolean not null default false,
  add column if not exists dpd_accept_at timestamptz,
  add column if not exists dpd_delivered_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_shipping_weight_band_chk'
  ) then
    alter table public.orders
      add constraint orders_shipping_weight_band_chk
      check (
        shipping_weight_band is null
        or shipping_weight_band in ('0_3', '3_6', '6_10')
      );
  end if;
end $$;

-- Feature flags (lidas pela app; secrets Edge têm prioridade operacional)
create table if not exists public.fleaber_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  note text
);

alter table public.fleaber_feature_flags enable row level security;

drop policy if exists fleaber_feature_flags_select on public.fleaber_feature_flags;
create policy fleaber_feature_flags_select
  on public.fleaber_feature_flags for select
  to authenticated, anon
  using (true);

drop policy if exists fleaber_feature_flags_admin on public.fleaber_feature_flags;
create policy fleaber_feature_flags_admin
  on public.fleaber_feature_flags for all
  to authenticated
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

insert into public.fleaber_feature_flags (key, enabled, note) values
  ('dpd_create_enabled', false, 'Espelho UI — create real = secret DPD_QA_CREATE_ENABLED'),
  ('dpd_shipping_rates_live', false, 'Cobrar tabela Célia ao comprador — OFF até GO'),
  ('dpd_home_charges_enabled', false, 'Shop2Home tarifas — OFF até validar combustível'),
  ('dpd_tracking_sync_enabled', false, 'Auto sync estados DPD — OFF até GO'),
  ('dpd_return_labels_enabled', false, 'Devoluções DPD API — pendente Rui')
on conflict (key) do nothing;

-- Peso efectivo (kg) a partir de kg exacto ou band
create or replace function public.batata_dpd_effective_weight_kg(
  p_weight_kg numeric,
  p_band text
) returns numeric
language sql
immutable
as $$
  select case
    when p_weight_kg is not null and p_weight_kg > 0 then least(p_weight_kg, 10)
    when p_band = '0_3' then 3::numeric
    when p_band = '3_6' then 6::numeric
    when p_band = '6_10' then 10::numeric
    else null
  end;
$$;

-- Band a partir de kg
create or replace function public.batata_dpd_weight_band(p_kg numeric)
returns text
language sql
immutable
as $$
  select case
    when p_kg is null or p_kg <= 0 then null
    when p_kg <= 3 then '0_3'
    when p_kg <= 6 then '3_6'
    when p_kg <= 10 then '6_10'
    else 'over_10'
  end;
$$;

-- Quote portes (servidor). Respeita flags; free shipping; teto 10 kg.
create or replace function public.batata_dpd_quote_shipping(
  p_modality text,
  p_weight_kg numeric default null,
  p_band text default null,
  p_free_by_seller boolean default false
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_kg numeric;
  v_band text;
  v_rates_live boolean;
  v_home_ok boolean;
  v_price numeric;
  v_legacy numeric := 3.50;
begin
  if p_free_by_seller then
    return jsonb_build_object(
      'ok', true,
      'price_eur', 0,
      'free_by_seller', true,
      'modality', p_modality
    );
  end if;

  select enabled into v_rates_live
  from public.fleaber_feature_flags
  where key = 'dpd_shipping_rates_live';
  v_rates_live := coalesce(v_rates_live, false);

  select enabled into v_home_ok
  from public.fleaber_feature_flags
  where key = 'dpd_home_charges_enabled';
  v_home_ok := coalesce(v_home_ok, false);

  if p_modality not in ('shop_to_shop', 'shop_to_home', 'carrier') then
    return jsonb_build_object('ok', false, 'error', 'invalid_modality');
  end if;

  if p_modality = 'carrier' then
    p_modality := 'shop_to_home'; -- default; checkout deve enviar S2S/S2H
  end if;

  v_kg := public.batata_dpd_effective_weight_kg(p_weight_kg, p_band);
  if v_kg is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'weight_required',
      'message', 'Indica peso ou escalão (máx. 10 kg).'
    );
  end if;

  if v_kg > 10 then
    return jsonb_build_object(
      'ok', false,
      'error', 'over_10kg',
      'message', 'Envio DPD indisponível acima de 10 kg por expedição.'
    );
  end if;

  v_band := public.batata_dpd_weight_band(v_kg);
  if v_band = 'over_10' then
    return jsonb_build_object('ok', false, 'error', 'over_10kg');
  end if;

  -- Até GO comercial: devolver legado 3,50 + metadados da tabela
  if not v_rates_live then
    return jsonb_build_object(
      'ok', true,
      'price_eur', v_legacy,
      'legacy', true,
      'rates_live', false,
      'modality', p_modality,
      'weight_kg', v_kg,
      'weight_band', v_band,
      'note', 'DPD_SHIPPING_RATES_LIVE off — a cobrar 3,50 € legado'
    );
  end if;

  if p_modality = 'shop_to_home' and not v_home_ok then
    return jsonb_build_object(
      'ok', false,
      'error', 'home_charges_disabled',
      'message', 'Entrega ao domicílio DPD ainda não activada (validação combustível).'
    );
  end if;

  select price_eur into v_price
  from public.dpd_shipping_rates
  where modality = p_modality
    and weight_band = v_band
    and active = true
  limit 1;

  if v_price is null then
    return jsonb_build_object('ok', false, 'error', 'rate_missing');
  end if;

  return jsonb_build_object(
    'ok', true,
    'price_eur', v_price,
    'legacy', false,
    'rates_live', true,
    'modality', p_modality,
    'weight_kg', v_kg,
    'weight_band', v_band
  );
end;
$$;

revoke all on function public.batata_dpd_quote_shipping(text, numeric, text, boolean)
  from public, anon;
grant execute on function public.batata_dpd_quote_shipping(text, numeric, text, boolean)
  to authenticated, service_role;

-- Admin: listar expedições / erros DPD
create or replace function public.batata_admin_dpd_expeditions(
  p_limit int default 50
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null or not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.dpd_created_at desc nulls last), '[]'::jsonb)
  into v_rows
  from (
    select
      id,
      status,
      seller_id,
      buyer_id,
      dpd_service,
      dpd_tracking_code,
      dpd_expedition_id,
      dpd_label_url,
      dpd_last_error,
      dpd_created_at,
      dpd_accept_at,
      dpd_delivered_at,
      shipping_weight_kg,
      shipping_free_by_seller,
      created_at
    from public.orders
    where dpd_tracking_code is not null
       or dpd_last_error is not null
       or dpd_created_at is not null
    order by coalesce(dpd_created_at, created_at) desc
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) t;
  return jsonb_build_object('ok', true, 'rows', v_rows);
end;
$$;

revoke all on function public.batata_admin_dpd_expeditions(int) from public, anon;
grant execute on function public.batata_admin_dpd_expeditions(int)
  to authenticated, service_role;
