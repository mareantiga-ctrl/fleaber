-- =============================================================================
-- BATATA 2026-10-05 — Phase 3: omnichannel seller bag foundation
-- Evolves live_reservation_requests as canonical bag lines (no parallel cart).
-- Does NOT reopen Phase 2 reservation engine semantics.
-- Does NOT implement Phase 4 checkout mini-lock.
-- Staging only. Additive. Production unchanged.
-- =============================================================================

-- source_channel: internal metadata (not a separate bag).
alter table public.live_reservation_requests
  add column if not exists source_channel text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_source_channel_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_source_channel_chk
      check (
        source_channel is null
        or source_channel in (
          'fleaber_live',
          'marketplace',
          'facebook_psreader',
          'facebook_meta'
        )
      );
  end if;
end $$;

-- Backfill from existing source / ingest (best-effort; do not invent Meta).
update public.live_reservation_requests
set source_channel = case
  when lower(trim(coalesce(source, ''))) = 'fleaber_live' then 'fleaber_live'
  when lower(trim(coalesce(source, ''))) in ('facebook_manual', 'helper_manual')
    then 'facebook_psreader'
  else coalesce(source_channel, 'fleaber_live')
end
where source_channel is null;

comment on column public.live_reservation_requests.source_channel is
  'Phase 3 omnichannel metadata. Does not split bags. Seller boundary remains seller_id.';

-- ---------------------------------------------------------------------------
-- Qty: guaranteed lines cannot silently grow/shrink blocked stock via bag UI.
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_bag_update_qty(
  p_request_id uuid,
  p_qty integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_qty int;
  v_avail int := 0;
  v_snap jsonb;
  v_kind text;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if auth.uid() is null
     or auth.uid() <> v_req.buyer_id
     or v_req.source <> 'fleaber_live'
     or v_req.status not in ('pending', 'accepted') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if p_qty is null or p_qty < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  if p_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'qty_too_high');
  end if;

  v_kind := coalesce(nullif(trim(v_req.request_kind), ''), 'approval_pending');

  -- Guaranteed hold qty is owned by the reservation engine — not bag steppers.
  if v_req.status = 'accepted'
     and v_kind = 'guaranteed'
     and p_qty is distinct from v_req.requested_qty then
    return jsonb_build_object(
      'ok', false,
      'error', 'guaranteed_qty_immutable',
      'hint', 'quantity_changes_must_use_reservation_engine',
      'requested_qty', v_req.requested_qty
    );
  end if;

  v_qty := p_qty;

  begin
    v_snap := public.batata_live_item_stock(v_req.live_item_id);
    v_avail := coalesce((v_snap->>'available_qty')::int, 0);
  exception when others then
    v_avail := 0;
  end;

  v_avail := v_avail + greatest(coalesce(v_req.requested_qty, 1), 0);

  if v_avail < 1 then
    return jsonb_build_object('ok', false, 'error', 'no_stock', 'available_qty', 0);
  end if;

  if v_qty > v_avail then
    return jsonb_build_object(
      'ok', false,
      'error', 'qty_exceeds_stock',
      'available_qty', v_avail,
      'requested', v_qty
    );
  end if;

  update public.live_reservation_requests
  set
    requested_qty = v_qty,
    updated_at = timezone('utc', now())
  where id = v_req.id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'requested_qty', v_qty,
    'available_qty', v_avail,
    'request_kind', v_kind
  );
end;
$$;

revoke all on function public.batata_live_bag_update_qty(uuid, integer)
  from public, anon;
grant execute on function public.batata_live_bag_update_qty(uuid, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Canonical seller bag read model (buyer sees own bag for one seller).
-- LRR lines + Marketplace open orders adapter (orders are NOT bag; mapped only).
-- ---------------------------------------------------------------------------
create or replace function public.batata_commerce_seller_bag(
  p_seller_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_lines jsonb := '[]'::jsonb;
  v_mp jsonb := '[]'::jsonb;
  r record;
  v_avail int;
  v_line_state text;
  v_kind text;
  v_channel text;
  v_unavailable boolean;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_seller_id');
  end if;

  for r in
    select *
    from public.live_reservation_requests lrr
    where lrr.buyer_id = v_uid
      and lrr.seller_id = p_seller_id
      and lrr.status in ('pending', 'accepted')
      and coalesce(lrr.notes, '') not ilike '%bag_removed%'
      and coalesce(lrr.notes, '') not ilike '%bag_cancelled%'
    order by lrr.created_at asc
  loop
    v_kind := coalesce(nullif(trim(r.request_kind), ''), 'approval_pending');
    v_channel := coalesce(
      nullif(trim(r.source_channel), ''),
      case
        when r.source in ('facebook_manual', 'helper_manual') then 'facebook_psreader'
        else 'fleaber_live'
      end
    );
    v_unavailable := false;
    v_avail := null;

    if r.live_item_id is not null then
      begin
        v_avail := public.batata_live_item_available_qty_engine(r.live_item_id);
      exception when others then
        v_avail := 0;
      end;
      -- Guaranteed already counted in available engine as blocked; treat as available to holder.
      if r.status = 'accepted' and v_kind = 'guaranteed' then
        v_unavailable := false;
        v_line_state := 'guaranteed';
      elsif v_kind = 'approval_pending' and r.status = 'pending' then
        v_line_state := 'approval_pending';
        -- pending never blocked; if stock gone, still pending until close — surface unavailable hint
        if coalesce(v_avail, 0) < greatest(coalesce(r.requested_qty, 1), 1) then
          v_unavailable := true;
          v_line_state := 'unavailable';
        end if;
      elsif v_kind = 'bag_hold_none' then
        v_line_state := 'bag_unguaranteed';
        if coalesce(v_avail, 0) < greatest(coalesce(r.requested_qty, 1), 1) then
          v_unavailable := true;
          v_line_state := 'unavailable';
        end if;
      else
        v_line_state := lower(trim(coalesce(r.status, 'pending')));
      end if;
    else
      v_line_state := case
        when r.status = 'accepted' and v_kind = 'guaranteed' then 'guaranteed'
        when v_kind = 'bag_hold_none' then 'bag_unguaranteed'
        when r.status = 'pending' then 'approval_pending'
        else r.status
      end;
    end if;

    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'line_type', 'live_reservation_request',
      'id', r.id,
      'seller_id', r.seller_id,
      'buyer_id', r.buyer_id,
      'live_id', r.live_id,
      'live_item_id', r.live_item_id,
      'status', r.status,
      'request_kind', v_kind,
      'line_state', v_line_state,
      'source', r.source,
      'source_channel', v_channel,
      'requested_qty', r.requested_qty,
      'expires_at', r.expires_at,
      'queue_position', r.queue_position,
      'available_qty', v_avail,
      'unavailable', v_unavailable,
      'ttl_seconds_snapshot', r.ttl_seconds_snapshot,
      'created_at', r.created_at
    ));
  end loop;

  -- Marketplace adapter: open pre-checkout orders for same buyer+seller.
  -- orders ≠ bag; exposed as mapped lines for one seller saco UI.
  for r in
    select o.*
    from public.orders o
    where o.buyer_id = v_uid
      and o.seller_id = p_seller_id
      and o.live_id is null
      and lower(trim(coalesce(o.status, ''))) in (
        'reserva_pendente', 'reservado', 'aguarda_confirmacao', 'pendente'
      )
    order by o.created_at asc nulls last
  loop
    v_line_state := case lower(trim(coalesce(r.status, '')))
      when 'reservado' then 'guaranteed'
      when 'reserva_pendente' then 'approval_pending'
      else 'bag_unguaranteed'
    end;
    v_mp := v_mp || jsonb_build_array(jsonb_build_object(
      'line_type', 'marketplace_order',
      'id', r.id,
      'seller_id', r.seller_id,
      'buyer_id', r.buyer_id,
      'product_id', r.product_id,
      'status', r.status,
      'request_kind', null,
      'line_state', v_line_state,
      'source', 'marketplace',
      'source_channel', 'marketplace',
      'requested_qty', coalesce(r.quantity, 1),
      'expires_at', r.reservation_expires_at,
      'unavailable', false,
      'created_at', r.created_at,
      'note', 'adapter_not_lrr_orders_are_not_bag'
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'seller_id', p_seller_id,
    'buyer_id', v_uid,
    'grouping', 'buyer_id+seller_id',
    'lrr_lines', v_lines,
    'marketplace_adapter_lines', v_mp,
    'line_count', jsonb_array_length(v_lines) + jsonb_array_length(v_mp)
  );
end;
$$;

revoke all on function public.batata_commerce_seller_bag(uuid) from public, anon;
grant execute on function public.batata_commerce_seller_bag(uuid)
  to authenticated, service_role;

-- Cross-seller probe helper (client cannot merge sellers in one commercial bag).
create or replace function public.batata_commerce_assert_single_seller_bag(
  p_seller_ids uuid[]
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_distinct int;
begin
  select count(distinct x) into v_distinct
  from unnest(p_seller_ids) as t(x)
  where x is not null;
  if coalesce(v_distinct, 0) <= 1 then
    return jsonb_build_object('ok', true, 'seller_count', coalesce(v_distinct, 0));
  end if;
  return jsonb_build_object(
    'ok', false,
    'error', 'cross_seller_bag_forbidden',
    'seller_count', v_distinct
  );
end;
$$;

revoke all on function public.batata_commerce_assert_single_seller_bag(uuid[])
  from public, anon;
grant execute on function public.batata_commerce_assert_single_seller_bag(uuid[])
  to authenticated, service_role;

notify pgrst, 'reload schema';
