-- !!! QUARANTINED FASE 4 — NÃO APLICAR (superseded / GRANT leak)
-- Fonte: docs/SCHEMA_SOURCE_OF_TRUTH.md · tool/reports/FASE4_PROD_APPLY_DENYLIST.md
do $$ begin
  raise exception 'QUARANTINED: sec_025_partial_refund_nested_ensure_batata.sql — não aplicar';
end $$;

-- SEC-025 hotfix — reembolso parcial no chat (buyer JWT)
-- BATATA: NÃO enfraquecer ensure_wallet para chamadas directas da app
-- (outsider continua not_allowed). Só confiar nest de RPCs batata_* de wallet
-- que já validaram participante da encomenda.
--
-- Sintoma: Aceitar reembolso parcial → PostgrestException not_allowed 42501
-- Causa: batata_process_partial_refund_dispute (security definer) credita
-- buyer+seller via batata_credit_wallet_once → ensure_wallet(seller) com
-- auth.uid()=buyer e pg_trigger_depth()=0.

create or replace function public.batata_ensure_wallet(p_user_id uuid default auth.uid())
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_internal text := coalesce(current_setting('batata.wallet_internal', true), '');
begin
  if p_user_id is null then
    raise exception 'Missing wallet user id.';
  end if;

  -- Chamada directa da app: só a própria carteira.
  -- Nest batata_* (reembolso parcial / credit_once) marca batata.wallet_internal=1.
  -- Triggers (pg_trigger_depth > 0) mantêm-se permitidos (hotfix anterior).
  if v_role = 'authenticated' and pg_trigger_depth() = 0 and v_internal is distinct from '1' then
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

create or replace function public.batata_credit_wallet_once(
  p_wallet_id uuid,
  p_order_id uuid,
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
  v_inserted boolean := false;
  v_row_count integer := 0;
begin
  -- Marca nest trusted para ensure_wallet (buyer+seller no mesmo RPC).
  perform set_config('batata.wallet_internal', '1', true);

  if p_wallet_id is null or p_order_id is null then
    return false;
  end if;

  if coalesce(p_amount, 0) <= 0 then
    return false;
  end if;

  perform public.batata_ensure_wallet(p_wallet_id);

  insert into public.wallet_transactions (
    wallet_id,
    amount,
    type,
    description,
    order_id
  ) values (
    p_wallet_id,
    round(p_amount, 2),
    p_type,
    p_description,
    p_order_id
  )
  on conflict (wallet_id, order_id, type) where order_id is not null do nothing;

  get diagnostics v_row_count = row_count;
  v_inserted := v_row_count > 0;

  if v_inserted then
    update public.wallets
    set balance = round(balance + p_amount, 2)
    where id = p_wallet_id;
  end if;

  return v_inserted;
end;
$$;

-- Grants: credit continua só service_role / definer nest (BATATA SEC-025).
revoke all on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.batata_credit_wallet_once(uuid, uuid, numeric, text, text)
  to service_role;

-- QUARANTINED 2026-08-26 — NÃO recriar batata_process_partial_refund_dispute.
-- Autoridade: sec_pos_auditoria_cega_hardening_batata.sql
do $$ begin
  raise notice
    'QUARANTINED: batata_process_partial_refund_dispute redefine skipped (nested_ensure)';
end $$;

notify pgrst, 'reload schema';
