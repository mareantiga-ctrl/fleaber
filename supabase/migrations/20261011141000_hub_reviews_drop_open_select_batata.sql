-- =============================================================================
-- BATATA 2026-10-11 — P05 validação: fechar SELECT aberto em public.reviews
-- Staging only neste passo. Não tocar produção.
--
-- Achado: policy reviews_select_public_marketplace USING (true) ainda activa
-- em staging → anon lê buyer_id / campos internos via /rest/v1/reviews.
-- Leitura pública Hub: hub_reviews_public + batata_hub_reviews_public_*.
-- =============================================================================

drop policy if exists "reviews_select_public_marketplace" on public.reviews;

-- Garantir SELECT parties só para autenticados (buyer / seller target / admin / order party)
drop policy if exists "reviews_select_parties" on public.reviews;
create policy "reviews_select_parties"
  on public.reviews
  for select
  to authenticated
  using (
    buyer_id = auth.uid()
    or target_id = auth.uid()
    or exists (
      select 1
      from public.orders o
      where o.id = reviews.order_id
        and (o.buyer_id = auth.uid() or o.seller_id = auth.uid())
    )
    or public.batata_is_admin()
  );

revoke select on table public.reviews from anon;
grant select on table public.reviews to authenticated;
grant all on table public.reviews to service_role;

-- View pública permanece SELECT-only para anon/authenticated
revoke insert, update, delete, truncate, references, trigger
  on public.hub_reviews_public from anon, authenticated;
grant select on public.hub_reviews_public to anon, authenticated;

notify pgrst, 'reload schema';
