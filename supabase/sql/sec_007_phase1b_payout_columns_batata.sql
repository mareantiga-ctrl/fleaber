-- SEC-007 fase 1b — BATATA (PII financeira)
-- Revoga SELECT de iban/mb_way a authenticated (dump JWT deixa de ver dados bancários).
-- Leitura autorizada só via RPCs:
--   batata_get_my_payout_details() — próprio
--   batata_seller_direct_payment_details(seller) — comprador com encomenda/conjunto aberta
-- UPDATE próprio de iban/mb_way mantém-se (profiles_update_own).
-- Conta/app devem usar as RPCs (Dart actualizado).

-- 1) RPCs
create or replace function public.batata_get_my_payout_details()
returns table (mb_way text, iban text, external_payments_enabled boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Não autenticado.';
  end if;
  return query
  select
    p.mb_way::text,
    p.iban::text,
    coalesce(p.external_payments_enabled, false)
  from public.profiles p
  where p.id = auth.uid();
end;
$$;

create or replace function public.batata_seller_direct_payment_details(p_seller_id uuid)
returns table (mb_way text, iban text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid := auth.uid();
  v_ok boolean := false;
begin
  if v_buyer is null then
    raise exception 'Não autenticado.';
  end if;
  if p_seller_id is null then
    return;
  end if;
  -- Próprio perfil
  if p_seller_id = v_buyer then
    v_ok := true;
  else
    -- Comprador com encomenda com este vendedor (aberta ou recente)
    select exists (
      select 1
      from public.orders o
      where o.seller_id = p_seller_id
        and o.buyer_id = v_buyer
        and lower(coalesce(o.status, '')) not in ('cancelado', 'cancelled', 'refunded')
    ) into v_ok;
    if not v_ok then
      select exists (
        select 1
        from public.product_bundles b
        where b.seller_id = p_seller_id
          and b.buyer_id = v_buyer
      ) into v_ok;
    end if;
  end if;

  if not v_ok then
    return;
  end if;

  return query
  select p.mb_way::text, p.iban::text
  from public.profiles p
  where p.id = p_seller_id
    and coalesce(p.external_payments_enabled, false) = true;
end;
$$;

revoke all on function public.batata_get_my_payout_details() from public;
revoke all on function public.batata_seller_direct_payment_details(uuid) from public;
grant execute on function public.batata_get_my_payout_details() to authenticated;
grant execute on function public.batata_seller_direct_payment_details(uuid) to authenticated;

-- 2) Revogar SELECT das colunas sensíveis (authenticated)
do $$
begin
  revoke select (iban, mb_way) on table public.profiles from authenticated;
exception
  when undefined_object then null;
  when others then
    raise notice 'SEC-007 1b revoke column select: %', sqlerrm;
end $$;

-- service_role mantém acesso total (edges / admin)
do $$
begin
  grant select (iban, mb_way) on table public.profiles to service_role;
exception
  when others then
    raise notice 'SEC-007 1b grant service_role: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

comment on function public.batata_get_my_payout_details() is
  'SEC-007 1b: ler MB WAY/IBAN do próprio utilizador';
comment on function public.batata_seller_direct_payment_details(uuid) is
  'SEC-007 1b: MB WAY/IBAN do vendedor só com relação de compra';
