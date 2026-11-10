-- =============================================================================
-- BATATA — fecho N/O claros 2026-08-31 (P = saturado; O3/O4 = perguntar produto)
-- N-P0: seller_id spoof em live_reservation_requests
-- N-P2: stop_egress na Edge (código TS)
-- O-P1: seller não aborta devolução com PATCH enviado
-- O-P2: proof_url + return_label_url wrap
-- O-P3: escalate → current_turn=administracao
-- production_touched: false · fase4: false
-- =============================================================================

-- ---------------------------------------------------------------------------
-- N-P0 — autoridade do saco: seller_id = dono da live (não o JWT que se auto-nomeia)
-- ---------------------------------------------------------------------------
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
  v_live_owner uuid;
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
  NEW.live_id := coalesce(NEW.live_id, v_live_id);

  select coalesce(l.seller_id, l.vendedor_id)
    into v_live_owner
  from public.lives l
  where l.id = v_live_id
  limit 1;

  -- N-P0: seller_id sempre o dono do directo (spoof JWT ignorado)
  if v_live_owner is not null then
    NEW.seller_id := v_live_owner;
  end if;

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

  -- Só dono da live (ou staff dessa loja) é «vendedor» — nunca só NEW.seller_id=JWT
  v_is_seller :=
    (v_live_owner is not null and v_live_owner = v_uid)
    or (
      v_live_owner is not null
      and public.batata_staff_has_permission(v_live_owner, 'can_manage_reservations')
    );

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
    NEW.seller_id := OLD.seller_id;
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

  NEW.seller_id := coalesce(v_live_owner, OLD.seller_id);
  return NEW;
end;
$fn$;

comment on function public.batata_live_reservation_guard_authority() is
  'N-P0: seller_id=dono live; JWT alheio não auto-aceita stock.';

-- ---------------------------------------------------------------------------
-- O-P1 — seller não aborta ciclo de devolução com PATCH enviado/pago/concluido
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

  v_released := OLD.wallet_release_processed_at is not null
    or NEW.wallet_release_processed_at is not null;

  v_post_pay := v_old in (
    'pago', 'enviado', 'entregue', 'concluido', 'premio_rifa',
    'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
    'disputa_devolucao_vendedor', 'devolvida'
  );

  if v_post_pay and v_new in ('cancelado', 'cancelled') then
    NEW.status := OLD.status;
    return NEW;
  end if;

  if v_platform and not v_captured then
    if v_new in (
      'pago', 'enviado', 'entregue', 'concluido',
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor', 'devolvida'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  -- ---- Comprador ----
  if v_is_buyer and not v_is_seller then
    if v_new = 'pago' and v_old is distinct from 'premio_rifa' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'enviado' then
      NEW.status := OLD.status;
      return NEW;
    end if;
    if v_new = 'devolvida' then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'entregue' and v_old is distinct from 'enviado' then
      raise exception 'order_entregue_requires_enviado' using errcode = '42501';
    end if;

    if v_released and v_new in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    if v_new = 'pedido_devolucao' then
      if v_old not in ('concluido', 'entregue') then
        NEW.status := OLD.status;
        return NEW;
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        NEW.status := OLD.status;
        return NEW;
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
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;
  end if;

  -- ---- Vendedor ----
  if v_is_seller then
    -- O-P1: ciclo de devolução não volta a «enviado/pago/concluido»
    if v_old in (
      'pedido_devolucao', 'em_devolucao', 'devolucao_entregue',
      'disputa_devolucao_vendedor'
    ) and v_new in ('enviado', 'entregue', 'pago', 'concluido') then
      raise exception 'order_return_in_progress' using errcode = '42501';
    end if;

    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    if v_old = 'concluido' and v_new is distinct from 'concluido' then
      raise exception 'order_concluido_immutable_for_seller' using errcode = '42501';
    end if;

    if v_new in ('enviado', 'entregue') then
      if v_old is distinct from 'pago'
         and v_old is distinct from 'enviado'
         and not v_captured then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'devolvida' then
      if v_old not in (
        'devolucao_entregue',
        'disputa_devolucao_vendedor'
      ) then
        NEW.status := OLD.status;
        return NEW;
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
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'pedido_devolucao' and v_old is distinct from 'pedido_devolucao' then
      if not v_is_buyer then
        NEW.status := OLD.status;
        return NEW;
      end if;
    end if;

    if v_new = 'concluido' and not v_is_buyer then
      NEW.status := OLD.status;
      return NEW;
    end if;
  end if;

  if not v_is_buyer and not v_is_seller then
    NEW.status := OLD.status;
    return NEW;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_paid_status() is
  'D0820+O-P1: sem abort devolução; entregue pós-enviado; concluido imutável seller.';

-- ---------------------------------------------------------------------------
-- O-P2 — proof_url: pós-pago só storage/Fleaber; sem wrap evil
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

  -- wrap / open-redirect: segundo esquema na string
  if v_url ~ 'https?://.+/https?://' then
    raise exception 'order_proof_url_denied' using errcode = '42501';
  end if;

  if v_paid then
    if not (
      v_url like 'https://%.supabase.co/storage/%'
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

drop trigger if exists trg_batata_orders_guard_proof_url on public.orders;
create trigger trg_batata_orders_guard_proof_url
  before update of proof_url on public.orders
  for each row
  execute function public.batata_orders_guard_proof_url();

-- ---------------------------------------------------------------------------
-- O-P2 — return_label_url: prefixo Fleaber SEM wrap https://fleaber.app/https://evil
-- ---------------------------------------------------------------------------
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
  if v_role is distinct from 'authenticated' or v_uid is null then
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

  if v_url ~ 'https?://.+/https?://' then
    raise exception 'dispute_return_label_url_denied' using errcode = '42501';
  end if;

  if v_url not like 'https://fleaber.app/%'
     and v_url not like 'https://www.fleaber.app/%'
     and v_url not like 'https://fleaber.pt/%'
     and v_url not like 'https://www.fleaber.pt/%' then
    raise exception 'dispute_return_label_url_denied' using errcode = '42501';
  end if;

  -- path após host não pode parecer URL absoluta
  if substring(v_url from 'https://[^/]+(/.*)$') ~* '/https?%3a%2f%2f'
     or substring(v_url from 'https://[^/]+(/.*)$') ~* '/https?://' then
    raise exception 'dispute_return_label_url_denied' using errcode = '42501';
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_label_url on public.order_disputes;
create trigger trg_batata_order_disputes_guard_label_url
  before insert or update of return_label_url on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_label_url();

-- ---------------------------------------------------------------------------
-- O-P3 — escalate: status escalada_fleaber ⇒ turn administracao
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
    NEW.status := OLD.status;
    NEW.current_turn := OLD.current_turn;
    return NEW;
  end if;

  -- O-P3: escalada para Fleaber = turn admin (não reverter para vendedor)
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

drop trigger if exists trg_batata_order_disputes_guard_authority on public.order_disputes;
create trigger trg_batata_order_disputes_guard_authority
  before update on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_authority();

notify pgrst, 'reload schema';
