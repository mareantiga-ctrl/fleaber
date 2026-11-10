-- ZIP 156: fotos CDN Amazon (direitos pendentes) + metadados LLM local
-- Produção: bpmpkzwnrbmuqnhgdscf

alter table public.amazon_product_photos
  drop constraint if exists amazon_product_photos_source_check;

alter table public.amazon_product_photos
  add constraint amazon_product_photos_source_check
  check (source in (
    'upload',
    'camera',
    'amazon_ref_pending_rights',
    'amazon_cdn_pending_rights'
  ));

alter table public.amazon_catalog_products
  add column if not exists title_original text;

alter table public.amazon_catalog_products
  add column if not exists llm_model text;

alter table public.amazon_catalog_products
  add column if not exists llm_generated_at timestamptz;

alter table public.amazon_catalog_products
  add column if not exists photo_rights_status text
  default 'unknown';

comment on column public.amazon_catalog_products.photo_rights_status is
  'unknown | pending_rights | licensed | own_photos | missing';

comment on column public.amazon_catalog_products.llm_model is
  'Modelo local usado (ex. qwen3:8b via Ollama); null se manual/heurística.';
