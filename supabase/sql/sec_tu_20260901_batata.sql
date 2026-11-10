-- T/U fechos 2026-09-01 — pós-auditorias T + Q re-run + U (SQL parte)
-- P0: parcial disputa em pedido_devolucao+ minta carteira
-- P1: seller não escreve buyer_decision nem fecha resolvida/recusada
-- P1: live_items product_id ∈ dono live; imutável live_id com reserva activa
-- P1: convert fleaber_live exige order pago capturado
-- P1: race convert∥expire — UPDATE condicional + lock item
-- P2: URLs — newline, query wrap, supabase project allowlist staging

-- ---------------------------------------------------------------------------
-- P0 — estender Q8: todos os estados pós-envio / devolução → Stripe
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_remaining numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute public.order_disputes%rowtype;
  v_status text;
  v_platform boolean := false;
  v_captured boolean := false;
begin
  perform set_config('batata.wallet_internal', '1', true);
  perform pg_advisory_xact_lock(
    ('x' || substr(md5(p_order_id::text), 1, 16))::bit(64)::bigint
  );

  if p_order_id is null then return false; end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from v_order.buyer_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  if coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') <> '' then
    raise exception 'stripe_refund_already_exists';
  end if;

  v_status := lower(trim(coalesce(v_order.status, '')));
  if v_status not in (
    'pago', 'enviado', 'entregue', 'concluido',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    raise exception 'order_not_paid_for_refund';
  end if;

  v_platform := public.batata_is_platform_payment(v_order.payment_method);
  v_captured :=
    coalesce(v_order.amount_paid_cents, 0) > 0
    or coalesce(nullif(trim(v_order.stripe_payment_intent_id), ''), '') <> '';

  v_total := public.batata_order_wallet_base_eur(v_order);
  if v_total <= 0 then
    raise exception 'no_platform_funds_for_wallet_refund';
  end if;

  if v_order.wallet_release_processed_at is not null then
    perform public.batata_clawback_seller_wallet_for_order(v_order.id);
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  v_remaining := public.batata_order_wallet_remaining_eur(v_order);
  if v_remaining <= 0 then
    raise exception 'no_wallet_remaining_for_refund';
  end if;

  select * into v_dispute
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and d.seller_refund_percent > 0
    and d.seller_offer_set_by is not null
    and d.seller_offer_set_by = v_order.seller_id
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
    and lower(coalesce(d.seller_offer_type, '')) in (
      'partial_refund', 'return_and_partial_refund'
    )
  order by d.created_at desc limit 1;

  if not found then
    raise exception 'dispute_refund_offer_required';
  end if;

  v_percent := least(greatest(v_dispute.seller_refund_percent, 0), 100);

  if v_percent >= 100
     and v_platform
     and v_captured
     and coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') = '' then
    raise exception 'dispute_full_refund_requires_stripe' using errcode = '42501';
  end if;

  -- T3/Q8: qualquer pós-envio ou ciclo devolução com PI activo → Stripe
  if v_platform
     and v_captured
     and coalesce(nullif(trim(v_order.stripe_refund_id), ''), '') = ''
     and v_status in (
       'enviado', 'entregue', 'concluido',
       'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
       'disputa_devolucao_vendedor'
     ) then
    raise exception 'dispute_partial_refund_requires_stripe' using errcode = '42501';
  end if;

  v_refund := round(least(v_total, v_remaining) * v_percent / 100.0, 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(
    least(v_remaining - v_refund, greatest(v_total - v_refund - v_commission, 0)),
    0
  );

  if v_refund > 0 then
    v_buyer_done := public.batata_credit_wallet_once(
      v_order.buyer_id, v_order.id, v_refund, 'reembolso',
      'Reembolso parcial disputa #' || left(v_order.id::text, 8)
    );
  else
    v_buyer_done := true;
  end if;

  if v_seller_amount > 0 then
    v_seller_done := public.batata_credit_wallet_once(
      v_order.seller_id, v_order.id, v_seller_amount, 'venda',
      'Venda residual após disputa #' || left(v_order.id::text, 8)
    );
  else
    v_seller_done := true;
  end if;

  if v_buyer_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        wallet_release_processed_at = coalesce(wallet_release_processed_at, now())
    where id = v_order.id;
  end if;

  return v_buyer_done and v_seller_done;
end;
$$;

-- ---------------------------------------------------------------------------
-- P1 — disputa: seller não escreve buyer_decision; não fecha terminal
-- ---------------------------------------------------------------------------
create or replace function public.batata_order_disputes_guard_authority()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_st text;
  v_new_st text;
  v_new_turn text;
  v_terminal boolean;
  v_order_seller uuid;
  v_order_buyer uuid;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  v_old_st := lower(trim(coalesce(OLD.status, '')));
  v_new_st := lower(trim(coalesce(NEW.status, '')));
  v_new_turn := lower(trim(coalesce(NEW.current_turn, '')));
  v_terminal := v_new_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  );

  if v_old_st in (
    'resolvida', 'fechada', 'closed', 'resolved', 'recusada',
    'cancelada', 'concluida', 'concluída', 'arquivada'
  ) then
    NEW.seller_refund_percent := OLD.seller_refund_percent;
    NEW.seller_offer_type := OLD.seller_offer_type;
    NEW.seller_pays_return_shipping := OLD.seller_pays_return_shipping;
    NEW.seller_offer_set_by := OLD.seller_offer_set_by;
    NEW.seller_offer_set_at := OLD.seller_offer_set_at;
    NEW.buyer_decision := OLD.buyer_decision;
    NEW.admin_resolution := OLD.admin_resolution;
    NEW.admin_resolution_note := OLD.admin_resolution_note;
    NEW.return_label_url := OLD.return_label_url;
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  select o.seller_id, o.buyer_id
    into v_order_seller, v_order_buyer
  from public.orders o
  where o.id = NEW.order_id
  limit 1;

  -- T5/Q5: vendedor não escreve decisão do comprador
  if v_order_seller = v_uid
     and not public.batata_is_admin()
     and NEW.buyer_decision is distinct from OLD.buyer_decision then
    NEW.buyer_decision := OLD.buyer_decision;
  end if;

  -- T5/Q5: vendedor não fecha resolvida/recusada (só comprador ou admin)
  if v_order_seller = v_uid
     and not public.batata_is_admin()
     and v_new_st in ('resolvida', 'recusada')
     and v_new_st is distinct from v_old_st then
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  if v_new_st = 'escalada_fleaber' then
    NEW.current_turn := 'administracao';
  elsif v_new_turn = 'administracao' and not v_terminal then
    NEW.current_turn := OLD.current_turn;
  end if;

  if v_terminal then
    NEW.current_turn := 'administracao';
  end if;

  if NEW.admin_resolution is distinct from OLD.admin_resolution then
    NEW.admin_resolution := OLD.admin_resolution;
  end if;
  if NEW.admin_resolution_note is distinct from OLD.admin_resolution_note then
    NEW.admin_resolution_note := OLD.admin_resolution_note;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- P1 — live_items: product do dono; live_id imutável com reserva activa
-- ---------------------------------------------------------------------------
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
  v_has_active_res boolean := false;
begin
  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if NEW.live_id is not null then
    select coalesce(l.seller_id, l.vendedor_id)
      into v_live_owner
    from public.lives l
    where l.id = NEW.live_id
    limit 1;
  end if;

  if v_live_owner is not null and v_live_owner is distinct from v_uid
     and not public.batata_is_admin()
     and not public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations') then
    raise exception 'live_item_not_authorized' using errcode = '42501';
  end if;

  if NEW.product_id is not null and v_live_owner is not null then
    select p.seller_id into v_product_seller
    from public.products p
    where p.id = NEW.product_id
    limit 1;
    if v_product_seller is not null and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_product_seller_mismatch' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.live_id is distinct from OLD.live_id then
    select exists(
      select 1 from public.live_reservation_requests r
      where r.live_item_id = NEW.id
        and r.status in ('pending', 'accepted', 'converted')
    ) into v_has_active_res;
    if v_has_active_res then
      raise exception 'live_item_live_id_immutable' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_live_items_guard_authority on public.live_items;
create trigger trg_batata_live_items_guard_authority
  before insert or update on public.live_items
  for each row
  execute function public.batata_live_items_guard_authority();

-- ---------------------------------------------------------------------------
-- P1 — convert fleaber_live: exige order Seguro capturada para este item
-- P1 — race convert∥expire: lock item + UPDATE condicional
-- ---------------------------------------------------------------------------
create or replace function public.batata_process_live_reservation_request(
  p_request_id uuid,
  p_action text,
  p_processed_by uuid default auth.uid(),
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.live_reservation_requests%rowtype;
  v_item_qty int := 0;
  v_reserved_qty int := 0;
  v_sibling_qty int := 0;
  v_final_qty int := 1;
  v_already int := 0;
  v_avail int := 0;
  v_next_status text;
  v_item_status text;
  v_src text;
  v_paid_order uuid;
begin
  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id
  for update;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'request_not_found');
  end if;

  perform pg_advisory_xact_lock(
    hashtext(v_req.live_item_id::text || ':live_res_proc')
  );

  if p_action not in ('accept', 'reject', 'skip', 'expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'invalid_action');
  end if;

  select coalesce(status, '') into v_item_status
  from public.live_items
  where id = v_req.live_item_id;

  if v_item_status = 'sold' and p_action in ('accept', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'item_sold');
  end if;

  if not (
    auth.uid() = v_req.seller_id
    or public.batata_staff_has_permission(v_req.seller_id, 'can_manage_reservations')
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;

  v_src := lower(trim(coalesce(v_req.source, 'fleaber_live')));

  if p_action = 'convert' and v_src in ('fleaber_live', '') then
    select o.id into v_paid_order
    from public.orders o
    where o.live_item_id = v_req.live_item_id
      and o.buyer_id = v_req.buyer_id
      and lower(trim(coalesce(o.status, ''))) in ('pago', 'enviado', 'entregue', 'concluido')
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
    order by o.created_at desc
    limit 1;
    if v_paid_order is null then
      return jsonb_build_object('ok', false, 'error', 'convert_requires_paid_order');
    end if;
  end if;

  if p_action = 'accept' then
    select coalesce(sum(r.requested_qty), 0)::int
    into v_sibling_qty
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.live_id = v_req.live_id
      and r.buyer_id = v_req.buyer_id
      and r.id <> v_req.id
      and r.status = 'pending';

    v_final_qty := greatest(
      coalesce(v_req.requested_qty, 1) + coalesce(v_sibling_qty, 0),
      1
    );

    v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);
    if v_item_qty <= 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'no_stock',
        'available_qty', 0
      );
    end if;

    select coalesce(sum(r.requested_qty), 0)::int
    into v_already
    from public.live_reservation_requests r
    where r.live_item_id = v_req.live_item_id
      and r.status in ('accepted', 'converted')
      and r.id is distinct from v_req.id;

    v_avail := greatest(v_item_qty - v_already, 0);
    if v_final_qty > v_avail then
      return jsonb_build_object(
        'ok', false,
        'error', 'qty_exceeds_stock',
        'available_qty', v_avail,
        'requested', v_final_qty
      );
    end if;

    update public.live_reservation_requests
    set
      status = 'rejected',
      notes = trim(both ' |' from coalesce(notes, '') || ' | superseded:sibling_accept'),
      updated_at = now()
    where live_item_id = v_req.live_item_id
      and live_id = v_req.live_id
      and buyer_id = v_req.buyer_id
      and id <> v_req.id
      and status = 'pending';
  end if;

  update public.live_reservation_requests
  set
    requested_qty = case
      when p_action = 'accept' then v_final_qty
      else requested_qty
    end,
    status = case
      when p_action = 'accept' then 'accepted'
      when p_action = 'reject' then 'rejected'
      when p_action = 'skip' then 'rejected'
      when p_action = 'expire' then 'expired'
      else 'converted'
    end,
    expires_at = case
      when p_action = 'accept' then now() + interval '5 days'
      else expires_at
    end,
    notes = case
      when p_action = 'accept' then trim(both ' |' from regexp_replace(
        regexp_replace(coalesce(notes, ''), 'qty_confirm_needed', '', 'gi'),
        '\s*\|\s*\|', ' | ', 'g'))
      when p_action = 'skip' then coalesce('skip:' || p_notes, 'skip')
      else coalesce(p_notes, notes)
    end,
    processed_by_user_id = coalesce(p_processed_by, auth.uid()),
    updated_at = now()
  where id = v_req.id
    and (
      p_action <> 'expire'
      or lower(trim(coalesce(status, ''))) in ('pending', 'accepted')
    )
    and (
      p_action <> 'convert'
      or lower(trim(coalesce(status, ''))) in ('accepted', 'pending')
    );

  if not found and p_action in ('expire', 'convert') then
    return jsonb_build_object('ok', false, 'error', 'request_state_conflict');
  end if;

  select * into v_req
  from public.live_reservation_requests
  where id = p_request_id;

  if v_item_status = 'sold' then
    return jsonb_build_object(
      'ok', true,
      'request_id', v_req.id,
      'item_status', 'sold'
    );
  end if;

  v_item_qty := public.batata_live_item_total_qty(v_req.live_item_id);

  select coalesce(sum(r.requested_qty), 0)::int
  into v_reserved_qty
  from public.live_reservation_requests r
  where r.live_item_id = v_req.live_item_id
    and r.status in ('accepted', 'converted');

  if p_action in ('reject', 'skip', 'expire') then
    perform public.batata_recompact_reservation_queue(v_req.live_item_id);
  end if;

  perform public.batata_recompute_live_item_status(v_req.live_item_id);

  select coalesce(status, '') into v_next_status
  from public.live_items
  where id = v_req.live_item_id;

  if p_action = 'accept' then
    perform public.batata_live_reservation_accept_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id,
      v_final_qty
    );
  elsif p_action = 'convert' and v_req.status = 'converted' then
    perform public.batata_live_purchase_broadcast(
      v_req.live_id,
      v_req.buyer_id,
      v_req.live_item_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', v_req.id,
    'item_status', v_next_status,
    'reserved_qty', v_reserved_qty,
    'item_qty', v_item_qty
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- P2 — proof_url / label_url: newline, query wrap, supabase project fixo
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_proof_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_url text;
  v_paid boolean;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if NEW.proof_url is not distinct from OLD.proof_url then
    return NEW;
  end if;

  v_paid :=
    lower(trim(coalesce(OLD.status, ''))) in (
      'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    )
    or coalesce(OLD.amount_paid_cents, 0) > 0
    or nullif(trim(coalesce(OLD.stripe_payment_intent_id, '')), '') is not null;

  v_url := lower(trim(coalesce(NEW.proof_url, '')));
  if v_url = '' then
    return NEW;
  end if;

  if v_url ~ '[\n\r]' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;
  if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;
  if v_url ~ '[?&][^#]*https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  if v_paid then
    if not (
      v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'
      or v_url like 'https://fleaber.app/%'
      or v_url like 'https://www.fleaber.app/%'
      or v_url like 'https://fleaber.pt/%'
      or v_url like 'https://www.fleaber.pt/%'
    ) then
      raise exception 'order_proof_url_denied' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

create or replace function public.batata_order_disputes_guard_label_url()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_url text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.return_label_url is not distinct from OLD.return_label_url then
    return NEW;
  end if;

  if TG_OP = 'INSERT' and NEW.return_label_url is null then
    return NEW;
  end if;

  v_url := lower(trim(coalesce(NEW.return_label_url, '')));
  if v_url = '' then
    return NEW;
  end if;

  if v_url ~ '[\n\r]' then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;
  if v_url ~ 'https?://.+/https?://' or v_url ~ '#https?://' then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;
  if v_url ~ '[?&][^#]*https?://' then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;

  if not (
    v_url like 'https://fleaber.app/%'
    or v_url like 'https://www.fleaber.app/%'
    or v_url like 'https://fleaber.pt/%'
    or v_url like 'https://www.fleaber.pt/%'
    or v_url like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'
  ) then
    raise exception 'order_dispute_label_url_denied' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

notify pgrst, 'reload schema';
