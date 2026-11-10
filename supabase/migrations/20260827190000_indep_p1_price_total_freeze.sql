-- Espelho: P1-B price_total JWT freeze (ver sec_indep_p1_price_total_refund_bag_batata.sql)
create or replace function public.batata_orders_guard_money_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_old_status text;
  v_frozen boolean := false;
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
    return NEW;
  end if;

  if NEW.buyer_id is distinct from OLD.buyer_id then
    NEW.buyer_id := OLD.buyer_id;
  end if;
  if NEW.seller_id is distinct from OLD.seller_id then
    NEW.seller_id := OLD.seller_id;
  end if;
  if NEW.product_id is distinct from OLD.product_id then
    NEW.product_id := OLD.product_id;
  end if;
  if NEW.stripe_checkout_session_id is distinct from OLD.stripe_checkout_session_id then
    NEW.stripe_checkout_session_id := OLD.stripe_checkout_session_id;
  end if;
  if NEW.stripe_payment_intent_id is distinct from OLD.stripe_payment_intent_id then
    NEW.stripe_payment_intent_id := OLD.stripe_payment_intent_id;
  end if;
  if NEW.stripe_refund_id is distinct from OLD.stripe_refund_id then
    NEW.stripe_refund_id := OLD.stripe_refund_id;
  end if;
  if NEW.amount_paid_cents is distinct from OLD.amount_paid_cents then
    NEW.amount_paid_cents := OLD.amount_paid_cents;
  end if;

  if NEW.price_total is distinct from OLD.price_total then
    NEW.price_total := OLD.price_total;
  end if;

  v_old_status := lower(trim(coalesce(OLD.status, '')));
  v_frozen :=
    v_old_status in (
      'pago', 'enviado', 'entregue', 'concluido', 'devolvida',
      'em_devolucao', 'devolucao_entregue', 'disputa_devolucao_vendedor'
    )
    or coalesce(OLD.stripe_payment_intent_id, '') <> ''
    or coalesce(OLD.stripe_checkout_session_id, '') <> ''
    or coalesce(OLD.amount_paid_cents, 0) > 0;

  if v_frozen then
    if NEW.quantity is distinct from OLD.quantity then
      NEW.quantity := OLD.quantity;
    end if;
    if NEW.payment_method is distinct from OLD.payment_method then
      NEW.payment_method := OLD.payment_method;
    end if;
  end if;

  return NEW;
end;
$fn$;

comment on function public.batata_orders_guard_money_cols() is
  'AUD+INDEP 2026-08-27: money cols + price_total imutável JWT (P1-B).';
