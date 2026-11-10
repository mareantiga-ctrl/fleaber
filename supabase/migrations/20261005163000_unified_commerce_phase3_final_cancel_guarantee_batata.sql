-- =============================================================================
-- BATATA 2026-10-05 — Phase 3 FINAL
-- 1) Buyer voluntary cancel of GUARANTEED reservation (no D25 trust failure)
-- 2) Harden bag_remove: guaranteed must use cancel RPC (not normal remove)
-- Additive. Does not edit prior migrations. Staging only via apply.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- A) Voluntary cancel of a real guarantee
-- ---------------------------------------------------------------------------
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
  v_event jsonb;
  v_label text;
  v_body text;
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

  -- Idempotent: already buyer-cancelled terminal.
  if v_req.status in ('rejected', 'expired')
     and (
       coalesce(v_req.expiry_reason, '') = 'buyer_cancelled'
       or coalesce(v_req.notes, '') ilike '%buyer_voluntary_cancel%'
       or coalesce(v_req.notes, '') ilike '%bag_cancelled%'
     ) then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'request_id', v_req.id,
      'status', v_req.status,
      'expiry_reason', v_req.expiry_reason,
      'trust_failure', false
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
      'request_kind', v_kind,
      'hint', 'only_accepted_guaranteed_can_use_this_rpc'
    );
  end if;

  -- Fail-safe: do not cancel while legitimate payment is in progress (Phase 4 lock).
  begin
    v_pay := public.batata_lrr_payment_in_progress(v_req.id, timezone('utc', now()));
  exception when others then
    v_pay := jsonb_build_object('in_progress', false);
  end;

  if coalesce((v_pay->>'in_progress')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'payment_in_progress',
      'hint', 'cannot_cancel_while_payment_processing',
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

  -- Audit event — NOT a trust failure.
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

  -- Stock release via status change (accepted no longer counted).
  begin
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  exception when others then
    null;
  end;
  begin
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then
    null;
  end;

  begin
    v_avail_after := public.batata_live_item_available_qty_engine(v_req.live_item_id);
  exception when others then
    v_avail_after := null;
  end;

  -- Lifecycle chat: do not leave conversation looking reserved.
  if v_req.live_id is not null then
    begin
      v_label := public.batata_live_item_chat_label(v_req.live_item_id);
      v_body := '↩ Reserva cancelada pelo comprador · ' || coalesce(v_label, 'artigo');
      perform public.batata_live_system_message(v_req.live_id, v_body, 'Sistema');
    exception when others then
      null;
    end;
  end if;

  -- Explicitly DO NOT call batata_buyer_trust_record_failure.
  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'status', 'rejected',
    'expiry_reason', 'buyer_cancelled',
    'trust_failure', false,
    'available_qty_after', v_avail_after,
    'event', v_event,
    'idempotent', false
  );
end;
$$;

revoke all on function public.batata_commerce_cancel_guaranteed_reservation(uuid)
  from public, anon;
grant execute on function public.batata_commerce_cancel_guaranteed_reservation(uuid)
  to authenticated, service_role;

comment on function public.batata_commerce_cancel_guaranteed_reservation(uuid) is
  'Buyer voluntary cancel of accepted+guaranteed. Releases stock. Never records D25 trust failure.';

-- ---------------------------------------------------------------------------
-- B) Harden bag_remove: guaranteed cannot be removed as a normal line
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_bag_remove_request(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_next_status text;
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

  v_kind := coalesce(nullif(trim(v_req.request_kind), ''), 'approval_pending');

  -- Product decision: guaranteed must use explicit Cancelar reserva.
  if v_req.status = 'accepted' and v_kind = 'guaranteed' then
    return jsonb_build_object(
      'ok', false,
      'error', 'use_cancel_guarantee',
      'hint', 'call_batata_commerce_cancel_guaranteed_reservation'
    );
  end if;

  update public.live_reservation_requests
  set
    status = 'rejected',
    notes = coalesce(notes || ' | ', '') || 'bag_removed',
    queue_position = null,
    updated_at = now()
  where id = v_req.id;

  begin
    perform public.batata_live_system_message(
      v_req.live_id,
      '↩ Removido do saco pelo comprador',
      'Sistema'
    );
  exception when others then
    null;
  end;

  begin
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  exception when others then
    null;
  end;
  begin
    perform public.batata_recompute_live_item_status(v_req.live_item_id);
  exception when others then
    null;
  end;

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'queue_recompacted', true,
    'removed_kind', v_kind
  );
end;
$$;

revoke all on function public.batata_live_bag_remove_request(uuid)
  from public, anon;
grant execute on function public.batata_live_bag_remove_request(uuid)
  to authenticated, service_role;

-- Allow commerce event kind for cancel (if constrained elsewhere, event emit is best-effort).
notify pgrst, 'reload schema';
