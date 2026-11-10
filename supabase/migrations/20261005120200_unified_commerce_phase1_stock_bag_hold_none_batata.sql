-- =============================================================================
-- BATATA 2026-10-05 — Unified commerce Fase 1: stock respects bag_hold_none
-- Preserves: pending same-item does NOT reduce available; accepted DOES.
-- Change: bag_hold_none pending excluded from cross-item blocked_qty.
-- =============================================================================

create or replace function public.batata_lrr_counts_in_cross_block(
  p_status text,
  p_request_kind text
)
returns boolean
language sql
immutable
as $$
  select case
    when lower(trim(coalesce(p_status, ''))) = 'accepted' then true
    when lower(trim(coalesce(p_status, ''))) = 'pending'
      and coalesce(nullif(trim(p_request_kind), ''), 'approval_pending')
          is distinct from 'bag_hold_none'
      then true
    else false
  end;
$$;

comment on function public.batata_lrr_counts_in_cross_block(text, text) is
  'Cross-item stock block: accepted always; pending approval yes; bag_hold_none no.';

grant execute on function public.batata_lrr_counts_in_cross_block(text, text)
  to anon, authenticated, service_role;

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
  v_uid uuid := auth.uid();
  v_staff boolean := false;
  v_lineage uuid;
  v_hub boolean := false;
  v_buyer_bag boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  v_lineage := coalesce(v_li.logical_item_id, v_li.id);

  if v_uid is not null and v_seller is not null then
    v_staff := public.batata_staff_has_permission(v_seller, 'can_manage_chat')
      or v_uid = v_seller;
  end if;

  if v_uid is not null then
    select exists (
      select 1
      from public.live_reservation_requests r
      where r.live_item_id = v_li.id
        and r.buyer_id = v_uid
        and r.status in ('pending', 'accepted')
    ) into v_buyer_bag;
  end if;

  select coalesce(p.hub_published, false) into v_hub
  from public.profiles p where p.id = v_seller;

  if not coalesce(v_staff, false) then
    if not coalesce(v_hub, false) then
      return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
    end if;
    if not coalesce(v_buyer_bag, false) then
      if not public.batata_live_is_broadcasting(v_li.live_id)
         or lower(trim(coalesce(v_li.status, ''))) in (
           'paused', 'inactive', 'sold', 'reserved_full'
         ) then
        return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
      end if;
      if lower(trim(coalesce(v_li.item_kind, ''))) = 'live_only'
         and coalesce(v_li.quantity, 0) <= 0 then
        return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
      end if;
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
    where public.batata_lrr_counts_in_cross_block(r.status, r.request_kind)
      and li2.id <> v_li.id
      and coalesce(li2.product_id, li2.checkout_product_id) = v_product_id;

    if v_live_only and v_lineage is not null then
      select coalesce(sum(r.requested_qty), 0)::int
      into v_blocked_cross_res
      from public.live_reservation_requests r
      join public.live_items li2 on li2.id = r.live_item_id
      where public.batata_lrr_counts_in_cross_block(r.status, r.request_kind)
        and li2.id <> v_li.id
        and (
          coalesce(li2.product_id, li2.checkout_product_id) = v_product_id
          or coalesce(li2.logical_item_id, li2.id) = v_lineage
        );
    end if;
  elsif v_live_only and v_lineage is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    where public.batata_lrr_counts_in_cross_block(r.status, r.request_kind)
      and li2.id <> v_li.id
      and coalesce(li2.logical_item_id, li2.id) = v_lineage;
  elsif v_seller is not null
    and v_li.ref_code is not null
    and trim(v_li.ref_code) <> '' then
    select coalesce(sum(r.requested_qty), 0)::int into v_blocked_cross_res
    from public.live_reservation_requests r
    join public.live_items li2 on li2.id = r.live_item_id
    join public.lives l2 on l2.id = li2.live_id
    where public.batata_lrr_counts_in_cross_block(r.status, r.request_kind)
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
      select 1 from public.orders o
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
    and r.source in ('fleaber_live', 'facebook_manual', 'helper_manual')
    and not exists (
      select 1 from public.orders o
      where o.buyer_id = r.buyer_id
        and o.live_item_id = v_li.id
        and (
          public.batata_order_status_is_sold_fulfilled(o.status)
          or coalesce(o.stock_units_applied, 0) > 0
        )
    );

  select coalesce(sum(r.requested_qty), 0)::int into v_sold_converted
  from public.live_reservation_requests r
  where r.live_item_id = v_li.id and r.status = 'converted';

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
  -- Same-item pending still does NOT enter available (informative pending_bag only)
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;
  if v_available < 0 then v_available := 0; end if;

  if v_li.product_id is not null then
    select coalesce(nullif(v_li.price, 0), p.price) into v_unit_price
    from public.products p where p.id = v_li.product_id;
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

comment on function public.batata_live_item_stock(uuid) is
  'Stock live Fase1: pending same-item informativo; accepted hold; bag_hold_none fora do cross-block.';

notify pgrst, 'reload schema';
