-- Liga encomenda à proposta aceite (opcional, para auditoria).

alter table public.orders
  add column if not exists product_offer_id uuid
  references public.product_offers(id) on delete set null;

create index if not exists orders_product_offer_idx
  on public.orders (product_offer_id)
  where product_offer_id is not null;
