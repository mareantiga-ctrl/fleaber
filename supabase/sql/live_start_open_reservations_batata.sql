-- V1: aviso antes de iniciar directo — reservas/pedidos em aberto por artigo.
-- Executar no SQL Editor (ou incluído em live_ops_hotfix_batata.sql).

create or replace function public.batata_live_start_open_reservations_check(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_result jsonb;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_id_required');
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_seller
  from public.lives l
  where l.id = p_live_id;

  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if not (
    auth.uid() = v_seller
    or public.batata_staff_has_permission(v_seller, 'can_manage_reservations')
    or public.batata_staff_has_permission(v_seller, 'can_view_live_dashboard')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  with catalog as (
    select li.*
    from public.live_items li
    where li.live_id = p_live_id
  ),
  matched_requests as (
    select
      ci.id as catalog_item_id,
      r.id::text as entry_id,
      'live_request'::text as kind,
      r.buyer_id,
      r.status,
      greatest(coalesce(r.requested_qty, 1), 1) as quantity,
      r.queue_position,
      r.created_at,
      r.live_id as source_live_id
    from catalog ci
    join public.live_reservation_requests r
      on r.seller_id = v_seller
     and r.status in ('pending', 'accepted')
     and coalesce(lower(r.notes), '') not like '%bag_removed%'
     and coalesce(lower(r.notes), '') not like '%bag_cancelled%'
    join public.live_items li_src on li_src.id = r.live_item_id
    where public.batata_live_items_lineage_match(ci, li_src)
  ),
  matched_orders as (
    select
      ci.id as catalog_item_id,
      o.id::text as entry_id,
      'order'::text as kind,
      o.buyer_id,
      o.status,
      greatest(coalesce(o.quantity, 1), 1) as quantity,
      null::int as queue_position,
      o.created_at,
      o.live_id as source_live_id
    from catalog ci
    join public.orders o
      on o.seller_id = v_seller
     and lower(trim(coalesce(o.status, ''))) in (
       'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
     )
     and lower(trim(coalesce(o.status, ''))) not in (
       'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
     )
    left join public.live_items li_src on li_src.id = o.live_item_id
    where (
      (ci.product_id is not null and o.product_id = ci.product_id)
      or (
        ci.checkout_product_id is not null
        and o.product_id = ci.checkout_product_id
      )
      or (
        li_src.id is not null
        and public.batata_live_items_lineage_match(ci, li_src)
      )
    )
  ),
  all_matched as (
    select * from matched_requests
    union all
    select * from matched_orders
  ),
  with_meta as (
    select
      am.*,
      coalesce(nullif(trim(p.full_name), ''), 'Comprador') as buyer_name,
      nullif(trim(p.photo_url), '') as buyer_photo_url,
      case
        when am.source_live_id is null then 'Marketplace'
        when exists (
          select 1
          from public.lives lv
          where lv.id = am.source_live_id
            and (
              coalesce(lv.mux_vod_playback_id, lv.mux_playback_id, lv.playback_id, '')
                <> ''
              or lower(coalesce(lv.status, '')) in ('ended')
            )
        ) then 'Gravado'
        when am.source_live_id = p_live_id then 'Este directo'
        else 'Direto anterior'
      end as origin_label
    from all_matched am
    left join public.profiles p on p.id = am.buyer_id
  ),
  item_rows as (
    select
      ci.id as catalog_item_id,
      coalesce(nullif(trim(ci.title), ''), 'Artigo') as title,
      coalesce(nullif(trim(ci.ref_code), ''), '') as ref_code,
      nullif(trim(ci.photo_url), '') as photo_url,
      coalesce((stk->>'available_qty')::int, coalesce(ci.quantity, 1)) as current_stock,
      coalesce(agg.reservation_count, 0) as reservation_count,
      coalesce(agg.reserved_units, 0) as reserved_units,
      coalesce(agg.reservations, '[]'::jsonb) as reservations,
      coalesce(agg.origins, '[]'::jsonb) as origins
    from catalog ci
    left join lateral (
      select public.batata_live_item_stock(ci.id) as stk
    ) s on true
    left join lateral (
      select
        count(*)::int as reservation_count,
        coalesce(sum(wm.quantity), 0)::int as reserved_units,
        jsonb_agg(
          jsonb_build_object(
            'kind', wm.kind,
            'id', wm.entry_id,
            'buyer_id', wm.buyer_id,
            'buyer_name', wm.buyer_name,
            'buyer_photo_url', wm.buyer_photo_url,
            'status', wm.status,
            'quantity', wm.quantity,
            'queue_position', wm.queue_position,
            'created_at', wm.created_at,
            'origin', wm.origin_label
          )
          order by wm.created_at asc nulls last
        ) as reservations,
        (
          select coalesce(jsonb_agg(distinct o.origin_label order by o.origin_label), '[]'::jsonb)
          from (select distinct wm2.origin_label from with_meta wm2 where wm2.catalog_item_id = ci.id) o
        ) as origins
      from with_meta wm
      where wm.catalog_item_id = ci.id
    ) agg on true
    where coalesce(agg.reservation_count, 0) > 0
  ),
  summary as (
    select
      count(*)::int as items_with_open,
      coalesce(sum(reservation_count), 0)::int as total_reservations,
      coalesce(sum(reserved_units), 0)::int as total_units
    from item_rows
  )
  select jsonb_build_object(
    'ok', true,
    'summary', jsonb_build_object(
      'items_with_open', coalesce((select items_with_open from summary), 0),
      'total_reservations', coalesce((select total_reservations from summary), 0),
      'total_units', coalesce((select total_units from summary), 0)
    ),
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'live_item_id', ir.catalog_item_id,
            'title', ir.title,
            'ref_code', ir.ref_code,
            'photo_url', ir.photo_url,
            'current_stock', ir.current_stock,
            'reservation_count', ir.reservation_count,
            'reserved_units', ir.reserved_units,
            'stock_warning', ir.reserved_units >= greatest(ir.current_stock, 1),
            'origins', ir.origins,
            'reservations', ir.reservations
          )
          order by ir.reserved_units desc, ir.title asc
        )
        from item_rows ir
      ),
      '[]'::jsonb
    )
  )
  into v_result;

  return coalesce(v_result, jsonb_build_object('ok', true, 'summary', jsonb_build_object(
    'items_with_open', 0, 'total_reservations', 0, 'total_units', 0
  ), 'items', '[]'::jsonb));
end;
$$;

revoke all on function public.batata_live_start_open_reservations_check(uuid) from public;
grant execute on function public.batata_live_start_open_reservations_check(uuid) to authenticated;
grant execute on function public.batata_live_start_open_reservations_check(uuid) to service_role;

notify pgrst, 'reload schema';
