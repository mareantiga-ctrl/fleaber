-- Rascunhos de anúncios (app + FleaHub) — coluna única em products.
-- BATATA: não expor rascunhos em marketplace/live públicos.

alter table public.products
  add column if not exists is_draft boolean not null default false;

comment on column public.products.is_draft is
  'true = rascunho (não público; sem lives/marketplace). Publicar → false.';

create index if not exists products_seller_drafts_idx
  on public.products (seller_id, created_at desc)
  where is_draft = true;

-- Marketplace público: excluir rascunhos (defesa em profundidade).
create or replace view public.hub_products_public
with (security_barrier = true)
as
select
  pr.id,
  pr.seller_id,
  hp.handle as seller_handle,
  pr.title,
  pr.price,
  pr.image_urls,
  pr.category,
  pr.state,
  pr.description,
  pr.ref_code,
  pr.clothing_size,
  pr.gender,
  pr.created_at,
  coalesce(pr.is_sold, false) as is_sold
from public.products pr
join public.hub_profiles_public hp on hp.id = pr.seller_id
where coalesce(pr.list_on_marketplace, false) = true
  and coalesce(pr.is_sold, false) = false
  and coalesce(pr.is_draft, false) = false
  and public.batata_product_hub_sellable(pr.id) = true;

comment on view public.hub_products_public is
  'Marketplace público: listado, não vendido, não rascunho, com stock efectivo (holds).';

grant select on public.hub_products_public to anon, authenticated;

-- RLS: anúncios públicos nunca incluem rascunhos.
drop policy if exists "products_select_marketplace_or_own" on public.products;
create policy "products_select_marketplace_or_own"
  on public.products
  for select
  to authenticated
  using (
    (
      coalesce(is_draft, false) = false
      and list_on_marketplace = true
      and coalesce(is_sold, false) = false
    )
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
    coalesce(is_draft, false) = false
    and list_on_marketplace = true
    and coalesce(is_sold, false) = false
  );

notify pgrst, 'reload schema';
