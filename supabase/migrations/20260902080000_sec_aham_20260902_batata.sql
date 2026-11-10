-- AH–AM 2026-09-02 — fecho P0–P3 pós-refutação AEAFAG
-- production_touched: false · fase4: false

-- ---------------------------------------------------------------------------
-- AJ-P1 — mark_sold live_only: não deslista produto alheio / sem PI
-- ---------------------------------------------------------------------------
create or replace function public.batata_mark_live_item_sold(p_live_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_li public.live_items%rowtype;
  v_live public.lives%rowtype;
  v_seller uuid;
  v_uid uuid;
  v_role text := coalesce(auth.role(), '');
  v_has_paid boolean := false;
  v_checkout_seller uuid;
begin
  select li.* into v_li from public.live_items li where li.id = p_live_item_id;
  if v_li.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_item_not_found');
  end if;

  select * into v_live from public.lives where id = v_li.live_id;
  v_seller := coalesce(v_live.seller_id, v_live.vendedor_id);

  if v_role is distinct from 'service_role' then
    v_uid := auth.uid();
    if v_uid is null or v_role is distinct from 'authenticated' then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
    if v_uid is distinct from v_seller
       and not public.batata_staff_has_permission(v_seller, 'can_mark_items_sold') then
      return jsonb_build_object('ok', false, 'error', 'not_allowed');
    end if;
  end if;

  select exists (
    select 1 from public.orders o
    where o.live_item_id = v_li.id
      and lower(trim(coalesce(o.status, ''))) in (
        'pago', 'enviado', 'entregue', 'concluido'
      )
      and (
        coalesce(o.amount_paid_cents, 0) > 0
        or coalesce(nullif(trim(o.stripe_payment_intent_id), ''), '') <> ''
      )
  ) into v_has_paid;

  if v_li.product_id is not null
     or lower(trim(coalesce(v_li.item_kind, ''))) = 'marketplace_product' then
    if coalesce(v_has_paid, false) then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.product_id
        and seller_id is not distinct from v_seller;
      if v_li.checkout_product_id is not null
         and v_li.checkout_product_id is distinct from v_li.product_id then
        update public.products
        set is_sold = true, list_on_marketplace = false
        where id = v_li.checkout_product_id
          and seller_id is not distinct from v_seller;
      end if;
    end if;
  elsif v_li.checkout_product_id is not null then
    -- live_only: só deslista checkout_product do próprio vendedor E com PI/pago
    select p.seller_id into v_checkout_seller
    from public.products p where p.id = v_li.checkout_product_id;
    if v_checkout_seller is not distinct from v_seller
       and coalesce(v_has_paid, false) then
      update public.products
      set is_sold = true, list_on_marketplace = false
      where id = v_li.checkout_product_id;
    end if;
  end if;

  update public.live_reservation_requests
  set status = 'expired',
      notes = coalesce(notes || ' | ', '') || 'auto:item_vendido',
      updated_at = now()
  where live_item_id = v_li.id
    and status in ('pending', 'accepted');

  perform set_config('batata.mark_sold_internal', '1', true);
  update public.live_items
  set status = 'sold', updated_at = now()
  where id = v_li.id;
  perform set_config('batata.mark_sold_internal', '', true);

  perform public.batata_recompute_live_item_status(v_li.id);

  return public.batata_live_item_stock(v_li.id);
end;
$$;

-- AJ-P3 — INSERT status=sold bloqueado (só UPDATE via RPC)
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
  v_mark_sold_internal boolean := false;
  v_kind text;
begin
  v_mark_sold_internal :=
    coalesce(current_setting('batata.mark_sold_internal', true), '') = '1';

  if v_role is distinct from 'authenticated' or v_uid is null then
    return NEW;
  end if;

  if lower(trim(coalesce(NEW.status, ''))) = 'sold'
     and (
       TG_OP = 'INSERT'
       or lower(trim(coalesce(OLD.status, ''))) is distinct from 'sold'
     )
     and not v_mark_sold_internal
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

  v_kind := lower(trim(coalesce(NEW.item_kind, '')));

  if TG_OP = 'UPDATE'
     and coalesce(NEW.quantity, 0) > coalesce(OLD.quantity, 0)
     and v_role is distinct from 'service_role' then
    if NEW.product_id is null
       and v_kind in ('', 'live_only') then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    elsif not v_can_mark then
      raise exception 'live_item_qty_increase_not_allowed' using errcode = '42501';
    end if;
  end if;

  -- hitch checkout_product_id só do próprio seller
  if NEW.checkout_product_id is not null and v_live_owner is not null then
    select p.seller_id into v_product_seller
    from public.products p where p.id = NEW.checkout_product_id limit 1;
    if v_product_seller is not null
       and v_product_seller is distinct from v_live_owner then
      raise exception 'live_item_checkout_product_seller_mismatch'
        using errcode = '42501';
    end if;
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
      and r.status in ('accepted', 'converted');
    if coalesce(NEW.quantity, 0) < v_reserved then
      raise exception 'live_item_qty_below_reservations' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AM-P1 — stock: não restaurar em devolvida se captura Stripe ainda viva
-- ---------------------------------------------------------------------------
create or replace function public.batata_restore_product_stock_on_cancelled_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_units int;
  v_before int;
  v_after int;
  v_old text;
  v_new text;
  v_pm text;
  v_cleared int;
  v_restore boolean := false;
  v_captured boolean := false;
  v_refunded boolean := false;
begin
  v_old := lower(trim(coalesce(old.status, '')));
  v_new := lower(trim(coalesce(new.status, '')));

  if new.product_id is null then
    return new;
  end if;

  if v_new is not distinct from v_old then
    return new;
  end if;

  if v_new in (
    'cancelado', 'cancelada', 'cancelled', 'canceled', 'anulado', 'anulada'
  ) or position('cancelad' in v_new) > 0
    or position('anulad' in v_new) > 0 then
    v_restore := true;
  end if;

  if v_new = 'devolvida' then
    v_captured :=
      coalesce(new.amount_paid_cents, 0) > 0
      or coalesce(nullif(trim(coalesce(new.stripe_payment_intent_id, '')), ''), '') <> '';
    v_refunded :=
      coalesce(nullif(trim(coalesce(new.stripe_refund_id, '')), ''), '') <> '';
    -- Só restaura stock se não há captura viva (off-platform) OU já houve refund
    if not v_captured or v_refunded then
      v_restore := true;
    else
      -- captura viva sem refund: não libertar stock (anti oversell AM3)
      return new;
    end if;
  end if;

  if not v_restore then
    return new;
  end if;

  v_pm := lower(trim(coalesce(new.payment_method, '')));
  if v_pm like '%rifa%'
     or v_pm like '%prémio%'
     or v_pm like '%premio%' then
    update public.orders
       set stock_units_applied = null
     where id = new.id
       and stock_units_applied is not null;
    return new;
  end if;

  v_units := new.stock_units_applied;
  if v_units is null or v_units <= 0 then
    return new;
  end if;

  update public.orders
     set stock_units_applied = null
   where id = new.id
     and stock_units_applied is not null;
  get diagnostics v_cleared = row_count;
  if v_cleared = 0 then
    return new;
  end if;

  select quantity into v_before
  from public.products
  where id = new.product_id;

  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = new.product_id
   returning quantity into v_after;

  raise log
    'BATATA_STOCK restore order=% product=% units=% qty_before=% qty_after=% old_status=% new_status=%',
    new.id, new.product_id, v_units, v_before, v_after, v_old, v_new;

  return new;
end;
$$;

-- AM-P1 — refund-order: devolvida terminal ANTES de shipped_at
create or replace function public.batata_order_allows_seller_stripe_refund(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_st text;
  v_shipped timestamptz;
  v_open_dispute boolean;
begin
  if p_order_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_order');
  end if;

  select lower(trim(coalesce(o.status, ''))), o.shipped_at
    into v_st, v_shipped
  from public.orders o
  where o.id = p_order_id;

  if v_st is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  -- Terminal devolvida/cancelado: refund residual permitido mesmo com shipped_at
  if v_st in ('cancelado', 'cancelled', 'canceled', 'devolvida') then
    return jsonb_build_object('ok', true, 'status', v_st, 'terminal', true);
  end if;

  if v_shipped is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_shipped',
      'status', v_st
    );
  end if;

  if v_st in (
    'enviado',
    'concluido',
    'concluído',
    'entregue',
    'pedido_devolucao',
    'em_devolucao',
    'devolucao_entregue',
    'disputa_devolucao_vendedor'
  ) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_status',
      'status', v_st
    );
  end if;

  select exists (
    select 1
    from public.order_disputes d
    where d.order_id = p_order_id
      and lower(trim(coalesce(d.status, ''))) in (
        'aberta', 'open', 'pending', 'em_analise', 'em_análise'
      )
  ) into v_open_dispute;

  if coalesce(v_open_dispute, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'order_refund_blocked_open_dispute',
      'status', v_st
    );
  end if;

  return jsonb_build_object('ok', true, 'status', v_st);
end;
$$;

-- AM-P1 — storage provas disputa: path com order_id da encomenda do seller
drop policy if exists fleaber_private_select_order_counterparty on storage.objects;
create policy fleaber_private_select_order_counterparty
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fleaber_private'
    and auth.uid() is not null
    and (
      (
        name like 'order_proofs/%'
        and exists (
          select 1
          from public.orders o
          where o.seller_id = auth.uid()
            and o.buyer_id is not null
            and lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
            and (
              name like ('order_proofs/' || o.buyer_id::text || '/' || o.id::text || '/%')
              or (
                name like ('order_proofs/' || o.buyer_id::text || '/%')
                and name not like ('order_proofs/' || o.buyer_id::text || '/%/%')
              )
            )
        )
      )
      or (
        name like 'order_disputes/%'
        and exists (
          select 1
          from public.orders o
          where (o.seller_id = auth.uid() or o.buyer_id = auth.uid())
            and (
              name like ('order_disputes/' || o.buyer_id::text || '/' || o.id::text || '%')
              or name like ('order_disputes/' || o.buyer_id::text || '/' || o.id::text || '/%')
            )
            and (
              lower(trim(coalesce(o.status, ''))) not in ('cancelado', 'cancelled')
              or exists (
                select 1 from public.order_disputes d
                where d.order_id = o.id
                  and lower(coalesce(d.status, '')) not in ('recusada', 'resolvida')
              )
            )
        )
      )
    )
  );

-- AM-P2 — proof_photos URLs em order_disputes
create or replace function public.batata_order_disputes_guard_proof_urls()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_url text;
  v_arr jsonb;
begin
  if NEW.proof_photos is null then
    return NEW;
  end if;
  begin
    v_arr := to_jsonb(NEW.proof_photos);
  exception when others then
    raise exception 'dispute_proof_url_denied' using errcode = '23514';
  end;
  if jsonb_typeof(v_arr) <> 'array' then
    return NEW;
  end if;
  for v_url in
    select lower(trim(coalesce(elem, '')))
    from jsonb_array_elements_text(v_arr) as t(elem)
  loop
    if v_url = '' then
      continue;
    end if;
    if v_url like 'javascript:%' or v_url like 'data:%' or v_url ~ '^//'
       or v_url ~ '[\n\r]' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
    if v_url not like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%' then
      raise exception 'dispute_proof_url_denied' using errcode = '23514';
    end if;
  end loop;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_proof on public.order_disputes;
create trigger trg_batata_order_disputes_guard_proof
  before insert or update of proof_photos on public.order_disputes
  for each row execute function public.batata_order_disputes_guard_proof_urls();

-- AM-P3 — INSERT disputa status=resolvida forçado a aberta
create or replace function public.batata_order_disputes_guard_insert_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if auth.role() = 'authenticated' then
    NEW.status := 'aberta';
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_insert_status on public.order_disputes;
create trigger trg_batata_order_disputes_insert_status
  before insert on public.order_disputes
  for each row execute function public.batata_order_disputes_guard_insert_status();

-- ---------------------------------------------------------------------------
-- AL-P2 — cancel pós-pago: 403 em vez de 200 silencioso
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_paid_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old text;
  v_new text;
  v_is_buyer boolean;
  v_is_seller boolean;
  v_post_pay boolean;
  v_has_dispute boolean := false;
  v_released boolean := false;
  v_captured boolean := false;
  v_platform boolean := false;
  v_pm text;
  v_ship text;
  v_proof text;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := (NEW.seller_id is not null and NEW.seller_id = v_uid);

  if TG_OP = 'INSERT' then
    if v_is_buyer and v_new in (
      'pago', 'concluido', 'devolvida', 'enviado', 'entregue', 'premio_rifa',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  v_pm := coalesce(OLD.payment_method, NEW.payment_method);
  v_ship := coalesce(OLD.shipping_method, NEW.shipping_method);
  v_platform := public.batata_is_platform_payment(v_pm);
  v_captured :=
    coalesce(OLD.amount_paid_cents, 0) > 0
    or coalesce(OLD.stripe_payment_intent_id, '') <> '';
  v_proof := coalesce(nullif(trim(coalesce(NEW.proof_url, OLD.proof_url)), ''), '');

  if v_new in (
    'reserva_pendente', 'pendente', 'reservado',
    'aguarda_confirmacao', 'aguarda_pagamento'
  ) then
    if coalesce(OLD.shipped_at, NEW.shipped_at) is not null
       or v_old in ('enviado', 'entregue', 'concluido', 'concluído')
       or (v_captured and v_old = 'pago') then
      raise exception 'order_status_regression_denied' using errcode = '42501';
    end if;
  end if;

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    raise exception 'order_cancel_denied_post_pay' using errcode = '42501';
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      raise exception 'order_status_requires_capture' using errcode = '42501';
    end if;
  end if;

  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      raise exception 'order_buyer_cannot_mark_pago' using errcode = '42501';
    end if;
    if v_new = 'enviado' then
      raise exception 'order_buyer_cannot_mark_enviado' using errcode = '42501';
    end if;
    if v_new = 'devolvida' then
      raise exception 'order_buyer_cannot_mark_devolvida' using errcode = '42501';
    end if;

    if v_new = 'entregue' and v_old is distinct from 'enviado' then
      raise exception 'order_entregue_requires_enviado' using errcode = '42501';
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      raise exception 'order_return_after_release_denied' using errcode = '42501';
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        raise exception 'order_pedido_devolucao_denied' using errcode = '42501';
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        raise exception 'order_pedido_devolucao_requires_dispute' using errcode = '42501';
      end if;
    end if;

    if v_new = 'concluido' then
      if v_old = 'pago' then
        if not public.batata_shipping_method_is_hand(v_ship) then
          raise exception 'order_concluido_requires_shipped'
            using errcode = '42501';
        end if;
      elsif v_old not in (
        'enviado', 'entregue', 'pedido_devolucao',
        'em_devolucao', 'disputa_devolucao_vendedor', 'devolucao_entregue'
      ) then
        raise exception 'order_concluido_denied' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_is_seller then
    if v_old in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) and v_new in ('enviado', 'entregue', 'pago', 'concluido') then
      raise exception 'order_return_in_progress' using errcode = '42501';
    end if;

    if v_new = 'pago' and v_old is distinct from 'pago' then
      if public.batata_is_off_platform_payment(v_pm) then
        if v_proof = '' then
          raise exception 'order_mbway_pago_requires_proof' using errcode = '42501';
        end if;
      elsif not v_captured then
        raise exception 'order_seller_pago_requires_capture' using errcode = '42501';
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        raise exception 'order_ship_requires_pago' using errcode = '42501';
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        raise exception 'order_devolvida_denied' using errcode = '42501';
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and exists (
            select 1 from public.orders o
            where o.id = d.order_id and o.seller_id = v_uid
          )
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        raise exception 'order_devolvida_requires_dispute' using errcode = '42501';
      end if;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    raise exception 'order_status_not_party' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

-- ---------------------------------------------------------------------------
-- AK / AJ — Hub: GRANT stock a anon + filtrar reserved_full + só broadcasting
-- ---------------------------------------------------------------------------
grant execute on function public.batata_live_item_stock(uuid) to anon, authenticated;
grant execute on function public.batata_live_is_broadcasting(uuid) to anon, authenticated;

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
  and coalesce(li.quantity, 0) > 0
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and public.batata_live_is_broadcasting(li.live_id)
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

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
  and coalesce(li.quantity, 0) > 0
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and public.batata_live_is_broadcasting(li.live_id)
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

grant select on public.hub_live_items_discovery_public to anon, authenticated;

-- AK — REST hitch de live ended: só seller/staff vê (buyer precisa broadcasting)
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
              'paused', 'inactive', 'sold', 'reserved_full'
            )
            and coalesce(
              (public.batata_live_item_stock(live_items.id)->>'available_qty')::int,
              0
            ) > 0
            and public.batata_live_is_broadcasting(l.id)
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- AI — chat: mentiras display/notes/inbox + proof signed + Cf prefix
-- ---------------------------------------------------------------------------
create or replace function public.batata_chat_payment_lie_text(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~*
    '(Seguro Fleaber|Seguro|Compra paga|MB\s*WAY|MBWAY|PIX|Transfer[eê]ncia|Pagamento|Reembolso|PayPal|Bizum|IBAN|Recebi|aprovado|confirmado).*(\d+[,.]?\d*\s*(€|EUR|euros?)|€\s*\d+|\d+\s*€|\d+\s*EUR)'
    or coalesce(p_text, '') ~*
    '(MB\s*WAY|MBWAY|PIX|PayPal|Bizum).*(confirmado|banco|recebido)';
$$;

create or replace function public.batata_chat_is_forged_inbox_preview(p_text text)
returns boolean
language sql
immutable
as $$
  select public.batata_chat_payment_lie_text(p_text);
$$;

-- Strip Cf (ZWSP etc) before prefix check — patch via assert entry
create or replace function public.batata_chat_strip_format_controls(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    coalesce(p_text, ''),
    '[' || chr(8203) || chr(8204) || chr(8205) || chr(8206) || chr(8207)
      || chr(8234) || chr(8235) || chr(8236) || chr(8237) || chr(8238)
      || chr(8294) || chr(8295) || chr(8296) || chr(8297) || chr(8288)
      || chr(173) || ']+',
    '',
    'g'
  );
$$;

comment on function public.batata_restore_product_stock_on_cancelled_order() is
  'FASE2+3C+AHAM: repõe stock em cancelado; em devolvida só se off-platform ou já refund Stripe.';

-- Quando refund Stripe chega depois de devolvida, então sim libertar stock
create or replace function public.batata_restore_stock_on_stripe_refund()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_units int;
  v_cleared int;
begin
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;
  if coalesce(nullif(trim(coalesce(NEW.stripe_refund_id, '')), ''), '') = '' then
    return NEW;
  end if;
  if coalesce(nullif(trim(coalesce(OLD.stripe_refund_id, '')), ''), '') <> '' then
    return NEW;
  end if;
  if NEW.product_id is null then
    return NEW;
  end if;
  if lower(trim(coalesce(NEW.status, ''))) not in (
    'devolvida', 'cancelado', 'cancelled', 'canceled'
  ) then
    return NEW;
  end if;
  v_units := NEW.stock_units_applied;
  if v_units is null or v_units <= 0 then
    return NEW;
  end if;
  update public.orders
     set stock_units_applied = null
   where id = NEW.id
     and stock_units_applied is not null;
  get diagnostics v_cleared = row_count;
  if v_cleared = 0 then
    return NEW;
  end if;
  update public.products
     set quantity = coalesce(quantity, 0) + v_units,
         is_sold = false,
         list_on_marketplace = true
   where id = NEW.product_id;
  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_restore_stock_on_stripe_refund on public.orders;
create trigger trg_batata_restore_stock_on_stripe_refund
  after update of stripe_refund_id on public.orders
  for each row execute function public.batata_restore_stock_on_stripe_refund();

notify pgrst, 'reload schema';
