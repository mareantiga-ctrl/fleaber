-- !!! QUARANTINED FASE 4 — NÃO APLICAR (settle 2-args / bypass)
-- Fonte: docs/SCHEMA_SOURCE_OF_TRUTH.md · tool/reports/FASE4_PROD_APPLY_DENYLIST.md
do $$ begin
  raise exception 'QUARANTINED: sec_025_ensure_wallet_trigger_hotfix_batata.sql — não aplicar';
end $$;

-- SEC-025 hotfix — feedback/wallet release + ensure_wallet em triggers
-- BATATA: não enfraquecer o guard para chamadas directas da app;
-- só permitir ensure_wallet de outro user quando estamos DENTRO de um trigger
-- (ex.: insert reviews → libera saldo do vendedor).

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

  -- Chamada directa da app: só a própria carteira.
  -- Em trigger (pg_trigger_depth > 0) o JWT continua authenticated,
  -- mas precisamos criar/garantir a carteira do vendedor no release pós-feedback.
  if v_role = 'authenticated' and pg_trigger_depth() = 0 then
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

-- Gorjeta Stripe settle: FASE3B QUARANTINE — NÃO recriar assinatura (uuid, text).
-- Usar batata_settle_live_tip_from_stripe(uuid, text, integer) em sec_fase3b_hardening_batata.sql.

do $$
begin
  -- Remover overload perigoso de 2 args se alguém o recriar.
  drop function if exists public.batata_settle_live_tip_from_stripe(uuid, text);
exception when others then
  raise notice 'drop settle 2-arg: %', sqlerrm;
end $$;

