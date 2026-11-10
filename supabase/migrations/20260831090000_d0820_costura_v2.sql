-- =============================================================================
-- BATATA — D Costura v2 0820 (P1/P2 logística)
-- P1: buyer pago→entregue → concluido + release
-- P1: seller concluido→enviado (reabre, mata disputa)
-- P1: buyer pago→em_devolucao / devolucao_entregue sem disputa
-- P1: JWT grava wallet_release_processed_at / auto_feedback_processed_at
-- P2: bundle_id pós-pago; return_label_url; returned_at
-- production_touched: false · fase4: false
-- =============================================================================

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

    -- D2-0820-P1: entregue só depois de enviado (nunca desde pago)
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

    -- D2-0820-P1: em_devolucao / devolucao_entregue exigem disputa + estado certo
    if v_new = 'em_devolucao' then
      if v_old not in ('concluido', 'entregue', 'pedido_devolucao') then
        raise exception 'order_em_devolucao_requires_dispute' using errcode = '42501';
      end if;
      select exists(
        select 1 from public.order_disputes d
        where d.order_id = NEW.id
          and d.buyer_id = v_uid
          and lower(coalesce(d.status, '')) is distinct from 'recusada'
      ) into v_has_dispute;
      if not v_has_dispute then
        raise exception 'order_em_devolucao_requires_dispute' using errcode = '42501';
      end if;
    end if;

    if v_new = 'devolucao_entregue' then
      if v_old is distinct from 'em_devolucao' then
        raise exception 'order_devolucao_entregue_requires_em_devolucao'
          using errcode = '42501';
      end if;
    end if;

    if v_post_pay and v_new in (
      'reserva_pendente', 'reservado', 'pendente', 'aguarda_confirmacao'
    ) then
      NEW.status := OLD.status;
      return NEW;
    end if;

    -- D1-EARLY-CONFIRM: concluido a partir de pago só em mão.
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
    if v_new = 'pago' and v_old is distinct from 'pago' then
      if not public.batata_is_off_platform_payment(v_pm) then
        if not v_captured then
          NEW.status := OLD.status;
          return NEW;
        end if;
      end if;
    end if;

    -- D2-0820-P1: não reabrir concluido → enviado (mata disputa + já houve release)
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
  'D2-0820: entregue só pós-enviado; sem reopen concluido; devolução com disputa.';

-- ---------------------------------------------------------------------------
-- P1: flags de payout / auto-feedback imutáveis pelo JWT
-- P2: bundle_id / returned_at selados pós-captura
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
begin
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

  -- D2-0820-P1: JWT não finge release / auto-feedback
  if NEW.wallet_release_processed_at is distinct from OLD.wallet_release_processed_at then
    raise exception 'order_wallet_release_flag_immutable' using errcode = '42501';
  end if;
  if NEW.auto_feedback_processed_at is distinct from OLD.auto_feedback_processed_at then
    raise exception 'order_auto_feedback_flag_immutable' using errcode = '42501';
  end if;

  -- D2-0820-P2: returned_at só serviço / triggers
  if NEW.returned_at is distinct from OLD.returned_at then
    NEW.returned_at := OLD.returned_at;
  end if;

  -- D2-0820-P2: bundle_id imutável depois de pago/captura
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

drop trigger if exists trg_batata_orders_guard_money_cols on public.orders;
create trigger trg_batata_orders_guard_money_cols
  before insert or update on public.orders
  for each row
  execute function public.batata_orders_guard_money_cols();

comment on function public.batata_orders_guard_money_cols() is
  'D2-0820: money + release/autofeedback flags + bundle_id pós-pago imutáveis JWT.';

-- ---------------------------------------------------------------------------
-- P2: return_label_url — só domínio Fleaber (app gera https://fleaber.app/…)
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
     and NEW.return_label_url is distinct from OLD.return_label_url then
    v_url := lower(trim(coalesce(NEW.return_label_url, '')));
    if v_url = '' then
      return NEW;
    end if;
    if v_url not like 'https://fleaber.app/%'
       and v_url not like 'https://www.fleaber.app/%'
       and v_url not like 'https://fleaber.pt/%'
       and v_url not like 'https://www.fleaber.pt/%' then
      raise exception 'dispute_return_label_url_denied' using errcode = '42501';
    end if;
  end if;

  if TG_OP = 'INSERT' and NEW.return_label_url is not null then
    v_url := lower(trim(coalesce(NEW.return_label_url, '')));
    if v_url <> ''
       and v_url not like 'https://fleaber.app/%'
       and v_url not like 'https://www.fleaber.app/%'
       and v_url not like 'https://fleaber.pt/%'
       and v_url not like 'https://www.fleaber.pt/%' then
      raise exception 'dispute_return_label_url_denied' using errcode = '42501';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_order_disputes_guard_label_url on public.order_disputes;
create trigger trg_batata_order_disputes_guard_label_url
  before insert or update of return_label_url on public.order_disputes
  for each row
  execute function public.batata_order_disputes_guard_label_url();

comment on function public.batata_order_disputes_guard_label_url() is
  'D2-0820-P2: return_label_url só fleaber.app / fleaber.pt.';

-- completed_at: limpar ao sair de concluido (seller reopen já bloqueado; reforço)
create or replace function public.batata_set_order_completed_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $batata_completed$
begin
  if new.status = 'concluido'
     and (old.status is distinct from new.status) then
    new.completed_at := now();
  end if;

  if old.status = 'concluido' and new.status is distinct from 'concluido' then
    new.completed_at := null;
    new.auto_feedback_processed_at := null;
  end if;

  if tg_op = 'UPDATE'
     and auth.uid() is not null
     and coalesce(auth.role(), '') = 'authenticated'
     and new.completed_at is distinct from old.completed_at
     and not (
       new.status = 'concluido'
       and old.status is distinct from 'concluido'
     ) then
    new.completed_at := old.completed_at;
  end if;

  return new;
end;
$batata_completed$;

drop trigger if exists batata_set_order_completed_at_trg on public.orders;
create trigger batata_set_order_completed_at_trg
before update on public.orders
for each row
execute function public.batata_set_order_completed_at();

notify pgrst, 'reload schema';
