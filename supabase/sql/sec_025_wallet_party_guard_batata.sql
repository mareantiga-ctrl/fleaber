-- !!! QUARANTINED FASE 4 — NÃO APLICAR (reabre GRANT / redefine pré-gate)
-- Fonte: docs/SCHEMA_SOURCE_OF_TRUTH.md · tool/reports/FASE4_PROD_APPLY_DENYLIST.md
do $$ begin
  raise exception 'QUARANTINED: sec_025_wallet_party_guard_batata.sql — não aplicar';
end $$;

-- SEC-025 (cuidado triplicado) — wallet / disputa parcial
-- BATATA: o comprador CONTINUA a poder aceitar reembolso parcial (chat).
-- Só bloqueamos quem NÃO é buyer nem seller da encomenda.
-- Também: credit/commission internos só service_role; ensure_wallet só a própria conta.
--
-- SEC-026: sem SQL (ops) — ver docs/SECURITY_SQL_APPLY_LIST.md

-- =============================================================================
-- Helpers de grant (assinaturas exactas)
-- =============================================================================

revoke all on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  to service_role;

revoke all on function public.batata_record_fleaber_commission_once(uuid, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_record_fleaber_commission_once(uuid, numeric, text, text)
  to service_role;

-- =============================================================================
-- ensure_wallet: só a própria carteira (app já só chama currentUserUid)
-- =============================================================================

create or replace function public.batata_ensure_wallet(p_user_id uuid default auth.uid())
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if p_user_id is null then
    raise exception 'Missing wallet user id.';
  end if;

  if v_role = 'authenticated' then
    if v_uid is null or v_uid is distinct from p_user_id then
      raise exception 'not_allowed' using errcode = '42501';
    end if;
  end if;

  insert into public.wallets (id, balance)
  values (p_user_id, 0.00)
  on conflict (id) do nothing;

  return p_user_id;
end;
$$;

revoke all on function public.batata_ensure_wallet(uuid) from public, anon;
grant execute on function public.batata_ensure_wallet(uuid) to authenticated, service_role;

-- =============================================================================
-- refund buyer: só participante da encomenda (ou admin) / service
-- Trigger status→devolvida continua (seller JWT = ok)
-- =============================================================================

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

  -- Portes comprador + etiqueta gerada → abater 3,50 € (UI ReturnLabelRules.shippingFeeEur).
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

-- =============================================================================
-- QUARANTINED 2026-08-26 — NÃO recriar batata_process_partial_refund_dispute
-- Autoridade: supabase/sql/sec_pos_auditoria_cega_hardening_batata.sql
-- (buyer-only · pós-pago · % só da disputa · sem mint pré-pago)
-- Reaplicar ESTE bloco antigo reabria mint de wallet sem pagamento.
-- =============================================================================
do $$ begin
  raise notice
    'QUARANTINED: batata_process_partial_refund_dispute redefine skipped (use sec_pos_auditoria_cega_hardening_batata.sql)';
end $$;

-- release seller: grants explícitos (lógica de buyer já existia)
revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
