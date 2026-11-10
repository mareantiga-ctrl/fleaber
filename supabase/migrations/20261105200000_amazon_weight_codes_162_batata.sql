-- ZIP 162 — peso manifesto + margem embalagem (importador Amazon).
-- Não altera checkout/DPD Edges; só colunas de catálogo + comentário do contrato.

alter table public.amazon_catalog_products
  add column if not exists manifest_weight_kg numeric(10,4),
  add column if not exists shipping_weight_kg numeric(10,4),
  add column if not exists weight_packaging_pct numeric(5,2) not null default 10.00,
  add column if not exists weight_source text;

comment on column public.amazon_catalog_products.manifest_weight_kg is
  'Peso original do manifesto Amazon (kg), sem margem.';
comment on column public.amazon_catalog_products.shipping_weight_kg is
  'Peso de expedição = manifesto × (1+packaging_pct/100). Fonte para products.shipping_weight_kg.';
comment on column public.amazon_catalog_products.weight_packaging_pct is
  'Margem embalagem % (default 10). Reaplicar sempre sobre manifesto, nunca sobre shipping.';
comment on column public.amazon_catalog_products.weight_source is
  'Origem: manifesto | amazon_offer | manual | null.';

-- Localização de armazenamento (opcional, do manifesto InventoryLocation / FC).
alter table public.amazon_catalog_units
  add column if not exists storage_location text;

comment on column public.amazon_catalog_units.storage_location is
  'Localização física (InventoryLocation/FC do manifesto), se existir.';
