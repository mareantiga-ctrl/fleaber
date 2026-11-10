-- Phase 6.1: seller Studio «Reserva Facebook» must call engine for another buyer.
-- batata_reserve_with_policy only allows service_role or buyer_self; add seller actor mode.

create or replace function public.batata_reserve_with_policy(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_live_id uuid,
  p_live_item_id uuid,
  p_qty integer default 1,
  p_source text default 'fleaber_live',
  p_guest_session_id uuid default null,
  p_identity_linked boolean default true,
  p_notes text default null,
  p_actor_mode text default 'buyer'
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
  v_mode text := lower(trim(coalesce(p_actor_mode, 'buyer')));
begin
  if p_live_item_id is null or p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
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

  if v_role is distinct from 'service_role' then
    if v_uid is null then
      return jsonb_build_object('ok', false, 'error', 'not_authenticated');
    end if;
    if v_mode = 'seller_for_buyer' then
      if v_uid is distinct from v_seller
         and not public.batata_staff_has_permission(v_seller, 'can_manage_reservations') then
        return jsonb_build_object('ok', false, 'error', 'not_allowed');
      end if;
      if p_buyer_id is null then
        return jsonb_build_object('ok', false, 'error', 'missing_buyer');
      end if;
    else
      if p_buyer_id is null or p_buyer_id is distinct from v_uid then
        return jsonb_build_object('ok', false, 'error', 'buyer_self_only');
      end if;
    end if;
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

-- Keep old 9-arg signature callable (PostgREST / clients without p_actor_mode)
drop function if exists public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text);

revoke all on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text, text)
  from public;
grant execute on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text, text)
  to authenticated, service_role;

create or replace function public.batata_commerce_seller_manual_reserve_with_policy(
  p_live_id uuid,
  p_live_item_id uuid,
  p_buyer_id uuid,
  p_qty integer default 1,
  p_source text default 'facebook_manual',
  p_notes text default null,
  p_external_display_name text default null,
  p_client_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_live public.lives%rowtype;
  v_seller uuid;
  v_src text := lower(trim(coalesce(p_source, 'facebook_manual')));
  v_qty integer := greatest(coalesce(p_qty, 1), 1);
  v_reserve jsonb;
  v_rid uuid;
  v_idem text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_live_id is null or p_live_item_id is null or p_buyer_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;
  if v_qty > 99 then
    return jsonb_build_object('ok', false, 'error', 'invalid_qty');
  end if;
  if v_src not in ('facebook_manual', 'helper_manual') then
    return jsonb_build_object('ok', false, 'error', 'invalid_source');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is null or (
    v_seller is distinct from v_uid
    and not public.batata_staff_has_permission(v_seller, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_idem := nullif(trim(coalesce(p_client_idempotency_key, '')), '');
  if v_idem is not null then
    select r.id into v_rid
    from public.live_reservation_requests r
    where r.idempotency_key = v_idem
    limit 1;
    if v_rid is not null then
      return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_rid);
    end if;
  end if;

  v_reserve := public.batata_reserve_with_policy(
    v_seller,
    p_buyer_id,
    p_live_id,
    p_live_item_id,
    v_qty,
    v_src,
    null,
    true,
    coalesce(nullif(trim(p_notes), ''), 'seller:manual:' || v_src),
    'seller_for_buyer'
  );

  if coalesce((v_reserve->>'ok')::boolean, false) = false then
    return v_reserve;
  end if;
  if (v_reserve->>'outcome') = 'UNAVAILABLE' then
    return v_reserve || jsonb_build_object('action', 'unavailable');
  end if;

  v_rid := nullif(v_reserve->>'request_id', '')::uuid;
  if v_rid is not null then
    update public.live_reservation_requests r
    set
      external_display_name = coalesce(
        nullif(trim(coalesce(p_external_display_name, '')), ''),
        r.external_display_name
      ),
      idempotency_key = coalesce(v_idem, r.idempotency_key),
      ingest_channel = coalesce(r.ingest_channel, 'manual'),
      updated_at = timezone('utc', now())
    where r.id = v_rid;
  end if;

  return v_reserve || jsonb_build_object('action', 'created', 'duplicate', false);
end;
$$;

notify pgrst, 'reload schema';
