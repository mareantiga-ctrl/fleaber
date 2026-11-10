-- =============================================================================
-- BATATA 2026-10-05 — Phase 3 correction
-- batata_live_bag_update_qty: stop inflating available_qty for non-blocking lines.
--
-- Root cause (Phase 3 migration 20261005160000):
--   v_avail := available_qty + current_requested_qty
-- assumed "this line is already deducted from stock".
-- That is only true for capacity-consuming statuses (accepted / converted).
-- approval_pending + bag_hold_none never block → available already includes them.
-- Adding requested_qty again allowed oversell via bag stepper (stock=1 → qty=2).
--
-- Correct semantics:
--   guaranteed (accepted + guaranteed): qty immutable (unchanged).
--   approval_pending / bag_hold_none: new qty <= canonical available_qty (NO add-back).
--   legacy accepted that somehow reaches qty edit: add-back only if status consumes capacity.
-- Additive corrective migration. Does NOT edit 20261005160000.
-- Staging only. PRODUCTION NOT CHANGED by this agent action alone.
-- =============================================================================

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
  v_line_blocks boolean := false;
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
    -- Prefer engine available (same as reserve/accept). Fallback to stock JSON.
    v_avail := public.batata_live_item_available_qty_engine(v_req.live_item_id);
  exception when others then
    begin
      v_snap := public.batata_live_item_stock(v_req.live_item_id);
      v_avail := coalesce((v_snap->>'available_qty')::int, 0);
    exception when others then
      v_avail := 0;
    end;
  end;

  -- Only add back this line's qty when it already participates in blocked/reserved capacity.
  -- pending + approval_pending / bag_hold_none → NEVER add back.
  v_line_blocks := public.batata_live_reservation_status_consumes_capacity(v_req.status);
  if v_line_blocks then
    v_avail := v_avail + greatest(coalesce(v_req.requested_qty, 1), 0);
  end if;

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
    'request_kind', v_kind,
    'line_blocks_stock', v_line_blocks
  );
end;
$$;

revoke all on function public.batata_live_bag_update_qty(uuid, integer)
  from public, anon;
grant execute on function public.batata_live_bag_update_qty(uuid, integer)
  to authenticated, service_role;

comment on function public.batata_live_bag_update_qty(uuid, integer) is
  'Bag qty edit: pending/bag_hold_none use raw available (no inflate). Accepted add-back only when status consumes capacity. Guaranteed qty immutable.';

notify pgrst, 'reload schema';
