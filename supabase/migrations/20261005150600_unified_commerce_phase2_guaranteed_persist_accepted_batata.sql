-- =============================================================================
-- BATATA 2026-10-05 — Phase 2: legacy compatibility — GUARANTEED must persist
-- as status=accepted (do not force pending), + pending chat must not say "reservou".
--
-- Root cause: BEFORE INSERT trigger batata_live_reservation_guard_authority
-- forced NEW.status := 'pending' for any authenticated non-seller INSERT.
-- batata_reserve_with_policy (buyer JWT + SECURITY DEFINER) therefore stored
-- request_kind=guaranteed with status=pending → stock not blocked.
--
-- Fix: commerce engine sets local GUC batata.commerce_engine=1; trigger allows
-- accepted+guaranteed only under that GUC. Direct client inserts still forced pending.
-- Additive. Staging only. Does NOT edit prior migrations.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Guard: allow engine-issued guaranteed accepted inserts
-- ---------------------------------------------------------------------------
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

      -- Phase 2 commerce engine: trusted/policy path may INSERT accepted+guaranteed.
      -- GUC is transaction-local; set only inside batata_reserve_with_policy.
      -- Direct table inserts by buyers still cannot forge accepted.
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

      -- Legacy / direct client insert: always pending (anti-forge)
      NEW.status := 'pending';
      -- Do not allow clients to stamp request_kind=guaranteed without engine GUC
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

-- ---------------------------------------------------------------------------
-- 2) Announce: pending ≠ "reservou" (new semantics: pediu)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_announce_pending_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_label text;
  v_body text;
  v_channel text := 'fleaber';
  v_user uuid;
  v_kind text;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;
  if lower(trim(coalesce(new.status, ''))) is distinct from 'pending' then
    return new;
  end if;
  if lower(trim(coalesce(new.ingest_status, ''))) = 'rejected' then
    return new;
  end if;
  if new.live_id is null or new.live_item_id is null then
    return new;
  end if;

  v_kind := coalesce(nullif(trim(new.request_kind), ''), 'approval_pending');
  -- Bag unguaranteed is not a reservation request — no social announce.
  if v_kind = 'bag_hold_none' then
    return new;
  end if;
  -- Hybrid bug state must never announce as reserved.
  if v_kind = 'guaranteed' then
    return new;
  end if;

  if new.buyer_id is not null then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(handle), ''), 'Comprador')
    into v_name
    from public.profiles
    where id = new.buyer_id;
  end if;
  if v_name is null or trim(v_name) = '' then
    v_name := coalesce(nullif(trim(new.external_display_name), ''), 'Comprador');
  end if;

  v_label := public.batata_live_item_chat_label(new.live_item_id);
  -- NEW architecture: pending = pediu (not reservou)
  v_body := '🛍️ ' || v_name || ' pediu ' || v_label;

  if lower(trim(coalesce(new.source, ''))) = 'facebook_manual' then
    v_channel := 'fleaber';
  end if;

  v_user := coalesce(new.buyer_id, new.seller_id);

  if exists (
    select 1
    from public.live_messages m
    where m.live_id = new.live_id
      and m.body = v_body
      and m.created_at > now() - interval '45 seconds'
  ) then
    return new;
  end if;

  begin
    insert into public.live_messages (
      live_id, user_id, kind, body, sender_label, channel
    ) values (
      new.live_id, v_user, 'system', v_body, 'Sistema', v_channel
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Reserve engine: set commerce_engine GUC before INSERT
-- ---------------------------------------------------------------------------
create or replace function public.batata_reserve_with_policy(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_live_id uuid,
  p_live_item_id uuid,
  p_qty integer default 1,
  p_source text default 'fleaber_live',
  p_guest_session_id uuid default null,
  p_identity_linked boolean default true,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_lock_key text;
  v_avail integer;
  v_decision jsonb;
  v_outcome text;
  v_request_kind text;
  v_status text;
  v_ttl integer;
  v_expires timestamptz;
  v_row public.live_reservation_requests%rowtype;
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_canonical_live_id uuid;
  v_seller uuid;
  v_product uuid;
  v_prod_seller uuid;
  v_event jsonb;
begin
  if p_live_item_id is null or p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  if v_role is distinct from 'service_role' then
    if v_uid is null then
      return jsonb_build_object('ok', false, 'error', 'not_authenticated');
    end if;
    if p_buyer_id is null or p_buyer_id is distinct from v_uid then
      return jsonb_build_object('ok', false, 'error', 'buyer_self_only');
    end if;
  end if;

  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  v_canonical_live_id := v_li.live_id;
  if v_canonical_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_no_live');
  end if;

  if p_live_id is not null and p_live_id is distinct from v_canonical_live_id then
    return jsonb_build_object('ok', false, 'error', 'live_item_live_mismatch');
  end if;

  select * into v_live from public.lives where id = v_canonical_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_seller_missing');
  end if;

  if p_seller_id is distinct from v_seller then
    return jsonb_build_object('ok', false, 'error', 'seller_mismatch');
  end if;

  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  if v_product is not null then
    select pr.seller_id into v_prod_seller
    from public.products pr
    where pr.id = v_product;
    if v_prod_seller is not null and v_prod_seller is distinct from v_seller then
      return jsonb_build_object('ok', false, 'error', 'product_seller_mismatch');
    end if;
  end if;

  v_lock_key := coalesce(v_product::text, p_live_item_id::text) || ':commerce_reserve';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);

  v_decision := public.batata_commerce_decide_reservation_outcome(
    v_seller,
    p_buyer_id,
    v_avail,
    v_qty,
    coalesce(p_identity_linked, true)
  );

  if coalesce((v_decision->>'ok')::boolean, false) = false then
    return v_decision;
  end if;

  v_outcome := v_decision->>'outcome';
  if v_outcome = 'UNAVAILABLE' then
    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'decision', v_decision,
      'request_id', null
    );
  end if;

  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);
  if v_avail < v_qty then
    return jsonb_build_object(
      'ok', true,
      'outcome', 'UNAVAILABLE',
      'decision', v_decision,
      'request_id', null,
      'reason', 'stock_race'
    );
  end if;

  v_request_kind := v_decision->>'request_kind';
  v_status := v_decision->>'status';
  v_ttl := nullif(v_decision->>'ttl_seconds', '')::integer;

  if v_outcome = 'GUARANTEED' then
    v_expires := timezone('utc', now()) + make_interval(secs => v_ttl);
  elsif v_outcome = 'PENDING_APPROVAL' then
    v_expires := timezone('utc', now()) + interval '45 minutes';
  else
    v_expires := null;
  end if;

  -- Allow BEFORE INSERT guard to keep accepted+guaranteed (transaction-local).
  perform set_config('batata.commerce_engine', '1', true);

  insert into public.live_reservation_requests (
    live_id,
    live_item_id,
    seller_id,
    buyer_id,
    requested_qty,
    status,
    source,
    notes,
    expires_at,
    request_kind,
    policy_mode_snapshot,
    untrusted_mode_snapshot,
    trust_decision_snapshot,
    ttl_seconds_snapshot,
    policy_version_snapshot,
    guest_session_id
  ) values (
    v_canonical_live_id,
    p_live_item_id,
    v_seller,
    p_buyer_id,
    v_qty,
    v_status,
    coalesce(nullif(trim(p_source), ''), 'fleaber_live'),
    p_notes,
    v_expires,
    v_request_kind,
    v_decision->>'policy_mode',
    v_decision->>'untrusted_mode',
    v_decision->'trust'->>'decision',
    v_ttl,
    nullif(v_decision->>'policy_version', '')::integer,
    p_guest_session_id
  )
  returning * into v_row;

  if v_outcome = 'GUARANTEED' then
    begin
      perform public.batata_recompute_live_item_status(p_live_item_id);
    exception when others then
      null;
    end;
    v_event := public.batata_commerce_emit_reservation_event(
      v_row.id,
      'reservation_guaranteed',
      jsonb_build_object(
        'expires_at', v_row.expires_at,
        'ttl_seconds', v_ttl,
        'source', 'reserve_with_policy',
        'live_item_id', p_live_item_id,
        'buyer_id', p_buyer_id,
        'seller_id', v_seller
      )
    );
    perform public.batata_close_pending_for_stock(p_live_item_id, v_row.id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'outcome', v_outcome,
    'request_id', v_row.id,
    'status', v_row.status,
    'request_kind', v_row.request_kind,
    'expires_at', v_row.expires_at,
    'ttl_seconds_snapshot', v_row.ttl_seconds_snapshot,
    'policy_version_snapshot', v_row.policy_version_snapshot,
    'trust_decision_snapshot', v_row.trust_decision_snapshot,
    'decision', v_decision,
    'd19_event', coalesce(v_event, '{}'::jsonb),
    'available_qty_after', public.batata_live_item_available_qty_engine(p_live_item_id)
  );
end;
$$;

revoke all on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  from public;
grant execute on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Repair hybrid rows created by the bug (engine snapshots present)
-- ---------------------------------------------------------------------------
update public.live_reservation_requests
set
  status = 'accepted',
  updated_at = timezone('utc', now()),
  notes = trim(both ' |' from coalesce(notes, '') || ' | repaired_guaranteed_status')
where status = 'pending'
  and coalesce(request_kind, '') = 'guaranteed'
  and ttl_seconds_snapshot is not null
  and expires_at is not null;

notify pgrst, 'reload schema';
