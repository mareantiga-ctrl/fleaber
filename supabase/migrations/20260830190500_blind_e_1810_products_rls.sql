-- E6-P2: remover policy aberta «Qualquer um vê produtos ativos» (using true)
drop policy if exists "Qualquer um vê produtos ativos" on public.products;

drop policy if exists "products_select_marketplace_or_own" on public.products;
create policy "products_select_marketplace_or_own"
  on public.products
  for select
  to authenticated
  using (
    (list_on_marketplace = true and coalesce(is_sold, false) = false)
    or seller_id = auth.uid()
    or exists (
      select 1
      from public.orders o
      where o.product_id = products.id
        and o.buyer_id = auth.uid()
    )
  );

drop policy if exists "products_select_anon_marketplace" on public.products;
create policy "products_select_anon_marketplace"
  on public.products
  for select
  to anon
  using (
    list_on_marketplace = true
    and coalesce(is_sold, false) = false
  );

comment on policy "products_select_marketplace_or_own" on public.products is
  'E6-P2: listed+not sold OU own; shadow live continua à parte.';

notify pgrst, 'reload schema';
