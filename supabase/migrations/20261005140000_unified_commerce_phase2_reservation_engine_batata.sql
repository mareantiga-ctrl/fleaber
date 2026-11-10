-- =============================================================================
-- BATATA 2026-10-05 — Unified commerce Fase 2: motor canónico de reservas
-- Staging only. Additive. No PSP / Meta / DPD / UI redesign.
-- PENDING never blocks. GUARANTEED blocks. Decision 25 wired at expiry (next mig).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) Audit columns for one-time extension + D19 event ledger
-- -----------------------------------------------------------------------------
alter table public.live_reservation_requests
  add column if not exists extended_at timestamptz;

alter table public.live_reservation_requests
  add column if not exists extension_ttl_seconds integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'live_reservation_requests_extension_ttl_seconds_chk'
  ) then
    alter table public.live_reservation_requests
      add constraint live_reservation_requests_extension_ttl_seconds_chk
      check (
        extension_ttl_seconds is null
        or (extension_ttl_seconds >= 900 and extension_ttl_seconds <= 432000)
      );
  end if;
end $$;

create table if not exists public.commerce_reservation_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.live_reservation_requests (id) on delete cascade,
  kind text not null check (kind in (
    'reservation_guaranteed',
    'pending_expired_buyer_notice',
    'pending_stock_unavailable',
    'guaranteed_expired',
    'extension_applied',
    'promotion_applied',
    'promotion_skipped_no_stock'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

comment on table public.commerce_reservation_events is
  'Eventos canónicos de reserva (D19 foundation). Idempotentes por (request_id, kind). Sem UI nesta fase.';

create unique index if not exists uq_commerce_reservation_events_request_kind
  on public.commerce_reservation_events (request_id, kind);

create index if not exists idx_commerce_reservation_events_created
  on public.commerce_reservation_events (created_at desc);

alter table public.commerce_reservation_events enable row level security;

drop policy if exists commerce_reservation_events_select_participant
  on public.commerce_reservation_events;
create policy commerce_reservation_events_select_participant
  on public.commerce_reservation_events
  for select to authenticated
  using (
    exists (
      select 1
      from public.live_reservation_requests r
      where r.id = commerce_reservation_events.request_id
        and (r.buyer_id = auth.uid() or r.seller_id = auth.uid())
    )
  );

revoke all on table public.commerce_reservation_events from anon;
revoke insert, update, delete on table public.commerce_reservation_events from authenticated;
grant select on table public.commerce_reservation_events to authenticated;
grant all on table public.commerce_reservation_events to service_role;

-- -----------------------------------------------------------------------------
-- B) Emit event (idempotent) — service / internal only
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_emit_reservation_event(
  p_request_id uuid,
  p_kind text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  if p_request_id is null or coalesce(trim(p_kind), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  begin
    insert into public.commerce_reservation_events (request_id, kind, payload)
    values (p_request_id, trim(p_kind), coalesce(p_payload, '{}'::jsonb));
    v_inserted := true;
  exception when unique_violation then
    v_inserted := false;
  end;

  return jsonb_build_object('ok', true, 'inserted', v_inserted, 'kind', trim(p_kind));
end;
$$;

revoke all on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb) from public;
grant execute on function public.batata_commerce_emit_reservation_event(uuid, text, jsonb)
  to service_role;

-- -----------------------------------------------------------------------------
-- C) Internal available qty (no hub visibility gate) for engine decisions
-- -----------------------------------------------------------------------------
create or replace function public.batata_live_item_available_qty_engine(p_live_item_id uuid)
returns integer
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
  v_sold_converted integer := 0;
  v_sold_orders integer := 0;
  v_available integer;
  v_product_id uuid;
  v_seller uuid;
  v_lineage uuid;
  v_live_only boolean := false;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  v_lineage := coalesce(v_li.logical_item_id, v_li.id);
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
  v_available := v_total - v_blocked - v_reserved_accepted;
  if v_live_only or v_product_id is null then
    v_available := v_available - v_sold_converted;
  elsif v_sold_converted >= greatest(v_total, 1) then
    v_available := 0;
  end if;
  if v_available < 0 then
    v_available := 0;
  end if;
  return v_available;
end;
$$;

revoke all on function public.batata_live_item_available_qty_engine(uuid) from public;
grant execute on function public.batata_live_item_available_qty_engine(uuid)
  to service_role;

-- -----------------------------------------------------------------------------
-- D) Pure commercial decision (no writes)
-- -----------------------------------------------------------------------------
create or replace function public.batata_commerce_decide_reservation_outcome(
  p_seller_id uuid,
  p_buyer_id uuid,
  p_available_qty integer,
  p_requested_qty integer default 1,
  p_identity_linked boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_settings public.seller_reservation_settings%rowtype;
  v_trust jsonb;
  v_has_benefit boolean := false;
  v_decision text;
  v_qty integer := greatest(coalesce(p_requested_qty, 1), 1);
  v_avail integer := greatest(coalesce(p_available_qty, 0), 0);
  v_outcome text;
  v_request_kind text;
  v_ttl integer;
  v_status text;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_seller');
  end if;

  select * into v_settings
  from public.seller_reservation_settings
  where seller_id = p_seller_id;

  if v_settings.seller_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'policy_not_configured',
      'outcome', 'UNAVAILABLE'
    );
  end if;

  if coalesce(p_identity_linked, true) = false or p_buyer_id is null then
    v_trust := jsonb_build_object(
      'ok', true,
      'decision', 'IDENTITY_INSUFFICIENT',
      'has_benefit', false
    );
  else
    v_trust := public.batata_buyer_trust_decision(p_seller_id, p_buyer_id);
  end if;

  v_has_benefit := coalesce((v_trust->>'has_benefit')::boolean, false);
  v_decision := coalesce(v_trust->>'decision', 'IDENTITY_INSUFFICIENT');

  -- Auto / trust benefit → guaranteed only with stock
  if v_settings.policy_mode = 'auto'
     or (v_settings.policy_mode = 'trust' and v_has_benefit)
     or (v_settings.policy_mode = 'manual' and false) then
    if v_avail < v_qty then
      return jsonb_build_object(
        'ok', true,
        'outcome', 'UNAVAILABLE',
        'request_kind', null,
        'status', null,
        'ttl_seconds', null,
        'trust', v_trust,
        'policy_mode', v_settings.policy_mode,
        'untrusted_mode', v_settings.untrusted_mode,
        'policy_version', v_settings.policy_version
      );
    end if;
    v_outcome := 'GUARANTEED';
    v_request_kind := 'guaranteed';
    v_status := 'accepted';
    v_ttl := case
      when v_has_benefit then v_settings.trusted_ttl_seconds
      else v_settings.normal_ttl_seconds
    end;
  elsif v_settings.policy_mode = 'trust' and not v_has_benefit then
    if v_settings.untrusted_mode = 'approval' then
      v_outcome := 'PENDING_APPROVAL';
      v_request_kind := 'approval_pending';
      v_status := 'pending';
      v_ttl := 2700; -- 45 minutes fixed
    else
      -- pay_required: foundation only — no fake guaranteed, no approval pending
      v_outcome := 'BAG_UNGUARANTEED';
      v_request_kind := 'bag_hold_none';
      v_status := 'pending';
      v_ttl := null;
    end if;
  elsif v_settings.policy_mode = 'manual' then
    v_outcome := 'PENDING_APPROVAL';
    v_request_kind := 'approval_pending';
    v_status := 'pending';
    v_ttl := 2700;
  elsif v_settings.policy_mode = 'pay_only' then
    v_outcome := 'BAG_UNGUARANTEED';
    v_request_kind := 'bag_hold_none';
    v_status := 'pending';
    v_ttl := null;
  else
    return jsonb_build_object('ok', false, 'error', 'unsupported_policy_mode');
  end if;

  -- Guaranteed path already handled stock; pending/bag do not require stock
  -- but if stock is 0 and outcome would be guaranteed we already returned UNAVAILABLE.
  -- For pending with 0 stock: still allow pending (does not block); seller may reject.
  -- Product rule: if no stock at all for guaranteed-eligible, unavailable.
  -- For BAG with 0 stock: still BAG_UNGUARANTEED (may lose item) — keep outcome.

  if v_outcome = 'GUARANTEED' and v_avail < v_qty then
    v_outcome := 'UNAVAILABLE';
    v_request_kind := null;
    v_status := null;
    v_ttl := null;
  end if;

  return jsonb_build_object(
    'ok', true,
    'outcome', v_outcome,
    'request_kind', v_request_kind,
    'status', v_status,
    'ttl_seconds', v_ttl,
    'trust', v_trust,
    'policy_mode', v_settings.policy_mode,
    'untrusted_mode', v_settings.untrusted_mode,
    'policy_version', v_settings.policy_version,
    'normal_ttl_seconds', v_settings.normal_ttl_seconds,
    'trusted_ttl_seconds', v_settings.trusted_ttl_seconds,
    'available_qty', v_avail,
    'requested_qty', v_qty
  );
end;
$$;

revoke all on function public.batata_commerce_decide_reservation_outcome(uuid, uuid, integer, integer, boolean)
  from public;
grant execute on function public.batata_commerce_decide_reservation_outcome(uuid, uuid, integer, integer, boolean)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- E) Canonical reserve write path
-- -----------------------------------------------------------------------------
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
  v_seller uuid;
  v_product uuid;
  v_event jsonb;
begin
  if p_live_item_id is null or p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_args');
  end if;

  -- Authz: buyer self, or service_role / postgres (PS / jobs)
  if v_role is distinct from 'service_role' and current_user is distinct from 'postgres' then
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

  select * into v_live from public.lives where id = coalesce(p_live_id, v_li.live_id);
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);
  if v_seller is distinct from p_seller_id then
    return jsonb_build_object('ok', false, 'error', 'seller_mismatch');
  end if;

  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  v_lock_key := coalesce(v_product::text, p_live_item_id::text) || ':commerce_reserve';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));

  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);

  v_decision := public.batata_commerce_decide_reservation_outcome(
    p_seller_id,
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

  v_request_kind := v_decision->>'request_kind';
  v_status := v_decision->>'status';
  v_ttl := nullif(v_decision->>'ttl_seconds', '')::integer;

  if v_outcome = 'GUARANTEED' then
    -- Re-check under lock
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
    v_expires := timezone('utc', now()) + make_interval(secs => v_ttl);
  elsif v_outcome = 'PENDING_APPROVAL' then
    v_expires := timezone('utc', now()) + interval '45 minutes';
  else
    -- BAG_UNGUARANTEED: no fake TTL; does not look guaranteed
    v_expires := null;
  end if;

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
    coalesce(p_live_id, v_li.live_id),
    p_live_item_id,
    p_seller_id,
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
        'seller_id', p_seller_id
      )
    );
    -- Close incompatible pendings on same stock unit
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

-- Forward declare stub for close_pending (body in same migration below)
create or replace function public.batata_close_pending_for_stock(
  p_live_item_id uuid,
  p_except_request_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_closed integer := 0;
  v_avail integer;
  v_product uuid;
  v_li public.live_items%rowtype;
begin
  select * into v_li from public.live_items where id = p_live_item_id;
  if v_li.id is null then
    return 0;
  end if;
  v_product := coalesce(v_li.product_id, v_li.checkout_product_id);
  v_avail := public.batata_live_item_available_qty_engine(p_live_item_id);

  -- Close approval_pending rows that can no longer be fulfilled on this item
  -- or sibling listings of same product when available is 0.
  for r in
    select req.id, req.live_item_id, req.requested_qty
    from public.live_reservation_requests req
    join public.live_items li on li.id = req.live_item_id
    where req.status = 'pending'
      and coalesce(req.request_kind, 'approval_pending') = 'approval_pending'
      and (p_except_request_id is null or req.id is distinct from p_except_request_id)
      and (
        req.live_item_id = p_live_item_id
        or (
          v_product is not null
          and coalesce(li.product_id, li.checkout_product_id) = v_product
        )
      )
    for update of req skip locked
  loop
    -- If this pending's qty cannot fit remaining available on its item, close it.
    if public.batata_live_item_available_qty_engine(r.live_item_id) < greatest(r.requested_qty, 1)
       or v_avail <= 0 then
      update public.live_reservation_requests
      set
        status = 'expired',
        expiry_reason = 'stock_unavailable',
        unavailable_at = timezone('utc', now()),
        notes = trim(both ' |' from coalesce(notes, '') || ' | stock_unavailable_closed'),
        updated_at = timezone('utc', now())
      where id = r.id
        and status = 'pending';

      if found then
        v_closed := v_closed + 1;
        perform public.batata_commerce_emit_reservation_event(
          r.id,
          'pending_stock_unavailable',
          jsonb_build_object('closed_by_item', p_live_item_id)
        );
        begin
          perform public.batata_recompact_reservation_queue(r.live_item_id);
          perform public.batata_recompute_live_item_status(r.live_item_id);
        exception when others then
          null;
        end;
      end if;
    end if;
  end loop;

  return v_closed;
end;
$$;

revoke all on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  from public;
grant execute on function public.batata_reserve_with_policy(uuid, uuid, uuid, uuid, integer, text, uuid, boolean, text)
  to authenticated, service_role;

revoke all on function public.batata_close_pending_for_stock(uuid, uuid) from public;
grant execute on function public.batata_close_pending_for_stock(uuid, uuid)
  to service_role;

-- Re-create reserve body now that close_pending exists (already complete above).
-- Ensure PostgREST sees latest.
notify pgrst, 'reload schema';
