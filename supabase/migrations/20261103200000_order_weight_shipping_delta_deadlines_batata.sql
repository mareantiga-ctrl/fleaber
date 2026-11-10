-- =============================================================================
-- ZIP 140 — Peso / diferença portes / prazos envio (5 dias úteis) / flags OFF
-- Aditivo. NÃO activa cron comercial nem DPD create. Reversível via 90-rollback.
-- =============================================================================

-- Feature flags (default OFF — GO separado)
insert into public.fleaber_feature_flags (key, enabled, note)
values
  ('order_weight_confirm_enabled', false,
   'ZIP140: fase 3 dias confirmação peso após pago'),
  ('order_shipping_delta_enabled', false,
   'ZIP140: vendedor solicita diferença portes + PI Stripe separado'),
  ('order_ship_deadline_enabled', false,
   'ZIP140: prazo expedição 5 dias úteis'),
  ('order_ship_deadline_autocancel_enabled', false,
   'ZIP140: auto-cancel por prazo envio / delta 48h — OFF até GO')
on conflict (key) do update
  set note = excluded.note,
      updated_at = now();

-- Colunas orders (auxiliares — não substituem status machine)
alter table public.orders
  add column if not exists shipping_weight_charged_kg numeric(8,3),
  add column if not exists shipping_weight_charged_band text,
  add column if not exists shipping_weight_actual_kg numeric(8,3),
  add column if not exists shipping_weight_actual_band text,
  add column if not exists shipping_modality text,
  add column if not exists shipping_cents_charged integer,
  add column if not exists weight_confirm_deadline_at timestamptz,
  add column if not exists weight_confirmed_at timestamptz,
  add column if not exists weight_confirm_status text,
  add column if not exists ship_by_at timestamptz,
  add column if not exists ship_clock_paused_at timestamptz,
  add column if not exists ship_deadline_paused_remaining_seconds integer,
  add column if not exists shipping_delta_status text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_shipping_weight_charged_band_chk'
  ) then
    alter table public.orders add constraint orders_shipping_weight_charged_band_chk
      check (
        shipping_weight_charged_band is null
        or shipping_weight_charged_band in ('0_3', '3_6', '6_10')
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'orders_shipping_weight_actual_band_chk'
  ) then
    alter table public.orders add constraint orders_shipping_weight_actual_band_chk
      check (
        shipping_weight_actual_band is null
        or shipping_weight_actual_band in ('0_3', '3_6', '6_10')
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'orders_shipping_modality_chk'
  ) then
    alter table public.orders add constraint orders_shipping_modality_chk
      check (
        shipping_modality is null
        or shipping_modality in ('shop_to_shop', 'shop_to_home', 'hand')
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'orders_weight_confirm_status_chk'
  ) then
    alter table public.orders add constraint orders_weight_confirm_status_chk
      check (
        weight_confirm_status is null
        or weight_confirm_status in (
          'not_required', 'pending', 'confirmed_same', 'assumed_by_seller',
          'delta_requested', 'delta_paid', 'expired'
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'orders_shipping_delta_status_chk'
  ) then
    alter table public.orders add constraint orders_shipping_delta_status_chk
      check (
        shipping_delta_status is null
        or shipping_delta_status in (
          'none', 'pending', 'paid', 'assumed', 'expired', 'cancelled'
        )
      );
  end if;
end $$;

comment on column public.orders.shipping_weight_charged_band is
  'Escalão cobrado ao comprador no checkout (selo).';
comment on column public.orders.shipping_weight_actual_band is
  'Escalão confirmado pelo vendedor (pesagem).';
comment on column public.orders.ship_by_at is
  'Deadline expedição (5 dias úteis) — pausável durante delta.';
comment on column public.orders.weight_confirm_deadline_at is
  'Fim dos 3 dias para confirmar peso após pago.';

-- Ajustes de portes (PI Stripe separado)
create table if not exists public.order_shipping_adjustments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'assumed', 'expired', 'cancelled')),
  band_from text not null check (band_from in ('0_3', '3_6', '6_10')),
  band_to text not null check (band_to in ('0_3', '3_6', '6_10')),
  modality text not null check (modality in ('shop_to_shop', 'shop_to_home')),
  shipping_delta_cents integer not null check (shipping_delta_cents >= 0),
  stripe_fee_grossup_cents integer not null default 0 check (stripe_fee_grossup_cents >= 0),
  amount_charge_cents integer not null check (amount_charge_cents >= 0),
  currency text not null default 'eur',
  buyer_id uuid not null references auth.users(id),
  seller_id uuid not null references auth.users(id),
  expires_at timestamptz not null,
  stripe_checkout_session_id text,
  stripe_payment_intent_id text,
  stripe_refund_id text,
  paid_at timestamptz,
  assumed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Um único pending activo por encomenda
create unique index if not exists order_shipping_adj_one_pending_uidx
  on public.order_shipping_adjustments (order_id)
  where status = 'pending';

create index if not exists order_shipping_adj_expires_idx
  on public.order_shipping_adjustments (expires_at)
  where status = 'pending';

alter table public.order_shipping_adjustments enable row level security;

drop policy if exists order_shipping_adj_select_parties on public.order_shipping_adjustments;
create policy order_shipping_adj_select_parties
  on public.order_shipping_adjustments for select
  to authenticated
  using (
    buyer_id = auth.uid() or seller_id = auth.uid() or public.batata_is_admin()
  );

grant select on public.order_shipping_adjustments to authenticated, service_role;
grant insert, update, delete on public.order_shipping_adjustments to service_role;

-- Feriados PT (mínimo 2026–2027) para dias úteis
create table if not exists public.fleaber_pt_holidays (
  holiday_date date primary key,
  name text not null
);

insert into public.fleaber_pt_holidays (holiday_date, name) values
  ('2026-01-01', 'Ano Novo'),
  ('2026-04-03', 'Sexta Santa'),
  ('2026-04-05', 'Páscoa'),
  ('2026-04-25', 'Liberdade'),
  ('2026-05-01', 'Trabalhador'),
  ('2026-06-10', 'Portugal'),
  ('2026-06-11', 'Corpo de Deus'),
  ('2026-08-15', 'Assunção'),
  ('2026-10-05', 'Implantação República'),
  ('2026-11-01', 'Todos os Santos'),
  ('2026-12-01', 'Restauração'),
  ('2026-12-08', 'Imaculada'),
  ('2026-12-25', 'Natal'),
  ('2027-01-01', 'Ano Novo'),
  ('2027-03-26', 'Sexta Santa'),
  ('2027-03-28', 'Páscoa'),
  ('2027-04-25', 'Liberdade'),
  ('2027-05-01', 'Trabalhador'),
  ('2027-06-10', 'Portugal'),
  ('2027-08-15', 'Assunção'),
  ('2027-10-05', 'Implantação República'),
  ('2027-11-01', 'Todos os Santos'),
  ('2027-12-01', 'Restauração'),
  ('2027-12-08', 'Imaculada'),
  ('2027-12-25', 'Natal')
on conflict (holiday_date) do nothing;

grant select on public.fleaber_pt_holidays to authenticated, service_role;

create or replace function public.batata_is_pt_business_day(p_day date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select extract(isodow from p_day) < 6
    and not exists (
      select 1 from public.fleaber_pt_holidays h where h.holiday_date = p_day
    );
$$;

create or replace function public.batata_add_business_days(
  p_from timestamptz,
  p_days integer
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_day date := (p_from at time zone 'Europe/Lisbon')::date;
  v_left integer := greatest(p_days, 0);
  v_guard integer := 0;
begin
  if p_days is null or p_days <= 0 then
    return p_from;
  end if;
  while v_left > 0 loop
    v_day := v_day + 1;
    v_guard := v_guard + 1;
    if v_guard > 400 then
      raise exception 'batata_add_business_days_guard';
    end if;
    if public.batata_is_pt_business_day(v_day) then
      v_left := v_left - 1;
    end if;
  end loop;
  -- fim do dia útil em Lisbon → timestamptz
  return ((v_day::text || ' 23:59:59')::timestamp
    at time zone 'Europe/Lisbon');
end;
$$;

revoke all on function public.batata_is_pt_business_day(date) from public, anon;
revoke all on function public.batata_add_business_days(timestamptz, integer) from public, anon;
grant execute on function public.batata_is_pt_business_day(date) to authenticated, service_role;
grant execute on function public.batata_add_business_days(timestamptz, integer) to authenticated, service_role;

create or replace function public.batata_flag_enabled(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select enabled from public.fleaber_feature_flags where key = p_key),
    false
  );
$$;

grant execute on function public.batata_flag_enabled(text) to authenticated, service_role;

-- Ao passar a pago: iniciar relógios se flags ON
create or replace function public.batata_orders_on_paid_shipping_clocks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hand boolean;
begin
  if tg_op <> 'UPDATE' then return new; end if;
  if lower(coalesce(new.status, '')) not in ('pago', 'premio_rifa') then
    return new;
  end if;
  if lower(coalesce(old.status, '')) in ('pago', 'premio_rifa', 'enviado', 'entregue', 'concluido') then
    return new;
  end if;

  v_hand := lower(coalesce(new.shipping_method, '')) in (
    'hand', 'mao', 'mão', 'entrega em mão', 'entrega em mao'
  ) or coalesce(new.shipping_modality, '') = 'hand';

  if v_hand then
    new.weight_confirm_status := coalesce(new.weight_confirm_status, 'not_required');
    new.shipping_delta_status := coalesce(new.shipping_delta_status, 'none');
    return new;
  end if;

  if public.batata_flag_enabled('order_weight_confirm_enabled') then
    if new.weight_confirm_deadline_at is null then
      new.weight_confirm_deadline_at := now() + interval '3 days';
    end if;
    new.weight_confirm_status := coalesce(new.weight_confirm_status, 'pending');
  else
    new.weight_confirm_status := coalesce(new.weight_confirm_status, 'not_required');
  end if;

  if public.batata_flag_enabled('order_ship_deadline_enabled')
     and new.ship_by_at is null
     and coalesce(new.weight_confirm_status, 'not_required') in ('not_required', 'confirmed_same', 'assumed_by_seller', 'delta_paid')
  then
    -- Se confirmação peso activa e ainda pending, ship_by só após resolução
    if coalesce(new.weight_confirm_status, '') = 'pending'
       and public.batata_flag_enabled('order_weight_confirm_enabled') then
      null;
    else
      new.ship_by_at := public.batata_add_business_days(now(), 5);
    end if;
  end if;

  new.shipping_delta_status := coalesce(new.shipping_delta_status, 'none');
  return new;
end;
$$;

drop trigger if exists trg_orders_on_paid_shipping_clocks on public.orders;
create trigger trg_orders_on_paid_shipping_clocks
  before update of status on public.orders
  for each row
  execute function public.batata_orders_on_paid_shipping_clocks();

-- Pausar / retomar relógio de envio
create or replace function public.batata_ship_clock_pause(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_rem integer;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.ship_by_at is null then
    return jsonb_build_object('ok', true, 'paused', false, 'reason', 'no_ship_by');
  end if;
  if v_order.ship_clock_paused_at is not null then
    return jsonb_build_object('ok', true, 'paused', true, 'already', true);
  end if;
  v_rem := greatest(0, extract(epoch from (v_order.ship_by_at - now()))::int);
  update public.orders set
    ship_clock_paused_at = now(),
    ship_deadline_paused_remaining_seconds = v_rem
  where id = p_order_id;
  return jsonb_build_object('ok', true, 'paused', true, 'remaining_seconds', v_rem);
end;
$$;

create or replace function public.batata_ship_clock_resume(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_rem integer;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.ship_clock_paused_at is null then
    -- se ainda não tinha ship_by (esperava peso), arrancar 5 dias úteis
    if v_order.ship_by_at is null
       and public.batata_flag_enabled('order_ship_deadline_enabled') then
      update public.orders set
        ship_by_at = public.batata_add_business_days(now(), 5)
      where id = p_order_id;
      return jsonb_build_object('ok', true, 'started', true);
    end if;
    return jsonb_build_object('ok', true, 'paused', false);
  end if;
  v_rem := coalesce(v_order.ship_deadline_paused_remaining_seconds, 0);
  update public.orders set
    ship_by_at = now() + make_interval(secs => v_rem),
    ship_clock_paused_at = null,
    ship_deadline_paused_remaining_seconds = null
  where id = p_order_id;
  return jsonb_build_object('ok', true, 'resumed', true, 'ship_by_at', now() + make_interval(secs => v_rem));
end;
$$;

revoke all on function public.batata_ship_clock_pause(uuid) from public, anon;
revoke all on function public.batata_ship_clock_resume(uuid) from public, anon;
grant execute on function public.batata_ship_clock_pause(uuid) to service_role;
grant execute on function public.batata_ship_clock_resume(uuid) to service_role;

-- Seller: confirmar peso / assumir / solicitar delta
create or replace function public.batata_seller_confirm_shipping_weight(
  p_order_id uuid,
  p_actual_kg numeric default null,
  p_actual_band text default null,
  p_action text default 'confirm' -- confirm | assume | request_delta
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
  v_fee_fixed integer := 25; -- 0,25 € Stripe EU card (configurável via nota; Edge pode recalcular)
  v_fee_bps integer := 150; -- 1,5%
  v_charge integer;
  v_grossup integer;
  v_adj_id uuid;
  v_flag_w boolean;
  v_flag_d boolean;
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

  -- Mesmo escalão
  if v_band = v_charged or p_action = 'confirm' and v_band = v_charged then
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
      -- peso inferior ou igual em preço → tratar como same
      update public.orders set weight_confirm_status = 'confirmed_same', shipping_delta_status = 'none'
      where id = p_order_id;
      perform public.batata_ship_clock_resume(p_order_id);
      return jsonb_build_object('ok', true, 'result', 'confirmed_same', 'note', 'no_price_increase');
    end if;
    v_delta_cents := round((v_price_to - v_price_from) * 100)::int;
    -- gross-up: charge = ceil((delta + fixed) / (1 - pct))
    v_charge := ceil(((v_delta_cents + v_fee_fixed)::numeric * 10000)
      / (10000 - v_fee_bps))::int;
    v_grossup := v_charge - v_delta_cents;

    insert into public.order_shipping_adjustments (
      order_id, status, band_from, band_to, modality,
      shipping_delta_cents, stripe_fee_grossup_cents, amount_charge_cents,
      buyer_id, seller_id, expires_at
    ) values (
      p_order_id, 'pending', v_charged, v_band, v_modality,
      v_delta_cents, v_grossup, v_charge,
      v_order.buyer_id, v_order.seller_id, now() + interval '48 hours'
    ) returning id into v_adj_id;

    update public.orders set
      weight_confirm_status = 'delta_requested',
      shipping_delta_status = 'pending'
    where id = p_order_id;

    perform public.batata_ship_clock_pause(p_order_id);

    return jsonb_build_object(
      'ok', true,
      'result', 'delta_requested',
      'adjustment_id', v_adj_id,
      'shipping_delta_cents', v_delta_cents,
      'stripe_fee_grossup_cents', v_grossup,
      'amount_charge_cents', v_charge,
      'expires_at', now() + interval '48 hours',
      'band_from', v_charged,
      'band_to', v_band
    );
  end if;

  return jsonb_build_object('ok', false, 'error', 'invalid_action');
end;
$$;

revoke all on function public.batata_seller_confirm_shipping_weight(uuid, numeric, text, text)
  from public, anon;
grant execute on function public.batata_seller_confirm_shipping_weight(uuid, numeric, text, text)
  to authenticated, service_role;

-- Marcar adjustment pago (só service_role / webhook)
create or replace function public.batata_mark_shipping_adjustment_paid(
  p_adjustment_id uuid,
  p_payment_intent_id text,
  p_checkout_session_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adj public.order_shipping_adjustments%rowtype;
begin
  select * into v_adj from public.order_shipping_adjustments
  where id = p_adjustment_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_adj.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;
  if v_adj.status <> 'pending' then
    return jsonb_build_object('ok', false, 'error', 'status_blocked', 'status', v_adj.status);
  end if;

  update public.order_shipping_adjustments set
    status = 'paid',
    paid_at = now(),
    stripe_payment_intent_id = p_payment_intent_id,
    stripe_checkout_session_id = coalesce(p_checkout_session_id, stripe_checkout_session_id),
    updated_at = now()
  where id = p_adjustment_id;

  update public.orders set
    shipping_delta_status = 'paid',
    weight_confirm_status = 'delta_paid',
    shipping_weight_charged_band = v_adj.band_to,
    shipping_cents_charged = coalesce(shipping_cents_charged, 0) + v_adj.shipping_delta_cents
  where id = v_adj.order_id;

  perform public.batata_ship_clock_resume(v_adj.order_id);

  return jsonb_build_object('ok', true, 'order_id', v_adj.order_id);
end;
$$;

revoke all on function public.batata_mark_shipping_adjustment_paid(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_mark_shipping_adjustment_paid(uuid, text, text)
  to service_role;

-- Expirar deltas 48h + prazos envio (chamada manual/cron futuro — NÃO agenda aqui)
create or replace function public.batata_expire_shipping_deltas_and_deadlines(
  p_now timestamptz default timezone('utc', now()),
  p_limit integer default 40
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auto boolean := public.batata_flag_enabled('order_ship_deadline_autocancel_enabled');
  r record;
  v_n_delta integer := 0;
  v_n_ship integer := 0;
  v_ids uuid[] := '{}';
begin
  if not v_auto then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'order_ship_deadline_autocancel_enabled=false'
    );
  end if;

  for r in
    select a.* from public.order_shipping_adjustments a
    where a.status = 'pending' and a.expires_at <= p_now
    order by a.expires_at
    limit greatest(p_limit, 1)
    for update skip locked
  loop
    update public.order_shipping_adjustments set
      status = 'expired', cancelled_at = p_now, cancel_reason = 'buyer_48h_expired',
      updated_at = p_now
    where id = r.id;
    update public.orders set
      shipping_delta_status = 'expired',
      weight_confirm_status = 'expired'
    where id = r.order_id and lower(coalesce(status, '')) in ('pago', 'premio_rifa');
    -- Cancel + refund fica a cargo Edge service (lista de IDs)
    v_ids := array_append(v_ids, r.order_id);
    v_n_delta := v_n_delta + 1;
  end loop;

  for r in
    select o.id from public.orders o
    where public.batata_flag_enabled('order_ship_deadline_enabled')
      and o.ship_by_at is not null
      and o.ship_clock_paused_at is null
      and o.ship_by_at <= p_now
      and lower(coalesce(o.status, '')) in ('pago', 'premio_rifa')
    order by o.ship_by_at
    limit greatest(p_limit, 1)
    for update skip locked
  loop
    v_ids := array_append(v_ids, r.id);
    v_n_ship := v_n_ship + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'delta_expired', v_n_delta,
    'ship_overdue', v_n_ship,
    'order_ids_need_refund_cancel', to_jsonb(v_ids)
  );
end;
$$;

revoke all on function public.batata_expire_shipping_deltas_and_deadlines(timestamptz, integer)
  from public, anon, authenticated;
grant execute on function public.batata_expire_shipping_deltas_and_deadlines(timestamptz, integer)
  to service_role;

-- Gate DPD: diferença pendente?
create or replace function public.batata_order_blocks_dpd_create(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pending boolean;
begin
  select exists (
    select 1 from public.order_shipping_adjustments a
    where a.order_id = p_order_id and a.status = 'pending'
  ) into v_pending;
  if v_pending then
    return jsonb_build_object(
      'blocked', true,
      'error', 'shipping_delta_unpaid',
      'message', 'Há uma diferença de portes por pagar — etiqueta bloqueada.'
    );
  end if;
  if exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and coalesce(o.weight_confirm_status, '') = 'pending'
      and public.batata_flag_enabled('order_weight_confirm_enabled')
  ) then
    return jsonb_build_object(
      'blocked', true,
      'error', 'weight_confirm_pending',
      'message', 'Confirma o peso da encomenda antes de criar a etiqueta.'
    );
  end if;
  return jsonb_build_object('blocked', false);
end;
$$;

grant execute on function public.batata_order_blocks_dpd_create(uuid)
  to authenticated, service_role;

comment on function public.batata_expire_shipping_deltas_and_deadlines(timestamptz, integer) is
  'ZIP140: NÃO agendar pg_cron até GO order_ship_deadline_autocancel_enabled.';
