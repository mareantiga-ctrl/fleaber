-- =============================================================================
-- BATATA — RTG/F/Indep fixes 20260831 (escolhas utilizador + P1 regressão D0820)
-- P1: cancel hold + review humana (money_cols internal flags + wallet cancel)
-- 1-A: Hub items paused ocultos
-- 2-A: shadow unlist só live activa (sem reserva em ended)
-- 3-A: pairing claim/heartbeat só live activa (arquitectura)
-- 4-A: pairing/OCR accept em draft só admin
-- 5-A: offer/bundle rejeitam SKU morto
-- 6-A: reviews_gerais sem buyer_id alheio
-- 7-A: logout JWT — sem alteração
-- G2: hold guard lock product (race sold)
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper — live «no ar» vs draft vs ended
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_is_broadcasting(p_live_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.lives l
    where l.id = p_live_id
      and coalesce(l.is_active, false) = true
      and lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
  );
$$;

revoke all on function public.batata_live_is_broadcasting(uuid) from public, anon;
grant execute on function public.batata_live_is_broadcasting(uuid)
  to authenticated, service_role;

create or replace function public.batata_live_is_draft(p_live_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.lives l
    where l.id = p_live_id
      and lower(trim(coalesce(l.status, ''))) in ('draft', 'scheduled')
      and not public.batata_live_is_broadcasting(p_live_id)
  );
$$;

revoke all on function public.batata_live_is_draft(uuid) from public, anon;
grant execute on function public.batata_live_is_draft(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- P1 — money_cols: triggers internos podem carimbar release/refund (D0820 fix)
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_paid boolean;
  v_internal boolean := false;
begin
  v_internal :=
    coalesce(current_setting('batata.allow_internal_order_cols', true), '') = '1'
    or coalesce(current_setting('batata.wallet_internal', true), '') = '1';

  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    NEW.stripe_checkout_session_id := null;
    NEW.stripe_payment_intent_id := null;
    NEW.stripe_refund_id := null;
    NEW.amount_paid_cents := null;
    NEW.wallet_release_processed_at := null;
    NEW.auto_feedback_processed_at := null;
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id
     or NEW.seller_id is distinct from OLD.seller_id
     or NEW.product_id is distinct from OLD.product_id
     or NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id
     or NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id
     or NEW.stripe_refund_id is distinct from OLD.stripe_refund_id
     or NEW.amount_paid_cents is distinct from OLD.amount_paid_cents
     or NEW.price_total is distinct from OLD.price_total
     or NEW.contract_unit_cents is distinct from OLD.contract_unit_cents
     or NEW.contract_qty is distinct from OLD.contract_qty
     or NEW.quantity is distinct from OLD.quantity
     or NEW.payment_method is distinct from OLD.payment_method
  then
    raise exception 'order_money_fields_immutable' using errcode = '42501';
  end if;

  if not v_internal then
    if NEW.wallet_release_processed_at is distinct from OLD.wallet_release_processed_at then
      raise exception 'order_wallet_release_flag_immutable' using errcode = '42501';
    end if;
    if NEW.auto_feedback_processed_at is distinct from OLD.auto_feedback_processed_at then
      raise exception 'order_auto_feedback_flag_immutable' using errcode = '42501';
    end if;
    if NEW.wallet_refund_processed_at is distinct from OLD.wallet_refund_processed_at then
      NEW.wallet_refund_processed_at := OLD.wallet_refund_processed_at;
    end if;
    if NEW.stock_units_applied is distinct from OLD.stock_units_applied then
      NEW.stock_units_applied := OLD.stock_units_applied;
    end if;
  end if;

  if NEW.returned_at is distinct from OLD.returned_at then
    NEW.returned_at := OLD.returned_at;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_paid := v_old_st in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  ) or coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';

  if v_paid and NEW.bundle_id is distinct from OLD.bundle_id then
    raise exception 'order_bundle_id_frozen_after_payment' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'RTG-P1: JWT não finge flags; wallet_internal/allow_internal_order_cols OK para release/cancel interno.';

-- P1 — cancel: não carimbar release em hold sem captura; internal flag no UPDATE
create or replace function public.batata_wallet_order_status_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
  v_new text;
  v_had_wallet boolean := false;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if v_new = 'devolvida' then
    perform public.batata_refund_buyer_wallet_for_order(new.id);
  end if;

  if v_new in ('cancelado', 'cancelada', 'cancelled', 'canceled')
     and v_new is distinct from v_old then
    v_had_wallet :=
      new.wallet_release_processed_at is not null
      or exists (
        select 1 from public.wallet_transactions wt
        where wt.order_id = new.id and wt.type = 'venda'
      );

    if v_had_wallet then
      perform public.batata_clawback_seller_wallet_for_order(new.id);
    end if;

    if v_had_wallet
       or new.wallet_refund_processed_at is not null
       or coalesce(new.amount_paid_cents, 0) > 0
       or coalesce(new.stripe_payment_intent_id, '') <> '' then
      perform set_config('batata.allow_internal_order_cols', '1', true);
      update public.orders o
      set wallet_refund_processed_at = coalesce(o.wallet_refund_processed_at, now()),
          wallet_release_processed_at = coalesce(o.wallet_release_processed_at, now())
      where o.id = new.id;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.batata_wallet_order_status_trigger() is
  'RTG-P1: cancel unpaid não toca wallet_release; internal cols no carimbo pós-pago.';

-- G2 — race hold∥sold: lock product row
create or replace function public.batata_orders_guard_product_hold_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_allow text := coalesce(current_setting('batata.raffle_prize_write', true), '');
  v_new text;
  v_old text;
  v_need int;
  v_check jsonb;
  v_sold boolean;
  v_listed boolean;
  v_live_ok boolean;
begin
  if v_allow = '1' then
    return NEW;
  end if;

  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if NEW.product_id is null then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_old := case when TG_OP = 'UPDATE'
    then lower(trim(coalesce(OLD.status, '')))
    else '' end;

  if not public.batata_order_status_holds_product_qty(v_new) then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and public.batata_order_status_holds_product_qty(v_old)
     and v_new is not distinct from v_old then
    return NEW;
  end if;

  perform pg_advisory_xact_lock(
    ('x' || substr(md5(NEW.product_id::text), 1, 15))::bit(60)::bigint
  );

  select coalesce(p.is_sold, false),
         coalesce(p.list_on_marketplace, false)
    into v_sold, v_listed
  from public.products p
  where p.id = NEW.product_id
  for update;

  if not found then
    raise exception 'order_hold_product_missing' using errcode = '23514';
  end if;

  if v_sold then
    raise exception 'order_hold_product_sold' using errcode = '23514';
  end if;

  v_live_ok := public.batata_order_unlist_live_context_ok(
    NEW.product_id,
    NEW.seller_id,
    NEW.live_id,
    NEW.live_item_id
  );

  if not v_listed and not v_live_ok then
    raise exception 'order_hold_product_not_listed' using errcode = '23514';
  end if;

  v_need := greatest(coalesce(NEW.quantity, 1), 1);
  v_check := public.batata_product_checkout_available(
    NEW.product_id,
    NEW.id,
    v_need
  );

  if coalesce((v_check->>'ok')::boolean, false) is not true then
    raise exception 'order_hold_exceeds_stock' using errcode = '23514';
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 1-A — Hub: sem items paused/inactivos
-- ---------------------------------------------------------------------------
create or replace view public.hub_live_items_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_public hl on hl.id = li.live_id
where coalesce(li.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in ('paused', 'inactive', 'sold');

comment on view public.hub_live_items_public is
  'F1-A: só items activos no Hub público (sem paused/inactive).';

grant select on public.hub_live_items_public to anon, authenticated;

create or replace view public.hub_live_items_discovery_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_discovery_public hl on hl.id = li.live_id
where coalesce(li.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in ('paused', 'inactive', 'sold');

grant select on public.hub_live_items_discovery_public to anon, authenticated;

drop policy if exists "live_items_select_for_live" on public.live_items;
create policy "live_items_select_for_live"
  on public.live_items
  for select
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (
          auth.uid() = l.seller_id
          or auth.uid() = l.vendedor_id
          or public.batata_staff_has_permission(
            coalesce(l.seller_id, l.vendedor_id),
            'can_view_live_dashboard'
          )
          or (
            coalesce(live_items.is_active, false) = true
            and lower(trim(coalesce(live_items.status, ''))) not in (
              'paused', 'inactive', 'sold'
            )
            and (
              public.batata_live_is_broadcasting(l.id)
              or exists (
                select 1 from public.hub_lives_public hlp where hlp.id = l.id
              )
            )
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- 2-A — shadow: só live activa (sem reserva em ended)
-- ---------------------------------------------------------------------------
drop policy if exists "products_select_live_checkout_shadow" on public.products;
create policy "products_select_live_checkout_shadow"
  on public.products
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.live_items li
      inner join public.lives l on l.id = li.live_id
      where (
        li.checkout_product_id = products.id
        or li.product_id = products.id
      )
      and public.batata_live_is_broadcasting(l.id)
    )
    or exists (
      select 1
      from public.orders o
      where o.buyer_id = auth.uid()
        and o.product_id = products.id
        and lower(trim(coalesce(o.status, ''))) not in (
          'cancelado', 'cancelled', 'expirado', 'expired'
        )
    )
  );

comment on policy "products_select_live_checkout_shadow" on public.products is
  'F2-A: shadow unlist só live activa + orders activas do buyer (não reserva ended).';

-- ---------------------------------------------------------------------------
-- 3-A + 4-A — pairing: activa OK; draft só admin; ended bloqueado
-- ---------------------------------------------------------------------------
create or replace function public.batata_ps_create_pairing(
  p_live_id uuid,
  p_device_id_hint text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_live public.lives%rowtype;
  v_code text;
  v_token text;
  v_hash text;
  v_device text := coalesce(nullif(trim(p_device_id_hint), ''), 'ps-reader-pc');
  v_attempt int := 0;
  v_is_helper boolean := false;
  v_ttl interval := interval '2 minutes';
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select * into v_live from public.lives where id = p_live_id;
  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  v_seller_id := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_seller_id is distinct from v_uid
     and not public.batata_staff_has_permission(v_seller_id, 'can_manage_reservations') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  if public.batata_live_is_draft(p_live_id)
     and not public.batata_is_admin() then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  if not public.batata_live_is_broadcasting(p_live_id)
     and not (public.batata_live_is_draft(p_live_id) and public.batata_is_admin()) then
    return jsonb_build_object('ok', false, 'error', 'live_ended');
  end if;

  v_is_helper := v_seller_id is distinct from v_uid;

  if v_is_helper and not public.batata_live_is_broadcasting(p_live_id) then
    return jsonb_build_object('ok', false, 'error', 'live_not_active');
  end if;

  update public.ps_pairing_sessions
  set expires_at = least(expires_at, now() - interval '1 second')
  where live_id = p_live_id
    and claimed_at is null
    and expires_at > now();

  loop
    v_attempt := v_attempt + 1;
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (
      select 1 from public.ps_pairing_sessions s
      where s.code = v_code and s.claimed_at is null and s.expires_at > now()
    );
    exit when v_attempt > 20;
  end loop;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

  insert into public.seller_device_tokens (
    seller_id, device_id, token_hash, label, created_by
  ) values (
    v_seller_id,
    v_device,
    v_hash,
    'PS Reader ' || to_char(now(), 'YYYY-MM-DD HH24:MI'),
    v_uid
  )
  on conflict (seller_id, device_id) do update
  set
    token_hash = excluded.token_hash,
    label = excluded.label,
    created_by = excluded.created_by,
    revoked_at = null,
    created_at = now();

  insert into public.ps_pairing_sessions (
    seller_id, live_id, code, device_token_plain, device_id_hint, expires_at
  ) values (
    v_seller_id,
    p_live_id,
    v_code,
    v_token,
    v_device,
    now() + v_ttl
  );

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expires_at', (now() + v_ttl),
    'ttl_seconds', 120,
    'live_id', p_live_id,
    'live_title', coalesce(v_live.title, 'Live'),
    'device_id', v_device,
    'created_by_helper', v_is_helper
  );
end;
$$;

create or replace function public.batata_ps_claim_pairing(
  p_code text,
  p_device_id text,
  p_app_version text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ps_pairing_sessions%rowtype;
  v_ctx jsonb;
  v_device text := coalesce(nullif(trim(coalesce(p_device_id, '')), ''), 'ps-reader-pc');
  v_window timestamptz := date_trunc('hour', now());
  v_hits int := 0;
  v_rate_key text := 'ps_claim:' || lower(v_device);
begin
  insert into public.batata_anon_rate_limits (rate_key, rpc, window_start, hits)
  values (v_rate_key, 'batata_ps_claim_pairing', v_window, 1)
  on conflict (rate_key, rpc, window_start) do update
  set hits = public.batata_anon_rate_limits.hits + 1
  returning hits into v_hits;

  if v_hits > 12 then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  select * into v_row
  from public.ps_pairing_sessions s
  where s.code = trim(coalesce(p_code, ''))
    and s.claimed_at is null
    and s.expires_at > now()
  for update skip locked
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_or_expired_code');
  end if;

  if not public.batata_live_is_broadcasting(v_row.live_id)
     and not (public.batata_live_is_draft(v_row.live_id) and public.batata_is_admin()) then
    return jsonb_build_object('ok', false, 'error', 'live_ended');
  end if;

  update public.ps_pairing_sessions
  set
    claimed_at = now(),
    claimed_device_id = nullif(trim(coalesce(p_device_id, '')), '')
  where id = v_row.id;

  v_ctx := public.batata_ps_live_context(v_row.live_id);

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, paired_at, last_seen_at
  ) values (
    v_row.seller_id,
    v_row.live_id,
    coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint, 'ps-reader-pc'),
    'paired',
    nullif(trim(coalesce(p_app_version, '')), ''),
    now(),
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = excluded.live_id,
    status = 'paired',
    app_version = excluded.app_version,
    paired_at = now(),
    last_seen_at = now();

  return jsonb_build_object(
    'ok', true,
    'live_id', v_row.live_id,
    'device_token', v_row.device_token_plain,
    'device_id', coalesce(nullif(trim(p_device_id), ''), v_row.device_id_hint),
    'seller_id', v_row.seller_id,
    'live_context', v_ctx
  );
end;
$$;

create or replace function public.batata_ps_reader_heartbeat(
  p_device_token text,
  p_live_id uuid,
  p_device_id text,
  p_status text default 'online',
  p_app_version text default null,
  p_last_error text default null,
  p_roi_ok boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth jsonb;
  v_seller_id uuid;
  v_live_seller uuid;
begin
  v_auth := public.batata_validate_seller_device_token(p_device_token);
  if coalesce((v_auth->>'ok')::boolean, false) is not true then
    return v_auth;
  end if;

  v_seller_id := (v_auth->>'seller_id')::uuid;

  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  if not public.batata_live_is_broadcasting(p_live_id)
     and not (public.batata_live_is_draft(p_live_id) and public.batata_is_admin()) then
    return jsonb_build_object('ok', false, 'error', 'live_ended');
  end if;

  select coalesce(l.seller_id, l.vendedor_id) into v_live_seller
  from public.lives l
  where l.id = p_live_id;

  if v_live_seller is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_found');
  end if;

  if v_live_seller is distinct from v_seller_id then
    return jsonb_build_object('ok', false, 'error', 'live_not_owned');
  end if;

  insert into public.ps_reader_heartbeats (
    seller_id, live_id, device_id, status, app_version, last_error, roi_ok, last_seen_at
  ) values (
    v_seller_id,
    p_live_id,
    trim(coalesce(p_device_id, '')),
    coalesce(nullif(trim(p_status), ''), 'online'),
    nullif(trim(coalesce(p_app_version, '')), ''),
    nullif(trim(coalesce(p_last_error, '')), ''),
    p_roi_ok,
    now()
  )
  on conflict (seller_id, device_id) do update
  set
    live_id = coalesce(excluded.live_id, ps_reader_heartbeats.live_id),
    status = excluded.status,
    app_version = coalesce(excluded.app_version, ps_reader_heartbeats.app_version),
    last_error = excluded.last_error,
    roi_ok = excluded.roi_ok,
    last_seen_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

-- 4-A — accept reserva live: draft só admin
create or replace function public.batata_live_reservation_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_is_seller boolean := false;
  v_avail int := 0;
  v_item_qty int := 0;
  v_new_consumes boolean := false;
  v_old_consumes boolean := false;
  v_need_capacity boolean := false;
  v_live_id uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);

  v_live_id := coalesce(
    NEW.live_id,
    (select li.live_id from public.live_items li where li.id = NEW.live_item_id limit 1)
  );

  if v_live_id is not null
     and public.batata_live_reservation_status_consumes_capacity(NEW.status)
     and (
       TG_OP = 'INSERT'
       or not public.batata_live_reservation_status_consumes_capacity(
         public.batata_live_reservation_status_canonical(OLD.status)
       )
     ) then
    if public.batata_live_is_draft(v_live_id) and not public.batata_is_admin() then
      raise exception 'live_not_public' using errcode = '42501';
    end if;
    if not public.batata_live_is_broadcasting(v_live_id)
       and not (public.batata_live_is_draft(v_live_id) and public.batata_is_admin()) then
      raise exception 'live_ended' using errcode = '42501';
    end if;
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
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
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
$fn$;

-- ---------------------------------------------------------------------------
-- 5-A — offers: rejeitar unlist/sold
-- ---------------------------------------------------------------------------
create or replace function public.batata_product_offers_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dead boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if lower(trim(coalesce(NEW.status, ''))) is distinct from 'pending' then
      NEW.status := 'pending';
    end if;
    NEW.responded_at := null;
    if NEW.offered_by = 'buyer' then
      NEW.buyer_id := v_uid;
    elsif NEW.offered_by = 'seller' then
      NEW.seller_id := v_uid;
    end if;
    if coalesce(NEW.amount, 0) <= 0 then
      raise exception 'offer_amount_invalid' using errcode = '23514';
    end if;

    select not exists (
      select 1 from public.products p
      where p.id = NEW.product_id
        and coalesce(p.list_on_marketplace, false) = true
        and coalesce(p.is_sold, false) = false
    ) into v_dead;
    if v_dead then
      raise exception 'offer_product_not_listed' using errcode = '23514';
    end if;
    return NEW;
  end if;

  if NEW.amount is distinct from OLD.amount then
    raise exception 'offer_amount_immutable' using errcode = '42501';
  end if;
  NEW.product_id := OLD.product_id;
  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.offered_by := OLD.offered_by;

  if NEW.status is distinct from OLD.status
     and lower(trim(coalesce(NEW.status, ''))) = 'accepted' then
    select not exists (
      select 1 from public.products p
      where p.id = OLD.product_id
        and coalesce(p.list_on_marketplace, false) = true
        and coalesce(p.is_sold, false) = false
    ) into v_dead;
    if v_dead then
      raise exception 'offer_product_not_listed' using errcode = '23514';
    end if;

    if lower(trim(coalesce(OLD.offered_by, ''))) = 'buyer' then
      if v_uid is distinct from OLD.seller_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    elsif lower(trim(coalesce(OLD.offered_by, ''))) = 'seller' then
      if v_uid is distinct from OLD.buyer_id then
        raise exception 'offer_accept_not_authorized' using errcode = '42501';
      end if;
    else
      raise exception 'offer_accept_not_authorized' using errcode = '42501';
    end if;
    NEW.responded_at := coalesce(NEW.responded_at, now());
    NEW.amount := OLD.amount;
  end if;

  if lower(trim(coalesce(OLD.status, ''))) in (
    'accepted', 'rejected', 'superseded', 'expired'
  ) then
    NEW.amount := OLD.amount;
    NEW.status := OLD.status;
    NEW.responded_at := OLD.responded_at;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_product_offers_guard_authority() is
  'Indep5-A: offer INSERT/accept só em SKU listed+not sold.';

-- 5-A — bundle accept: membros vivos
create or replace function public.batata_product_bundles_guard_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_bad int := 0;
  v_dead int := 0;
  v_new_st text;
  v_old_st text;
  v_sub numeric(12, 2);
  v_pct numeric(5, 2);
  v_disc numeric(12, 2);
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.seller_id is not null and NEW.seller_id = v_uid then
      NEW.seller_id := v_uid;
      if NEW.buyer_id is null or NEW.buyer_id = v_uid then
        raise exception 'bundle_invalid_buyer' using errcode = '23514';
      end if;
      NEW.status := coalesce(nullif(trim(NEW.status), ''), 'pending');
      if lower(trim(NEW.status)) is distinct from 'pending' then
        NEW.status := 'pending';
      end if;
    elsif NEW.buyer_id is null or NEW.buyer_id = v_uid then
      NEW.buyer_id := v_uid;
      if NEW.seller_id is null or NEW.seller_id = v_uid then
        raise exception 'bundle_invalid_seller' using errcode = '23514';
      end if;
      NEW.status := 'pending';
      NEW.discount_pct := 0;
    else
      raise exception 'bundle_party_mismatch' using errcode = '42501';
    end if;

    if NEW.buyer_id = NEW.seller_id then
      raise exception 'bundle_same_party' using errcode = '23514';
    end if;

    if NEW.product_ids is null or coalesce(array_length(NEW.product_ids, 1), 0) < 1 then
      raise exception 'bundle_products_required' using errcode = '23514';
    end if;

    select count(*)::int into v_bad
    from unnest(NEW.product_ids) as pid
    where not exists (
      select 1 from public.products p
      where p.id = pid and p.seller_id = NEW.seller_id
    );
    if v_bad > 0 then
      raise exception 'bundle_product_seller_mismatch' using errcode = '23514';
    end if;

    select count(*)::int into v_dead
    from unnest(NEW.product_ids) as pid
    join public.products p on p.id = pid
    where coalesce(p.list_on_marketplace, false) = false
       or coalesce(p.is_sold, false) = true;
    if v_dead > 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;

    v_sub := public.batata_product_bundles_catalog_subtotal(NEW.product_ids);
    if coalesce(v_sub, 0) <= 0 then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    end if;
    v_pct := least(greatest(coalesce(NEW.discount_pct, 0), 0), 50);
    if v_uid is distinct from NEW.seller_id then
      v_pct := 0;
    end if;
    v_disc := round(v_sub * (v_pct / 100.0), 2);
    NEW.subtotal_eur := v_sub;
    NEW.discount_pct := v_pct;
    NEW.discount_eur := v_disc;
    NEW.total_eur := greatest(v_sub - v_disc, 0);
    return NEW;
  end if;

  NEW.buyer_id := OLD.buyer_id;
  NEW.seller_id := OLD.seller_id;
  NEW.product_ids := OLD.product_ids;

  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := lower(trim(coalesce(OLD.status, '')));

  if v_new_st is distinct from v_old_st then
    if v_new_st = 'accepted' then
      if v_uid is distinct from OLD.seller_id then
        raise exception 'bundle_accept_seller_only' using errcode = '42501';
      end if;
      select count(*)::int into v_dead
      from unnest(OLD.product_ids) as pid
      join public.products p on p.id = pid
      where coalesce(p.list_on_marketplace, false) = false
         or coalesce(p.is_sold, false) = true;
      if v_dead > 0 then
        raise exception 'bundle_product_not_listed' using errcode = '23514';
      end if;
      v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
      if coalesce(v_sub, 0) <= 0 then
        raise exception 'bundle_product_not_listed' using errcode = '23514';
      end if;
    end if;
    if v_new_st in ('rejected', 'cancelled', 'cancelado')
       and v_uid is distinct from OLD.seller_id
       and v_uid is distinct from OLD.buyer_id then
      raise exception 'bundle_status_not_authorized' using errcode = '42501';
    end if;
  end if;

  if v_uid is distinct from OLD.seller_id then
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  else
    v_sub := public.batata_product_bundles_catalog_subtotal(OLD.product_ids);
    if coalesce(v_sub, 0) <= 0 and v_new_st = 'accepted' then
      raise exception 'bundle_product_not_listed' using errcode = '23514';
    elsif coalesce(v_sub, 0) <= 0 then
      NEW.total_eur := OLD.total_eur;
      NEW.subtotal_eur := OLD.subtotal_eur;
      NEW.discount_pct := OLD.discount_pct;
      NEW.discount_eur := OLD.discount_eur;
    else
      v_pct := least(greatest(coalesce(NEW.discount_pct, OLD.discount_pct, 0), 0), 50);
      v_disc := round(v_sub * (v_pct / 100.0), 2);
      NEW.subtotal_eur := v_sub;
      NEW.discount_pct := v_pct;
      NEW.discount_eur := v_disc;
      NEW.total_eur := greatest(v_sub - v_disc, 0);
    end if;
  end if;

  if v_old_st in ('accepted', 'rejected', 'cancelled', 'cancelado', 'expired', 'purchased') then
    NEW.status := OLD.status;
    NEW.total_eur := OLD.total_eur;
    NEW.subtotal_eur := OLD.subtotal_eur;
    NEW.discount_pct := OLD.discount_pct;
    NEW.discount_eur := OLD.discount_eur;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 6-A — reviews: JWT só vê as suas ou onde é target (+ admin)
-- reviews_gerais é VIEW → policy na tabela base reviews
-- ---------------------------------------------------------------------------
drop policy if exists "reviews_select_public_marketplace" on public.reviews;
drop policy if exists "reviews_select_parties" on public.reviews;
create policy "reviews_select_parties"
  on public.reviews
  for select
  to authenticated
  using (
    buyer_id = auth.uid()
    or target_id = auth.uid()
    or public.batata_is_admin()
  );

notify pgrst, 'reload schema';
