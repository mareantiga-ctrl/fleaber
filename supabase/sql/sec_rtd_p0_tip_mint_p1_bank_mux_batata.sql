-- =============================================================================
-- Red Team 20260829T1435 + Indep D — P0 tip mint + P1 banking reservado + P1 Mux
-- STAGING only. PRODUÇÃO NÃO. FASE 4 NÃO.
-- BATATA: mínimo; preservar wallet tip legítima, bundle seller→reservado, registo vendedor.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- P0) batata_wallet_apply_tip_once — sem EXECUTE JWT; montantes da tip
-- ---------------------------------------------------------------------------
create or replace function public.batata_wallet_apply_tip_once(
  p_wallet_id uuid,
  p_tip_id uuid,
  p_amount numeric,
  p_type text,
  p_description text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row_count integer := 0;
  v_tip public.live_tips%rowtype;
  v_amt numeric(12, 2);
  v_role text := coalesce(auth.role(), '');
  v_type text := lower(trim(coalesce(p_type, '')));
begin
  if p_wallet_id is null or p_tip_id is null then
    return false;
  end if;

  v_amt := round(coalesce(p_amount, 0), 2);
  if v_amt = 0 then
    return false;
  end if;

  select * into v_tip
  from public.live_tips t
  where t.id = p_tip_id
  for update;
  if not found then
    return false;
  end if;

  -- Pending Stripe só via service_role (settle Edge). JWT não minta em tip pending.
  if lower(trim(coalesce(v_tip.status, ''))) = 'pending'
     and lower(trim(coalesce(v_tip.payment_source, ''))) = 'stripe'
     and v_role is distinct from 'service_role' then
    raise exception 'tip_pending_stripe_service_only' using errcode = '42501';
  end if;

  if v_amt > 0 then
    if p_wallet_id is distinct from v_tip.seller_id then
      raise exception 'tip_credit_wallet_mismatch' using errcode = '42501';
    end if;
    if v_amt is distinct from round(coalesce(v_tip.seller_amount, 0), 2) then
      raise exception 'tip_credit_amount_mismatch' using errcode = '23514';
    end if;
    if v_type is distinct from 'gorjeta_recebida' then
      raise exception 'tip_credit_type_invalid' using errcode = '23514';
    end if;
  else
    if p_wallet_id is distinct from v_tip.buyer_id then
      raise exception 'tip_debit_wallet_mismatch' using errcode = '42501';
    end if;
    if v_amt is distinct from -round(coalesce(v_tip.amount, 0), 2) then
      raise exception 'tip_debit_amount_mismatch' using errcode = '23514';
    end if;
    if v_type is distinct from 'gorjeta_enviada' then
      raise exception 'tip_debit_type_invalid' using errcode = '23514';
    end if;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    tip_id
  ) values (
    p_wallet_id,
    v_amt,
    v_type,
    p_description,
    p_tip_id
  )
  on conflict (wallet_id, tip_id, type) where tip_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  if v_row_count = 0 then
    return false;
  end if;

  update public.wallets
  set balance = round(balance + v_amt, 2)
  where id = p_wallet_id;

  return true;
end;
$$;

revoke all on function public.batata_wallet_apply_tip_once(uuid, uuid, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_wallet_apply_tip_once(uuid, uuid, numeric, text, text)
  to service_role;

comment on function public.batata_wallet_apply_tip_once(uuid, uuid, numeric, text, text) is
  'RT-D-P0: tip ledger; JWT sem EXECUTE; amount/wallet da tip; pending stripe só service_role.';

-- send_live_tip_from_wallet (DEFINER) continua a chamar apply — owner tem direito.
-- Garante que send_live_tip permanece executável por authenticated.
grant execute on function public.batata_send_live_tip_from_wallet(uuid, uuid, numeric, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- P1 BANK) buyer JWT não fabrica status pós-aceitação (reservado / aguarda_pagamento)
-- Preserva: seller INSERT/UPDATE → reservado (bundle accept); buyer → reserva_pendente.
-- ---------------------------------------------------------------------------
create or replace function public.batata_orders_guard_buyer_cannot_self_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_new text;
  v_old text;
  v_is_buyer boolean;
  v_is_seller boolean;
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  v_new := lower(trim(coalesce(NEW.status, '')));
  v_is_buyer := NEW.buyer_id is not null and NEW.buyer_id = v_uid;
  v_is_seller := NEW.seller_id is not null and NEW.seller_id = v_uid;

  if not v_is_buyer or v_is_seller then
    return NEW;
  end if;

  -- INSERT: comprador só cria pré-aceitação
  if TG_OP = 'INSERT' then
    if v_new in (
      'reservado',
      'aguarda_confirmacao',
      'aguarda_pagamento',
      'pago',
      'enviado',
      'entregue',
      'concluido',
      'premio_rifa'
    ) then
      NEW.status := 'reserva_pendente';
    end if;
    return NEW;
  end if;

  v_old := lower(trim(coalesce(OLD.status, '')));
  if v_new is not distinct from v_old then
    return NEW;
  end if;

  -- UPDATE: comprador não se «aceita» a si próprio
  if v_new in ('reservado', 'aguarda_pagamento')
     and v_old in ('reserva_pendente', 'pendente', '', 'aguarda_confirmacao') then
    NEW.status := OLD.status;
  end if;

  -- Prova de pagamento OK: reservado|aguarda_pagamento → aguarda_confirmacao
  if v_new = 'aguarda_confirmacao'
     and v_old in ('reserva_pendente', 'pendente', '') then
    NEW.status := OLD.status;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_orders_guard_buyer_cannot_self_accept on public.orders;
create trigger trg_batata_orders_guard_buyer_cannot_self_accept
  before insert or update of status on public.orders
  for each row
  execute function public.batata_orders_guard_buyer_cannot_self_accept();

comment on function public.batata_orders_guard_buyer_cannot_self_accept() is
  'RTB-B-BANK: buyer JWT não INSERT/PATCH aguarda_confirmacao|reservado sem aceite; prova reservado→aguarda_confirmacao OK.';

-- ---------------------------------------------------------------------------
-- P1 MUX) profiles.user_type imutável no UPDATE JWT (registo INSERT intacto)
-- ---------------------------------------------------------------------------
create or replace function public.batata_profiles_guard_user_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' then
    NEW.user_type := OLD.user_type;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_profiles_guard_user_type on public.profiles;
create trigger trg_batata_profiles_guard_user_type
  before update on public.profiles
  for each row
  execute function public.batata_profiles_guard_user_type();

comment on function public.batata_profiles_guard_user_type() is
  'RTB2-MUX-02: JWT não eleva user_type (comprador→vendedor); INSERT no registo OK.';

notify pgrst, 'reload schema';
