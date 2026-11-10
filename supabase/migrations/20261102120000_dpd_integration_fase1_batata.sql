-- =============================================================================
-- DPD integração fase 1 — BATATA
-- Pickup selection + metadados expedição. NÃO activa create Live.
-- Compatível / aditivo. Não toca Stripe ZIP 128.
-- =============================================================================

alter table public.orders
  add column if not exists dpd_service text,
  add column if not exists dpd_expedition_id text,
  add column if not exists dpd_tracking_code text,
  add column if not exists dpd_label_url text,
  add column if not exists dpd_last_error text,
  add column if not exists dpd_created_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_dpd_service_chk'
  ) then
    alter table public.orders
      add constraint orders_dpd_service_chk
      check (
        dpd_service is null
        or dpd_service in ('shop_to_shop', 'shop_to_home')
      );
  end if;
end $$;

comment on column public.orders.dpd_service is
  'shop_to_shop (03546101) | shop_to_home (03546102)';
comment on column public.orders.delivery_point_ref is
  'PUDO_ID MyPudo quando delivery_point_provider=dpd_pickup';

-- RPC: gravar escolha Pickup no checkout (antes do freeze de snapshot)
create or replace function public.batata_set_order_delivery_pickup(
  p_order_id uuid,
  p_pudo_id text,
  p_label text,
  p_address1 text default null,
  p_zip text default null,
  p_city text default null,
  p_country text default 'PT'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  if p_order_id is null or nullif(trim(p_pudo_id), '') is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_args');
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.buyer_id is distinct from v_uid
     and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if v_order.delivery_snapshot_at is not null then
    return jsonb_build_object('ok', false, 'error', 'snapshot_frozen');
  end if;
  if lower(coalesce(v_order.status, '')) in (
    'enviado', 'concluido', 'entregue', 'cancelado', 'cancelled', 'devolvida'
  ) then
    return jsonb_build_object('ok', false, 'error', 'status_blocked');
  end if;

  update public.orders
  set
    delivery_point_ref = trim(p_pudo_id),
    delivery_point_provider = 'dpd_pickup',
    delivery_point_label = coalesce(nullif(trim(p_label), ''), trim(p_pudo_id)),
    delivery_line1 = coalesce(nullif(trim(p_address1), ''), delivery_line1),
    delivery_postal_code = coalesce(nullif(trim(p_zip), ''), delivery_postal_code),
    delivery_city = coalesce(nullif(trim(p_city), ''), delivery_city),
    delivery_country = coalesce(nullif(trim(p_country), ''), delivery_country, 'PT'),
    dpd_service = 'shop_to_shop',
    shipping_method = coalesce(nullif(trim(shipping_method), ''), 'carrier')
  where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'delivery_point_ref', trim(p_pudo_id),
    'dpd_service', 'shop_to_shop'
  );
end;
$$;

revoke all on function public.batata_set_order_delivery_pickup(
  uuid, text, text, text, text, text, text
) from public, anon;
grant execute on function public.batata_set_order_delivery_pickup(
  uuid, text, text, text, text, text, text
) to authenticated, service_role;

-- Home explícito (limpa pickup)
create or replace function public.batata_set_order_delivery_home(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'auth_required');
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_order.buyer_id is distinct from v_uid
     and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if v_order.delivery_snapshot_at is not null then
    return jsonb_build_object('ok', false, 'error', 'snapshot_frozen');
  end if;

  update public.orders
  set
    delivery_point_ref = null,
    delivery_point_provider = 'home',
    delivery_point_label = null,
    dpd_service = 'shop_to_home',
    shipping_method = coalesce(nullif(trim(shipping_method), ''), 'carrier')
  where id = p_order_id;

  return jsonb_build_object('ok', true, 'dpd_service', 'shop_to_home');
end;
$$;

revoke all on function public.batata_set_order_delivery_home(uuid)
  from public, anon;
grant execute on function public.batata_set_order_delivery_home(uuid)
  to authenticated, service_role;
