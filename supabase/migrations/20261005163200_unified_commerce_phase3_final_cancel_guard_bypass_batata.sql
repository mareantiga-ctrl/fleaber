-- =============================================================================
-- BATATA 2026-10-05 — Phase 3 FINAL
-- Fix: buyer voluntary cancel was silently reverted by guard_authority UPDATE
-- (buyer cannot change status → NEW.status forced back to accepted).
-- Expire works because service_role skips the guard; cancel is authenticated.
-- Solution: commerce_engine GUC allows buyer transition accepted → rejected/expired.
-- =============================================================================

create or replace function public.batata_live_reservation_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean := false;
  v_avail int := 0;
  v_item_qty int := 0;
  v_new_consumes boolean := false;
  v_old_consumes boolean := false;
  v_need_capacity boolean := false;
  v_allowed_status boolean := false;
  v_engine boolean := coalesce(current_setting('batata.commerce_engine', true), '') = '1';
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  v_allowed_status := NEW.status in (
    'pending', 'accepted', 'rejected', 'expired', 'converted'
  );
  if not v_allowed_status then
    raise exception 'invalid_reservation_status' using errcode = '23514';
  end if;

  v_is_seller :=
    (NEW.seller_id is not null and NEW.seller_id = v_uid)
    or exists (
      select 1 from public.lives l
      where l.id = NEW.live_id
        and (l.seller_id = v_uid or l.vendedor_id = v_uid)
    )
    or public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations');

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;

      if v_engine
         and lower(trim(coalesce(NEW.request_kind, ''))) = 'guaranteed'
         and NEW.status = 'accepted' then
        if NEW.requested_qty > 99 then
          raise exception 'invalid_requested_qty' using errcode = '23514';
        end if;
        if v_new_consumes then
          perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
          v_avail := public.batata_live_reservation_accept_available(
            NEW.live_item_id,
            null
          );
          if NEW.requested_qty > v_avail then
            raise exception 'qty_exceeds_stock' using errcode = '23514';
          end if;
        end if;
        return NEW;
      end if;

      NEW.status := 'pending';
      if lower(trim(coalesce(NEW.request_kind, ''))) = 'guaranteed' then
        NEW.request_kind := 'approval_pending';
      end if;
      v_item_qty := coalesce(public.batata_live_item_total_qty(NEW.live_item_id), 0);
      if v_item_qty < 1 then
        v_item_qty := 1;
      end if;
      if NEW.requested_qty > v_item_qty then
        NEW.requested_qty := v_item_qty;
      end if;
      if NEW.requested_qty > 20 then
        NEW.requested_qty := 20;
      end if;
      return NEW;
    end if;

    if NEW.requested_qty > 99 then
      raise exception 'invalid_requested_qty' using errcode = '23514';
    end if;

    if v_new_consumes then
      perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
      v_avail := public.batata_live_reservation_accept_available(
        NEW.live_item_id,
        null
      );
      if NEW.requested_qty > v_avail then
        raise exception 'qty_exceeds_stock' using errcode = '23514';
      end if;
    end if;
    return NEW;
  end if;

  v_old_consumes := public.batata_live_reservation_status_consumes_capacity(OLD.status);

  if not v_is_seller and NEW.buyer_id = v_uid then
    -- Phase 3: engine-backed voluntary cancel / terminal release.
    -- Allows accepted → rejected|expired only when commerce_engine GUC is set
    -- by batata_commerce_cancel_guaranteed_reservation (never by raw client UPDATE).
    if v_engine
       and OLD.status = 'accepted'
       and NEW.status in ('rejected', 'expired')
       and NEW.buyer_id = v_uid then
      return NEW;
    end if;

    if NEW.status is distinct from public.batata_live_reservation_status_canonical(OLD.status) then
      NEW.status := public.batata_live_reservation_status_canonical(OLD.status);
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
    return NEW;
  end if;

  if v_new_consumes and not v_old_consumes then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  v_need_capacity :=
    v_new_consumes
    and (
      (not v_old_consumes)
      or (NEW.requested_qty > coalesce(OLD.requested_qty, 0))
    );

  if v_need_capacity then
    if NEW.live_item_id is null then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
    v_avail := public.batata_live_reservation_accept_available(
      NEW.live_item_id,
      NEW.id
    );
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
  end if;

  return NEW;
end;
$$;

-- Cancel RPC: set commerce_engine before UPDATE so guard allows terminal transition.
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

  perform set_config('batata.commerce_engine', '1', true);

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

  -- Confirm status actually stuck (guard must not have reverted).
  select * into v_req from public.live_reservation_requests where id = p_request_id;
  if v_req.status is distinct from 'rejected' then
    return jsonb_build_object(
      'ok', false,
      'error', 'cancel_reverted_by_guard',
      'status', v_req.status
    );
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
