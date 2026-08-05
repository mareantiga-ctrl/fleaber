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
  v_done boolean;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
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
  v_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_amount,
    'reembolso',
    'Reembolso Encomenda #' || left(v_order.id::text, 8)
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
-- partial refund dispute: só buyer/seller/admin + percent da disputa se existir
-- =============================================================================

create or replace function public.batata_process_partial_refund_dispute(
  p_order_id uuid,
  p_refund_percent numeric
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_total numeric;
  v_percent numeric;
  v_refund numeric;
  v_commission numeric;
  v_seller_amount numeric;
  v_buyer_done boolean := false;
  v_seller_done boolean := false;
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_dispute_percent numeric;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found or v_order.buyer_id is null or v_order.seller_id is null then
    return false;
  end if;

  -- Cuidado triplicado: não mudar quem já usa (buyer aceita no chat);
  -- só impedir estranhos.
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

  if v_order.wallet_release_processed_at is not null
     or v_order.wallet_refund_processed_at is not null then
    return false;
  end if;

  -- Preferir % proposto na disputa (não confiar só no cliente)
  select d.seller_refund_percent
  into v_dispute_percent
  from public.order_disputes d
  where d.order_id = p_order_id
    and d.seller_refund_percent is not null
    and lower(coalesce(d.status, '')) is distinct from 'recusada'
  order by d.created_at desc
  limit 1;

  v_percent := least(
    greatest(
      coalesce(v_dispute_percent, p_refund_percent, 0),
      0
    ),
    100
  );

  v_total := public.batata_order_amount(v_order);
  if v_total <= 0 or v_percent <= 0 then
    return false;
  end if;

  v_refund := round(v_total * (v_percent / 100), 2);
  v_commission := public.batata_order_commission_amount(v_total);
  v_seller_amount := greatest(round(v_total - v_refund - v_commission, 2), 0);

  v_buyer_done := public.batata_credit_wallet_once(
    v_order.buyer_id,
    v_order.id,
    v_refund,
    'reembolso',
    'Reembolso parcial de ' || round(v_percent, 2)::text || '%'
  );

  v_seller_done := public.batata_credit_wallet_once(
    v_order.seller_id,
    v_order.id,
    v_seller_amount,
    'venda',
    'Valor restante após reembolso parcial'
  );

  perform public.batata_record_fleaber_commission_once(
    v_order.id,
    v_commission,
    'protection_fee',
    'Taxa de Proteção Fleaber'
  );

  update public.orders
  set wallet_release_processed_at = now(),
      wallet_refund_processed_at = now()
  where id = v_order.id;

  return v_buyer_done or v_seller_done;
end;
$$;

revoke all on function public.batata_process_partial_refund_dispute(uuid, numeric)
  from public, anon;
grant execute on function public.batata_process_partial_refund_dispute(uuid, numeric)
  to authenticated, service_role;

-- release seller: grants explícitos (lógica de buyer já existia)
revoke all on function public.batata_release_seller_wallet_for_order(uuid)
  from public, anon;
grant execute on function public.batata_release_seller_wallet_for_order(uuid)
  to authenticated, service_role;

notify pgrst, 'reload schema';
