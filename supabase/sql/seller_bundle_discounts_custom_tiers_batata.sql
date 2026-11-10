-- Regras de desconto personalizadas (além dos escalões 2/3/5 pré-definidos).

alter table public.seller_bundle_discounts
  add column if not exists custom_tiers jsonb not null default '[]'::jsonb;

comment on column public.seller_bundle_discounts.custom_tiers is
  'Array JSON: [{ "min_items": 4, "pct": 12.5 }, ...]';
