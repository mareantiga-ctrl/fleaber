-- AB / AC / AD 2026-09-01 — fecho pós-refutação YZAA (P0–P3, sem P4)
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- AB-P1 — não inflacionar stock com holds activos (só stock_units_applied)
-- ---------------------------------------------------------------------------
create or replace function public.batata_products_guard_quantity_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_held int := 0;
  v_hold_units int := 0;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.quantity is not distinct from OLD.quantity then
    return NEW;
  end if;
  if NEW.seller_id is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_staff_has_permission(NEW.seller_id, 'can_manage_reservations') then
    NEW.quantity := OLD.quantity;
    return NEW;
  end if;

  select coalesce(sum(coalesce(o.stock_units_applied, o.quantity, 1)), 0)::int
    into v_held
  from public.orders o
  where o.product_id = NEW.id
    and coalesce(o.stock_units_applied, 0) > 0
    and lower(trim(coalesce(o.status, ''))) not in (
      'cancelado', 'cancelada', 'cancelled', 'canceled',
      'devolvida', 'concluido'
    );

  select coalesce(sum(greatest(coalesce(o.quantity, 1), 1)), 0)::int
    into v_hold_units
  from public.orders o
  where o.product_id = NEW.id
    and public.batata_order_status_holds_product_qty(o.status);

  if (v_held > 0 or v_hold_units > 0) and NEW.quantity > OLD.quantity then
    raise exception 'product_quantity_increase_blocked_active_order'
      using errcode = '42501';
  end if;

  if NEW.quantity < 0 then
    raise exception 'product_quantity_invalid' using errcode = '23514';
  end if;

  if v_held > 0 and coalesce(NEW.quantity, 0) < coalesce(OLD.quantity, 0)
     and coalesce(NEW.quantity, 0) = 0 then
    raise exception 'product_quantity_below_held' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AD-P1 — converted exige order paga (accepted→converted e INSERT seller)
-- ---------------------------------------------------------------------------
create or replace function public.batata_live_reservation_force_pending_manual()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') = 'authenticated'
     and NEW.source in ('facebook_manual', 'helper_manual', 'fleaber_live')
     and public.batata_live_reservation_status_consumes_capacity(NEW.status) then
    NEW.status := 'pending';
  end if;
  return NEW;
end;
$$;

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
  v_item_live_id uuid;
  v_live_owner uuid;
  v_paid_order uuid;
  v_new_st text;
  v_old_st text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.requested_qty is null or NEW.requested_qty < 1 then
    raise exception 'invalid_requested_qty' using errcode = '23514';
  end if;

  NEW.status := public.batata_live_reservation_status_canonical(NEW.status);
  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_old_st := case
    when TG_OP = 'UPDATE' then lower(trim(coalesce(OLD.status, '')))
    else ''
  end;

  if NEW.live_item_id is not null then
    select li.live_id into v_item_live_id
    from public.live_items li where li.id = NEW.live_item_id limit 1;
    if v_item_live_id is null then
      raise exception 'live_item_not_found' using errcode = '23503';
    end if;
    if NEW.live_id is not null and NEW.live_id is distinct from v_item_live_id then
      raise exception 'live_item_live_mismatch' using errcode = '42501';
    end if;
    NEW.live_id := coalesce(NEW.live_id, v_item_live_id);
  end if;

  v_live_id := NEW.live_id;
  select coalesce(l.seller_id, l.vendedor_id) into v_live_owner
  from public.lives l where l.id = v_live_id limit 1;
  if v_live_owner is not null then
    NEW.seller_id := v_live_owner;
  end if;

  v_new_consumes := public.batata_live_reservation_status_consumes_capacity(NEW.status);
  v_old_consumes := case
    when TG_OP = 'UPDATE' then public.batata_live_reservation_status_consumes_capacity(OLD.status)
    else false
  end;

  if v_live_id is not null and v_new_consumes
     and (TG_OP = 'INSERT' or not v_old_consumes) then
    if public.batata_live_is_draft(v_live_id) and not public.batata_is_admin() then
      raise exception 'live_not_public' using errcode = '42501';
    end if;
    if not public.batata_live_is_broadcasting(v_live_id)
       and not (public.batata_live_is_draft(v_live_id) and public.batata_is_admin()) then
      raise exception 'live_ended' using errcode = '42501';
    end if;
  end if;

  v_is_seller :=
    (v_live_owner is not null and v_live_owner = v_uid)
    or (
      v_live_owner is not null
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations')
    );

  if TG_OP = 'INSERT' then
    if not v_is_seller then
      NEW.status := 'pending';
      NEW.buyer_id := coalesce(NEW.buyer_id, v_uid);
      if NEW.buyer_id is distinct from v_uid then
        raise exception 'reservation_buyer_mismatch' using errcode = '42501';
      end if;
      v_item_qty := coalesce(public.batata_live_item_total_qty(NEW.live_item_id), 0);
      if v_item_qty < 1 then v_item_qty := 1; end if;
      if NEW.requested_qty > v_item_qty then NEW.requested_qty := v_item_qty; end if;
      if NEW.requested_qty > 20 then NEW.requested_qty := 20; end if;
      return NEW;
    end if;
    if NEW.requested_qty > 99 then
      raise exception 'invalid_requested_qty' using errcode = '23514';
    end if;
    if v_new_st = 'converted' then
      raise exception 'convert_requires_paid_order' using errcode = '42501';
    end if;
    if v_new_consumes then
      perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
      v_avail := public.batata_live_reservation_accept_available(NEW.live_item_id, null);
      if NEW.requested_qty > v_avail then
        raise exception 'qty_exceeds_stock' using errcode = '23514';
      end if;
    end if;
    return NEW;
  end if;

  if not v_is_seller and NEW.buyer_id = v_uid then
    if NEW.status is distinct from public.batata_live_reservation_status_canonical(OLD.status) then
      NEW.status := public.batata_live_reservation_status_canonical(OLD.status);
    end if;
    if NEW.requested_qty is distinct from OLD.requested_qty then
      NEW.requested_qty := OLD.requested_qty;
    end if;
    NEW.seller_id := OLD.seller_id;
    return NEW;
  end if;

  if v_new_consumes and not v_old_consumes then
    if not v_is_seller then
      raise exception 'reservation_accept_not_authorized' using errcode = '42501';
    end if;
  end if;

  if v_new_st = 'converted' and v_old_st is distinct from 'converted' then
    select o.id into v_paid_order
    from public.orders o
    where o.live_item_id = NEW.live_item_id
      and o.buyer_id = NEW.buyer_id
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'entregue', 'concluido'
      )
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
    order by o.created_at desc
    limit 1;
    if v_paid_order is null then
      raise exception 'convert_requires_paid_order' using errcode = '42501';
    end if;
    NEW.processed_by_user_id := coalesce(NEW.processed_by_user_id, v_uid);
  end if;

  v_need_capacity := v_new_consumes
    and ((not v_old_consumes) or (NEW.requested_qty > coalesce(OLD.requested_qty, 0)));

  if v_need_capacity then
    if NEW.live_item_id is null then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext(NEW.live_item_id::text || ':live_res_cap'));
    v_avail := public.batata_live_reservation_accept_available(NEW.live_item_id, NEW.id);
    if NEW.requested_qty > v_avail then
      raise exception 'qty_exceeds_stock' using errcode = '23514';
    end if;
  end if;

  NEW.seller_id := coalesce(v_live_owner, OLD.seller_id);
  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AD-P2 — discovery Hub: esconder item esgotado; PATCH status=sold só via RPC
-- ---------------------------------------------------------------------------
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
  and coalesce(li.quantity, 0) > 0
  and lower(trim(coalesce(li.status, ''))) not in ('paused', 'inactive', 'sold')
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

grant select on public.hub_live_items_discovery_public to anon, authenticated;

-- Patch live_items guard: status=sold directo bloqueado (usar mark_sold RPC)
create or replace function public.batata_live_items_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_live_owner uuid;
  v_product_seller uuid;
  v_has_any_res boolean := false;
  v_reserved int := 0;
  v_prod_qty int;
  v_is_staff boolean := false;
  v_can_mark boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and lower(trim(coalesce(NEW.status, ''))) = 'sold'
     and lower(trim(coalesce(OLD.status, ''))) is distinct from 'sold'
     and v_role is distinct from 'service_role' then
    raise exception 'live_item_status_sold_rpc_only' using errcode = '42501';
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id) into v_live_owner
    from public.lives l where l.id = NEW.live_id limit 1;
  end if;

  if v_live_owner is not null then
    v_is_staff := v_live_owner is distinct from v_uid
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations');
    v_can_mark := v_live_owner = v_uid
      or public.batata_staff_has_permission(v_live_owner, 'can_mark_items_sold');
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin() and not v_is_staff then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and not v_can_mark then
    raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
  end if;

  if TG_OP = 'UPDATE' and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
    ) into v_has_any_res;
    if v_has_any_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id, p.quantity into v_product_seller, v_prod_qty
    from public.products p where p.id = NEW.product_id limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
    if v_prod_qty is not null and coalesce(NEW.quantity, 0) > v_prod_qty then
      raise exception 'live_item_qty_exceeds_product' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE' and NEW.id is not null then
    select coalesce(sum(r.requested_qty), 0)::int into v_reserved
    from public.live_reservation_requests r
    where r.live_item_id = NEW.id
      and r.status in ('pending', 'accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AC — chat: unicode/raw JSON, inbox INSERT, cards vs BD, URLs
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_strip_unicode_ws(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    replace(coalesce(p_text, ''), U&'\FEFF', ''),
    '[' || chr(9) || chr(10) || chr(13) || chr(32) || chr(160) || chr(133)
      || chr(8192) || chr(8193) || chr(8194) || chr(8195) || chr(8196)
      || chr(8197) || chr(8198) || chr(8199) || chr(8200) || chr(8201)
      || chr(8202) || chr(8239) || chr(8287) || chr(12288) || ']+',
    '',
    'g'
  );
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* '(Seguro Fleaber|Compra paga|MB WAY|PIX).*(\d+[,.]?\d*\s*€|€\s*\d+)';
$$;

create or replace function public.batata_chats_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if not (NEW.user_a = v_uid or NEW.user_b = v_uid) then
    return NEW;
  end if;
  if public.batata_chat_is_forged_inbox_preview(NEW.last_message) then
    raise exception 'chat_inbox_preview_forbidden' using errcode = '42501';
  end if;
  if NEW.last_message_time is not null
     and NEW.last_message_time < now() - interval '2 minutes' then
    NEW.last_message_time := now();
  end if;
  if NEW.last_message_time is not null
     and NEW.last_message_time > now() + interval '5 minutes' then
    NEW.last_message_time := now();
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_chats_guard_insert on public.chats;
create trigger trg_batata_chats_guard_insert
  before insert on public.chats
  for each row
  execute function public.batata_chats_guard_insert();

create or replace function public.batata_chats_guard_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;
  if not public.batata_chat_is_participant(NEW.id) then
    return NEW;
  end if;
  if NEW.last_message is distinct from OLD.last_message
     and public.batata_chat_is_forged_inbox_preview(NEW.last_message) then
    raise exception 'chat_inbox_preview_forbidden' using errcode = '42501';
  end if;
  if NEW.last_message_time is distinct from OLD.last_message_time then
    if NEW.last_message_time < now() - interval '2 minutes'
       or NEW.last_message_time > now() + interval '5 minutes' then
      NEW.last_message_time := now();
    end if;
  end if;
  return NEW;
end;
$fn$;

create or replace function public.batata_chat_messages_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_norm text;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  NEW.sender_id := v_uid;
  NEW.created_at := now();
  NEW.text := replace(coalesce(NEW.text, ''), U&'\FEFF', '');
  v_norm := public.batata_chat_strip_unicode_ws(NEW.text);

  if v_norm like '{%' and NEW.text not like 'FLEABER_JSON_V1:%' then
    raise exception 'chat_system_card_prefix_required' using errcode = '42501';
  end if;

  if public.batata_chat_is_forged_seguro_plain(NEW.text) then
    raise exception 'chat_seguro_legacy_plain_forbidden' using errcode = '42501';
  end if;

  perform public.batata_chat_messages_assert_json_card(
    NEW.chat_id, NEW.sender_id, NEW.text
  );
  return NEW;
end;
$fn$;

-- assert_json_card — patches AC1/AC4 (full replace from yzaa_complete + AC deltas)
-- NOTE: deployed as separate patch file continuation below

notify pgrst, 'reload schema';
-- AB/AC/AD part2 — assert_json_card AC patches
create or replace function public.batata_chat_messages_assert_json_card(
  p_chat_id uuid,
  p_sender_id uuid,
  p_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_raw text := replace(coalesce(p_text, ''), U&'\FEFF', '');
  v_json jsonb;
  v_kind text;
  v_oid uuid;
  v_order_seller uuid;
  v_order_buyer uuid;
  v_order_status text;
  v_paid_cents int;
  v_pi text;
  v_refund text;
  v_order_total numeric;
  v_res_exp timestamptz;
  v_chat_a uuid;
  v_chat_b uuid;
  v_needs_order boolean;
  v_needs_paid boolean;
  v_captured boolean;
  v_payload_total numeric;
  v_payload_amount numeric;
  v_outcome text;
  v_bundle_id uuid;
  v_bundle_total numeric;
  v_offer_id uuid;
  v_offer_amount numeric;
  v_offer_status text;
  v_url text;
  v_path text;
  v_has_dispute boolean;
  v_has_review boolean;
  v_review_stars int;
  v_payload_stars int;
  v_label text;
begin
  if v_raw not like 'FLEABER_JSON_V1:%' then
    if public.batata_chat_strip_unicode_ws(v_raw) like '{%'
       or btrim(v_raw) like '{%' then
      raise exception 'chat_system_card_prefix_required' using errcode = '42501';
    end if;
    return;
  end if;

  begin
    v_json := substring(v_raw from length('FLEABER_JSON_V1:') + 1)::jsonb;
  exception when others then
    raise exception 'chat_system_card_invalid_json' using errcode = '23514';
  end;

  v_kind := lower(trim(coalesce(v_json->>'kind', '')));
  if v_kind = '' then
    raise exception 'chat_system_card_kind_required' using errcode = '23514';
  end if;

  if v_kind in (
    'marketplace_bag_paid', 'auto_feedback_generated',
    'raffle_prize', 'premio_rifa', 'order_paid'
  ) then
    raise exception 'chat_system_card_server_only' using errcode = '42501';
  end if;

  select c.user_a, c.user_b into v_chat_a, v_chat_b
  from public.chats c where c.id = p_chat_id;
  if not found then
    raise exception 'chat_system_card_chat_missing' using errcode = '23514';
  end if;
  if p_sender_id is distinct from v_chat_a and p_sender_id is distinct from v_chat_b then
    raise exception 'chat_system_card_not_participant' using errcode = '42501';
  end if;

  v_needs_order := v_kind in (
    'reservation_seller_confirmed_receipt', 'reservation_cancelled_by_seller',
    'bundle_reservation_cancelled_by_seller', 'reservation_order_shipped',
    'reservation_accepted', 'reservation_request_outcome', 'price_offer_outcome',
    'cancel_request_outcome', 'bundle_direct_payment_details',
    'order_direct_payment_details', 'bundle_buyer_confirmed_receipt',
    'reservation_payment_submitted', 'reservation_request',
    'reservation_order_completed', 'cancel_request', 'order_review_submitted',
    'seguro_fleaber_paid', 'price_offer', 'order_dispute_opened'
  );
  v_needs_paid := v_kind in (
    'seguro_fleaber_paid', 'reservation_order_shipped', 'reservation_order_completed',
    'reservation_seller_confirmed_receipt', 'bundle_buyer_confirmed_receipt'
  );

  begin
    v_oid := nullif(trim(coalesce(v_json->>'order_id', '')), '')::uuid;
  exception when others then
    v_oid := null;
  end;
  if v_needs_order and v_oid is null then
    raise exception 'chat_system_card_order_id_required' using errcode = '23514';
  end if;

  if v_oid is not null then
    select o.seller_id, o.buyer_id, o.status,
           coalesce(o.amount_paid_cents, 0),
           coalesce(o.stripe_payment_intent_id, ''),
           coalesce(o.stripe_refund_id, ''),
           o.price_total, o.reservation_expires_at
      into v_order_seller, v_order_buyer, v_order_status, v_paid_cents, v_pi, v_refund,
           v_order_total, v_res_exp
    from public.orders o where o.id = v_oid;
    if not found then
      raise exception 'chat_system_card_order_missing' using errcode = '23514';
    end if;
    if not (
      (v_order_seller is not distinct from v_chat_a and v_order_buyer is not distinct from v_chat_b)
      or (v_order_seller is not distinct from v_chat_b and v_order_buyer is not distinct from v_chat_a)
    ) then
      raise exception 'chat_system_card_order_chat_mismatch' using errcode = '23514';
    end if;

    v_captured := v_paid_cents > 0 or nullif(trim(v_pi), '') is not null;
    if v_needs_paid then
      if v_kind = 'seguro_fleaber_paid' then
        if not v_captured then
          raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
        end if;
        begin
          v_payload_total := nullif(trim(coalesce(v_json->>'total', '')), '')::numeric;
        exception when others then
          v_payload_total := null;
        end;
        if v_payload_total is null
           or abs(v_payload_total - round(v_paid_cents::numeric / 100.0, 2)) > 0.02 then
          raise exception 'chat_system_card_total_mismatch' using errcode = '23514';
        end if;
        v_label := coalesce(v_json->>'label', '');
        if v_label ~* '(Seguro|PIX|MB WAY|Compra paga).*\d+[,.]\d+\s*€'
           and abs(
             coalesce(
               nullif(regexp_replace(v_label, '[^0-9,.]', '', 'g'), '')::numeric,
               0
             ) - round(v_paid_cents::numeric / 100.0, 2)
           ) > 0.05 then
          raise exception 'chat_system_card_label_mismatch' using errcode = '23514';
        end if;
      elsif not (
        v_captured
        or lower(trim(coalesce(v_order_status, ''))) in (
          'pago', 'enviado', 'entregue', 'concluido',
          'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
          'disputa_devolucao_vendedor', 'devolvida'
        )
      ) then
        raise exception 'chat_system_card_order_not_paid' using errcode = '23514';
      end if;
    end if;

    if v_kind in ('order_direct_payment_details', 'bundle_direct_payment_details') then
      begin
        v_payload_amount := nullif(trim(coalesce(v_json->>'amount_eur', '')), '')::numeric;
      exception when others then
        v_payload_amount := null;
      end;
      if v_payload_amount is null
         or abs(v_payload_amount - coalesce(v_order_total, 0)) > 0.02 then
        raise exception 'chat_system_card_amount_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_payment_submitted' then
      v_url := lower(trim(coalesce(v_json->>'proof_url', '')));
      if v_url <> '' then
        if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
           or v_url ~ '[\n\r]' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url ~ '[?&][^#]*https?://' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if v_url like '%/object/public/%' then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
        if not (
          v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/%'
          or v_url like 'https://fleaber.app/%'
          or v_url like 'https://www.fleaber.app/%'
          or v_url like 'https://fleaber.pt/%'
          or v_url like 'https://www.fleaber.pt/%'
        ) then
          raise exception 'chat_system_card_url_denied' using errcode = '23514';
        end if;
      end if;
    end if;

    if v_kind = 'reservation_order_shipped'
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'enviado', 'entregue', 'concluido', 'pedido_devolucao',
         'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor', 'devolvida'
       ) then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;
    if v_kind = 'reservation_seller_confirmed_receipt'
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'entregue', 'concluido', 'pedido_devolucao', 'em_devolucao',
         'devolucao_entregue', 'disputa_devolucao_vendedor', 'devolvida'
       ) then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;
    if v_kind = 'reservation_order_completed'
       and lower(trim(coalesce(v_order_status, ''))) <> 'concluido' then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;
    if v_kind in ('reservation_cancelled_by_seller', 'bundle_reservation_cancelled_by_seller')
       and lower(trim(coalesce(v_order_status, ''))) not in (
         'cancelado', 'cancelled', 'canceled'
       ) and nullif(trim(v_refund), '') is null then
      raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
    end if;

    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    if v_kind = 'cancel_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'cancelado', 'cancelled', 'canceled'
      ) and nullif(trim(v_refund), '') is null then
        raise exception 'chat_system_card_cancel_not_refunded' using errcode = '23514';
      end if;
    end if;
    if v_kind = 'cancel_request_outcome' and v_outcome = 'rejected' then
      if lower(trim(coalesce(v_order_status, ''))) in (
        'cancelado', 'cancelled', 'canceled'
      ) or nullif(trim(v_refund), '') is not null then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_request_outcome' and v_outcome = 'accepted' then
      if lower(trim(coalesce(v_order_status, ''))) not in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'reserva_pendente'
      ) then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
      end if;
    end if;
    if v_kind = 'reservation_request_outcome' and v_outcome = 'rejected' then
      if lower(trim(coalesce(v_order_status, ''))) in (
        'reservado', 'aguarda_confirmacao', 'aguarda_pagamento', 'reserva_pendente', 'pago'
      ) then
        raise exception 'chat_system_card_status_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'order_dispute_opened' then
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = v_oid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not coalesce(v_has_dispute, false) then
        raise exception 'chat_system_card_dispute_missing' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'order_review_submitted' then
      select exists(
        select 1 from public.reviews r where r.order_id = v_oid
      ) into v_has_review;
      if not coalesce(v_has_review, false) then
        raise exception 'chat_system_card_review_missing' using errcode = '23514';
      end if;
      select coalesce(r.stars, 0) into v_review_stars
      from public.reviews r where r.order_id = v_oid
      order by r.created_at desc
      limit 1;
      begin
        v_payload_stars := nullif(trim(coalesce(v_json->>'stars', '')), '')::int;
      exception when others then
        v_payload_stars := null;
      end;
      if v_payload_stars is null or v_payload_stars is distinct from v_review_stars then
        raise exception 'chat_system_card_review_stars_mismatch' using errcode = '23514';
      end if;
    end if;

    if v_kind = 'reservation_accepted' and v_res_exp is not null then
      begin
        if nullif(trim(coalesce(v_json->>'expires_at', '')), '')::timestamptz
           is distinct from v_res_exp then
          raise exception 'chat_system_card_expires_mismatch' using errcode = '23514';
        end if;
      exception when others then
        raise exception 'chat_system_card_expires_mismatch' using errcode = '23514';
      end;
    end if;

    if v_kind in (
      'reservation_seller_confirmed_receipt', 'reservation_cancelled_by_seller',
      'bundle_reservation_cancelled_by_seller', 'reservation_order_shipped',
      'reservation_accepted', 'reservation_request_outcome', 'price_offer_outcome',
      'cancel_request_outcome', 'bundle_direct_payment_details', 'order_direct_payment_details'
    ) and p_sender_id is distinct from v_order_seller then
      raise exception 'chat_system_card_seller_only' using errcode = '42501';
    end if;
    if v_kind in (
      'bundle_buyer_confirmed_receipt', 'reservation_payment_submitted',
      'reservation_request', 'reservation_order_completed', 'cancel_request',
      'order_review_submitted', 'seguro_fleaber_paid', 'price_offer'
    ) and p_sender_id is distinct from v_order_buyer then
      raise exception 'chat_system_card_buyer_only' using errcode = '42501';
    end if;
    if v_kind = 'order_dispute_opened'
       and p_sender_id is distinct from v_order_buyer
       and p_sender_id is distinct from v_order_seller then
      raise exception 'chat_system_card_party_only' using errcode = '42501';
    end if;
  end if;

  if v_kind = 'price_offer' then
    begin
      v_offer_id := nullif(trim(coalesce(v_json->>'offer_id', '')), '')::uuid;
    exception when others then
      v_offer_id := null;
    end;
    if v_offer_id is null then
      raise exception 'chat_system_card_offer_id_required' using errcode = '23514';
    end if;
    select po.amount, lower(trim(coalesce(po.status, '')))
      into v_offer_amount, v_offer_status
    from public.product_offers po where po.id = v_offer_id;
    if not found then
      raise exception 'chat_system_card_offer_missing' using errcode = '23514';
    end if;
    if v_offer_status not in ('pending', 'accepted') then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
    end if;
    begin
      v_payload_amount := nullif(trim(coalesce(v_json->>'amount', '')), '')::numeric;
    exception when others then
      v_payload_amount := null;
    end;
    if v_payload_amount is null
       or abs(v_payload_amount - coalesce(v_offer_amount, 0)) > 0.02 then
      raise exception 'chat_system_card_offer_amount_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'price_offer_outcome' then
    begin
      v_offer_id := nullif(trim(coalesce(v_json->>'offer_id', '')), '')::uuid;
    exception when others then
      v_offer_id := null;
    end;
    if v_offer_id is null then
      raise exception 'chat_system_card_offer_id_required' using errcode = '23514';
    end if;
    v_outcome := lower(trim(coalesce(v_json->>'outcome', '')));
    select po.amount, lower(trim(coalesce(po.status, '')))
      into v_offer_amount, v_offer_status
    from public.product_offers po where po.id = v_offer_id;
    if not found then
      raise exception 'chat_system_card_offer_missing' using errcode = '23514';
    end if;
    if v_outcome = 'accepted' and v_offer_status is distinct from 'accepted' then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
    end if;
    if v_outcome = 'rejected'
       and v_offer_status not in ('rejected', 'declined', 'cancelled', 'canceled', 'cancelado') then
      raise exception 'chat_system_card_offer_status_mismatch' using errcode = '23514';
    end if;
    begin
      v_payload_amount := nullif(trim(coalesce(v_json->>'amount', '')), '')::numeric;
    exception when others then
      v_payload_amount := null;
    end;
    if v_payload_amount is null
       or abs(v_payload_amount - coalesce(v_offer_amount, 0)) > 0.02 then
      raise exception 'chat_system_card_offer_amount_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'bundle_proposal' then
    begin
      v_bundle_id := nullif(trim(coalesce(v_json->>'bundle_id', '')), '')::uuid;
    exception when others then
      v_bundle_id := null;
    end;
    if v_bundle_id is null then
      raise exception 'chat_system_card_bundle_id_required' using errcode = '23514';
    end if;
    begin
      v_payload_total := nullif(trim(coalesce(v_json->>'total_eur', '')), '')::numeric;
    exception when others then
      v_payload_total := null;
    end;
    select b.total_eur into v_bundle_total from public.product_bundles b where b.id = v_bundle_id;
    if not found then
      raise exception 'chat_system_card_bundle_missing' using errcode = '23514';
    end if;
    if v_payload_total is null
       or abs(v_payload_total - coalesce(v_bundle_total, 0)) > 0.02 then
      raise exception 'chat_system_card_bundle_total_mismatch' using errcode = '23514';
    end if;
  end if;

  if v_kind = 'chat_image' then
    v_path := trim(coalesce(v_json->>'path', ''));
    if v_path = '' or v_path like '%..%' or position(chr(92) in v_path) > 0
       or v_path like '%\%%' then
      raise exception 'chat_system_card_path_denied' using errcode = '23514';
    end if;
    if v_path not like ('chat_uploads/' || p_sender_id::text || '/%') then
      raise exception 'chat_system_card_path_denied' using errcode = '23514';
    end if;
    v_url := lower(trim(coalesce(v_json->>'url', '')));
    if v_url <> '' then
      if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
         or v_url ~ '[\n\r]' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
      if not v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
        raise exception 'chat_system_card_url_denied' using errcode = '23514';
      end if;
    end if;
  end if;

  if v_kind not in (
    'chat_image', 'bundle_proposal', 'bundle_direct_payment_details',
    'order_direct_payment_details', 'price_offer', 'price_offer_outcome',
    'reservation_accepted', 'reservation_request', 'reservation_request_outcome',
    'bundle_buyer_confirmed_receipt', 'cancel_request', 'cancel_request_outcome',
    'order_dispute_opened', 'order_review_submitted',
    'reservation_cancelled_by_seller', 'bundle_reservation_cancelled_by_seller',
    'reservation_order_completed', 'reservation_order_shipped',
    'reservation_payment_submitted', 'reservation_seller_confirmed_receipt',
    'seguro_fleaber_paid'
  ) then
    raise exception 'chat_system_card_kind_denied' using errcode = '42501';
  end if;
end;
$fn$;

notify pgrst, 'reload schema';
