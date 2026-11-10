-- =============================================================================
-- BATATA 2026-10-05 — Phase 3 FINAL fix
-- Allow commerce event kind for voluntary guarantee cancel.
-- Soften cancel idempotency + ensure stock snapshot after cancel.
-- =============================================================================

alter table public.commerce_reservation_events
  drop constraint if exists commerce_reservation_events_kind_check;

alter table public.commerce_reservation_events
  add constraint commerce_reservation_events_kind_check
  check (kind = any (array[
    'reservation_guaranteed',
    'pending_expired_buyer_notice',
    'pending_stock_unavailable',
    'guaranteed_expired',
    'extension_applied',
    'promotion_applied',
    'promotion_skipped_no_stock',
    'guaranteed_cancelled_by_buyer'
  ]));

-- Re-apply cancel function with clearer idempotency (any terminal buyer cancel).
create or replace function public.batata_commerce_cancel_guaranteed_reservation(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_uid uuid := auth.uid();
  v_kind text;
  v_pay jsonb;
  v_avail_after int;
  v_reserved_after int;
  v_event jsonb;
  v_label text;
  v_body text;
  v_snap jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_request_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_request_id');
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  if v_req.status in ('rejected', 'expired', 'converted')
     and (
       coalesce(v_req.expiry_reason, '') = 'buyer_cancelled'
       or coalesce(v_req.notes, '') ilike '%buyer_voluntary_cancel%'
       or coalesce(v_req.notes, '') ilike '%bag_cancelled%'
     ) then
    begin
      v_avail_after := public.batata_live_item_available_qty_engine(v_req.live_item_id);
    exception when others then
      v_avail_after := null;
    end;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'request_id', v_req.id,
      'status', v_req.status,
      'expiry_reason', v_req.expiry_reason,
      'trust_failure', false,
      'available_qty_after', v_avail_after
    );
  end if;

  if v_req.buyer_id is distinct from v_uid then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_kind := coalesce(nullif(trim(v_req.request_kind), ''), 'approval_pending');

  if v_req.status is distinct from 'accepted' or v_kind is distinct from 'guaranteed' then
    return jsonb_build_object(
      'ok', false,
      'error', 'not_guaranteed',
      'status', v_req.status,
      'request_kind', v_kind
    );
  end if;

  begin
    v_pay := public.batata_lrr_payment_in_progress(v_req.id, timezone('utc', now()));
  exception when others then
    v_pay := jsonb_build_object('in_progress', false);
  end;

  if coalesce((v_pay->>'in_progress')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'payment_in_progress',
      'payment', v_pay
    );
  end if;

  update public.live_reservation_requests
  set
    status = 'rejected',
    expiry_reason = 'buyer_cancelled',
    notes = trim(both ' |' from coalesce(notes, '') || ' | buyer_voluntary_cancel | bag_cancelled'),
    queue_position = null,
    expires_at = null,
    updated_at = timezone('utc', now())
  where id = v_req.id
    and status = 'accepted';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'race_lost');
  end if;

  begin
    v_event := public.batata_commerce_emit_reservation_event(
      v_req.id,
      'guaranteed_cancelled_by_buyer',
      jsonb_build_object(
        'expiry_reason', 'buyer_cancelled',
        'voluntary', true,
        'trust_failure', false,
        'live_item_id', v_req.live_item_id,
        'seller_id', v_req.seller_id
      )
    );
  exception when others then
    v_event := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;

  begin
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  exception when others then null;
  end;
  begin
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then null;
  end;

  begin
    v_avail_after := public.batata_live_item_available_qty_engine(v_req.live_item_id);
  exception when others then
    v_avail_after := null;
  end;

  begin
    v_snap := public.batata_live_item_stock(v_req.live_item_id);
    v_reserved_after := coalesce((v_snap->>'reserved_accepted_qty')::int, 0);
  exception when others then
    v_reserved_after := null;
  end;

  if v_req.live_id is not null then
    begin
      v_label := public.batata_live_item_chat_label(v_req.live_item_id);
      v_body := '↩ Reserva cancelada pelo comprador · ' || coalesce(v_label, 'artigo');
      perform public.batata_live_system_message(v_req.live_id, v_body, 'Sistema');
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'status', 'rejected',
    'expiry_reason', 'buyer_cancelled',
    'trust_failure', false,
    'available_qty_after', v_avail_after,
    'reserved_accepted_qty_after', v_reserved_after,
    'event', v_event,
    'idempotent', false
  );
end;
$$;

revoke all on function public.batata_commerce_cancel_guaranteed_reservation(uuid)
  from public, anon;
grant execute on function public.batata_commerce_cancel_guaranteed_reservation(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
