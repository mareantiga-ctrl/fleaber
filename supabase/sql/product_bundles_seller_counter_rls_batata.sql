-- Permite ao vendedor criar bundle pendente (ex.: contraproposta após proposta do comprador).
-- Complementa product_bundles_insert_buyer (comprador cria proposta inicial).

drop policy if exists "product_bundles_insert_seller" on public.product_bundles;
create policy "product_bundles_insert_seller"
  on public.product_bundles for insert to authenticated
  with check (seller_id = auth.uid());
