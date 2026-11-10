-- SEC-040 — seller_bundle_discounts
-- Os escalões de desconto SÃO dados de produto: o comprador precisa de os ler
-- (fetchSellerBundleDiscounts) para montar conjuntos — igual a ver o preço.
-- Fechar SELECT ao próprio seller partia checkout de conjuntos.
--
-- Endurecimento BATATA sem partir UX:
-- 1) Manter SELECT authenticated (necessário)
-- 2) Garantir que INSERT/UPDATE/DELETE só o dono (já em upsert_own)
-- 3) Revogar anon se existir grant
--
-- Residual ACEITE: qualquer autenticado vê % de desconto de qualquer loja
-- (intel comercial, não PII/dinheiro directo).

do $$
begin
  revoke all on table public.seller_bundle_discounts from anon;
exception
  when undefined_object then null;
  when others then null;
end $$;

-- Reforçar policy de escrita só own (idempotente)
drop policy if exists "seller_bundle_discounts_upsert_own" on public.seller_bundle_discounts;
create policy "seller_bundle_discounts_upsert_own"
  on public.seller_bundle_discounts for all to authenticated
  using (seller_id = auth.uid())
  with check (seller_id = auth.uid());

-- SELECT continua aberto a authenticated (produto)
drop policy if exists "seller_bundle_discounts_select" on public.seller_bundle_discounts;
create policy "seller_bundle_discounts_select"
  on public.seller_bundle_discounts for select to authenticated
  using (true);

comment on table public.seller_bundle_discounts is
  'SEC-040 ACEITE: SELECT auth aberto de propósito (descontos públicos na app); escrita só own.';

notify pgrst, 'reload schema';
