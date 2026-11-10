-- BATATA: reembolso em devolvida abate etiqueta 3,50 € quando portes a cargo do comprador.
-- Alinha batata_refund_buyer_wallet_for_order com a UI do chat
-- («Custo da etiqueta: 3,50 €. Este valor será abatido ao reembolso…»).

create or replace function public.batata_refund_buyer_wallet_for_order(
  p_order_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
  v_label_fee numeric := 0;
  v_done boolean;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute record;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.buyer_id is null then
    return false;
  end if;

  if v_role = 'authenticated' then
    if v_uid is null then
      return false;
    end if;
    if v_uid is distinct from v_order.buyer_id
       and v_uid is distinct from v_order.seller_id
       and not public.batata_is_admin() then
      return false;
    end if;
  end if;

  if lower(coalesce(v_order.status, '')) <> 'devolvida' then
    return false;
  end if;

  if v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  v_amount := public.batata_order_amount(v_order);

  -- Portes comprador + etiqueta gerada → abater 3,50 € (mesmo valor ReturnLabelRules.shippingFeeEur).
  select od.seller_pays_return_shipping,
         od.return_label_created_at,
         od.buyer_decision
    into v_dispute
  from public.order_disputes od
  where od.order_id = v_order.id
  order by od.created_at desc
  limit 1;

  if found
     and coalesce(v_dispute.seller_pays_return_shipping, false) = false
     and v_dispute.return_label_created_at is not null
     and coalesce(v_dispute.buyer_decision, '') = 'accepted_return'
  then
    v_label_fee := 3.50;
  end if;

  if v_label_fee > 0 and v_amount > v_label_fee then
    v_amount := v_amount - v_label_fee;
  elsif v_label_fee > 0 and v_amount <= v_label_fee then
    -- Não criar crédito negativo; mínimo 0 (caso extremo).
    v_amount := 0;
  end if;

  if v_amount <= 0 then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now())
    where id = v_order.id;
    return true;
  end if;

  v_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_amount,
    'reembolso',
    case
      when v_label_fee > 0 then
        'Reembolso Encomenda #' || left(v_order.id::text, 8)
          || ' (abatida etiqueta ' || to_char(v_label_fee, 'FM999990.00') || ' €)'
      else
        'Reembolso Encomenda #' || left(v_order.id::text, 8)
    end
  );

  if v_done then
    update public.orders
    set wallet_refund_processed_at = now(),
        returned_at = coalesce(returned_at, now())
    where id = v_order.id;
  end if;

  return v_done;
end;
$$;

revoke all on function public.batata_refund_buyer_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_refund_buyer_wallet_for_order(uuid)
  to authenticated, service_role;
