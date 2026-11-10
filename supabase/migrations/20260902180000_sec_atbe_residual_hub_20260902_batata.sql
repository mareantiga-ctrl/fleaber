-- ATBE residual 2026-09-02 — Hub CDN / stock JWT / FOMO «comprou»
-- production_touched: false · fase4: false
-- BATATA: não revogar GRANT stock (Hub); gate dentro da função.
-- Não mexer no player live / Arena carrossel.

-- ===========================================================================
-- BC P2/P3 — hub_lives_public: sem draft/error; VOD só em ended; live play só ao ar
-- ===========================================================================
create or replace view public.hub_lives_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  hp.handle as seller_handle,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  case
    when lower(trim(coalesce(l.status, ''))) = 'live'
         and coalesce(l.is_active, false) = true
      then l.mux_playback_id
    else null
  end as mux_playback_id,
  case
    when lower(trim(coalesce(l.status, ''))) = 'ended'
      then l.mux_vod_playback_id
    else null
  end as mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
join public.hub_profiles_public hp
  on hp.id = coalesce(l.seller_id, l.vendedor_id)
where lower(trim(coalesce(l.status, ''))) in ('scheduled', 'live', 'ended');

comment on view public.hub_lives_public is
  'Lives Hub: scheduled|live|ended apenas. VOD só ended; playback live só live+active. Sem stream keys.';

grant select on public.hub_lives_public to anon, authenticated, service_role;

-- ===========================================================================
-- BC P3 — stock: JWT não-seller também gated fora de broadcasting (como anon)
-- ===========================================================================
create or replace function public.batata_live_item_stock(p_live_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_total integer;
  v_blocked integer := 0;
  v_blocked_orders integer := 0;
  v_blocked_cross_res integer := 0;
  v_reserved_accepted integer := 0;
  v_pending_bag integer := 0;
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_unit_price numeric;
  v_live_only boolean := false;
  v_role text := coalesce(auth.role(), '');
  v_uid uuid := auth.uid();
  v_staff boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_uid is not null and v_seller is not null then
    v_staff := public.batata_staff_has_permission(v_seller, 'can_manage_chat')
      or v_uid = v_seller;
  end if;

  -- Vitrine / oráculo: anon E buyer JWT só vêem stock em broadcasting.
  -- Seller/staff da loja mantêm leitura (gestão pós-live sem partir Hub views: views usam anon).
  if not coalesce(v_staff, false) then
    if not public.batata_live_is_broadcasting(v_li.live_id)
       or coalesce(v_li.quantity, 0) <= 0
       or lower(trim(coalesce(v_li.status, ''))) in (
         'paused', 'inactive', 'sold', 'reserved_full'
       ) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
  end if;

  v_live_only := lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only';

  v_total := public.batata_live_item_total_qty(v_li.id);
  v_product_id := coalesce(v_li.product_id, v_li.checkout_product_id);

  if v_product_id is not null then
    select coalesce(sum(o.quantity), 0)::int into v_blocked_orders
    from public.orders o
    where o.product_id = v_product_id
      and coalesce(o.status, '') not in ('cancelado', 'cancelled', 'rejected', 'expired')
      and lower(trim(coalesce(o.status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'pendente',
        'pedido_devolucao', 'em_devolucao'
      );

    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where r.status in ('pending', 'accepted')
      and li2.id <> v_li.id
      and lower(trim(li2.ref_code)) = lower(trim(v_li.ref_code))
      and coalesce(l2.seller_id, l2.vendedor_id) = v_seller;
  end if;

  v_blocked := v_blocked_orders + v_blocked_cross_res;

  select coalesce(sum(r.requested_qty), 0)::int into v_reserved_accepted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'accepted'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
        and (
          o.live_item_id = v_li.id
          or (
            o.live_id = v_li.live_id
            and v_product_id is not null
            and o.product_id = v_product_id
          )
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_pending_bag
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'pending'
    and r.source = 'fleaber_live'
    and not exists (
      select 1
      from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id
    and r.status = 'converted';

  select coalesce(sum(o.quantity), 0)::int into v_sold_orders
  from public.orders o
  where (
      public.batata_order_status_is_sold_fulfilled(o.status)
      or coalesce(o.stock_units_applied, 0) > 0
    )
    and (
      o.live_item_id = v_li.id
      or (
        o.live_id = v_li.live_id
        and v_product_id is not null
        and o.product_id = v_product_id
      )
    );

  v_sold_converted := greatest(v_sold_converted, v_sold_orders);

  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;

  if v_available < 0 then
    v_available := 0;
  end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p
    where p.id = v_li.product_id;
  else
    v_unit_price := v_li.price;
  end if;

  return jsonb_build_object(
    'ok', true,
    'live_item_id', v_li.id,
    'live_id', v_li.live_id,
    'item_kind', v_li.item_kind,
    'product_id', v_li.product_id,
    'checkout_product_id', v_li.checkout_product_id,
    'ref_code', v_li.ref_code,
    'total_qty', v_total,
    'blocked_qty', v_blocked,
    'reserved_accepted_qty', v_reserved_accepted,
    'pending_bag_qty', v_pending_bag,
    'sold_converted_qty', v_sold_converted,
    'available_qty', v_available,
    'live_status', v_live.status,
    'price', v_unit_price
  );
end;
$$;

grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated, service_role;

-- ===========================================================================
-- AV/BB P3 — system_message não imita anúncio de compra (só purchase_broadcast)
-- ===========================================================================
create or replace function public.batata_live_system_message(
  p_live_id uuid,
  p_body text,
  p_sender_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_seller uuid;
  v_body text := trim(coalesce(p_body, ''));
  v_norm text;
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
begin
  if p_live_id is null or v_body = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;

  if char_length(v_body) > 400 then
    return jsonb_build_object('ok', false, 'error', 'body_too_long');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  -- FOMO compra: só via batata_live_purchase_broadcast (exige order paga)
  v_norm := lower(v_body);
  v_norm := translate(v_norm, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc');
  if v_norm ~ '(comprou|compraram|purchased|bought)'
     or (v_body like '%✅%' and v_norm ~ 'compr') then
    return jsonb_build_object(
      'ok', false,
      'error', 'purchase_announce_via_broadcast_only'
    );
  end if;

  select coalesce(seller_id, vendedor_id) into v_seller
  from public.lives
  where id = p_live_id;

  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_uid is distinct from v_seller
     and not public.batata_staff_has_permission(v_seller, 'can_manage_chat') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  insert into public.batata_rpc_rate_limits (uid, rpc, window_start, hits)
  values (v_uid, 'batata_live_system_message', v_window, 1)
  on conflict (uid, rpc, window_start) do update
  set hits = public.batata_rpc_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 60 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label
  ) values (
    p_live_id,
    v_uid,
    'system',
    v_body,
    coalesce(nullif(trim(p_sender_label), ''), 'Sistema')
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.batata_live_system_message(uuid, text, text)
  from public, anon;
grant execute on function public.batata_live_system_message(uuid, text, text)
  to authenticated, service_role;

notify pgrst, 'reload schema';
