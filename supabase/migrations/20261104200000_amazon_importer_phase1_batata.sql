-- =============================================================================
-- ZIP Amazon Importer Fase 1 — catálogo privado admin-only
-- Isolado: só cria objectos amazon_* + batata_is_amazon_importer_admin().
-- Não altera tabelas/funções de checkout, Stripe, DPD, lives, bundles, etc.
-- =============================================================================

create or replace function public.batata_is_amazon_importer_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  -- Autorização por role admin (profiles.user_type), nunca só email no cliente.
  select public.batata_is_admin();
$$;

comment on function public.batata_is_amazon_importer_admin() is
  'Importador Amazon: allowlist = batata_is_admin(). UI só mostra a admins.';

revoke all on function public.batata_is_amazon_importer_admin() from public;
grant execute on function public.batata_is_amazon_importer_admin()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Lotes (ficheiros manifesto)
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_import_lots (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  source_filename text not null,
  source_sha256 text,
  source_storage_path text,
  status text not null default 'draft'
    check (status in (
      'draft', 'validating', 'importing', 'paused', 'completed', 'failed'
    )),
  row_count int not null default 0,
  distinct_asin_count int not null default 0,
  imported_units int not null default 0,
  duplicate_units int not null default 0,
  error_count int not null default 0,
  progress_pct numeric(5,2) not null default 0,
  last_error text,
  default_discount_pct numeric(5,2) not null default 50.00,
  notes text,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists amazon_import_lots_created_at_idx
  on public.amazon_import_lots (created_at desc);

-- -----------------------------------------------------------------------------
-- Produtos (ASIN / EAN) — nível catálogo
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_catalog_products (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  asin text not null,
  ean text,
  upc text,
  title text,
  description text,
  brand text,
  category text,
  subcategory text,
  weight_grams numeric,
  dimensions_cm text,
  primary_image_url text,
  catalog_status text not null default 'imported'
    check (catalog_status in (
      'imported', 'researching', 'researched', 'needs_review',
      'prepared', 'approved', 'exported_moloni', 'draft_fleaber', 'archived'
    )),
  suggested_sale_eur numeric(12,2),
  approved_sale_eur numeric(12,2),
  discount_pct numeric(5,2) default 50.00,
  reference_offer_id uuid,
  real_acquisition_cost_eur numeric(12,2),
  prep_notes text,
  unique (asin)
);

create index if not exists amazon_catalog_products_ean_idx
  on public.amazon_catalog_products (ean)
  where ean is not null and ean <> '';

-- -----------------------------------------------------------------------------
-- Unidades físicas (LPN) — nunca fundir condições diferentes
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_catalog_units (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lot_id uuid not null references public.amazon_import_lots(id) on delete cascade,
  product_id uuid not null references public.amazon_catalog_products(id) on delete restrict,
  lpn text not null,
  asin text not null,
  condition_code text,
  condition_label text,
  qty int not null default 1 check (qty > 0),
  manifesto_cost_eur numeric(12,2),
  manifesto_retail_eur numeric(12,2),
  manifesto_currency text default 'EUR',
  sku_fc text,
  fnsku text,
  internal_ref text,
  package_weight numeric,
  package_weight_uom text,
  raw_row jsonb not null default '{}'::jsonb,
  unique (lpn)
);

create index if not exists amazon_catalog_units_lot_idx
  on public.amazon_catalog_units (lot_id);
create index if not exists amazon_catalog_units_asin_idx
  on public.amazon_catalog_units (asin);
create index if not exists amazon_catalog_units_product_idx
  on public.amazon_catalog_units (product_id);

-- -----------------------------------------------------------------------------
-- Ofertas / pesquisa por país (cache)
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_market_offers (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  product_id uuid not null references public.amazon_catalog_products(id) on delete cascade,
  marketplace text not null
    check (marketplace in ('es', 'it', 'de', 'fr', 'manual')),
  asin text not null,
  fetched_at timestamptz,
  status text not null default 'pending'
    check (status in (
      'pending', 'ok', 'not_found', 'blocked', 'captcha', 'error', 'skipped'
    )),
  title text,
  description text,
  price_amount numeric(12,2),
  currency text,
  availability text,
  condition_label text,
  image_urls jsonb not null default '[]'::jsonb,
  weight_grams numeric,
  dimensions_cm text,
  source_url text,
  raw_excerpt text,
  error_text text,
  unique (product_id, marketplace, fetched_at)
);

create index if not exists amazon_market_offers_product_idx
  on public.amazon_market_offers (product_id, fetched_at desc);

-- -----------------------------------------------------------------------------
-- Histórico de consultas
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_research_runs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid references auth.users(id),
  lot_id uuid references public.amazon_import_lots(id) on delete set null,
  scope text not null default 'manual',
  status text not null default 'running'
    check (status in (
      'running', 'paused', 'completed', 'blocked', 'failed', 'cancelled'
    )),
  asin_count int not null default 0,
  done_count int not null default 0,
  ok_count int not null default 0,
  blocked_count int not null default 0,
  error_count int not null default 0,
  cursor_index int not null default 0,
  throttle_ms int not null default 2500,
  pause_requested boolean not null default false,
  last_asin text,
  last_error text,
  notes text,
  meta jsonb not null default '{}'::jsonb
);

-- -----------------------------------------------------------------------------
-- Fotografias reais (preparação)
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_product_photos (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  product_id uuid not null references public.amazon_catalog_products(id) on delete cascade,
  unit_id uuid references public.amazon_catalog_units(id) on delete set null,
  storage_path text not null,
  public_url text,
  sort_order int not null default 0,
  is_primary boolean not null default false,
  source text not null default 'upload'
    check (source in ('upload', 'camera', 'amazon_ref_pending_rights'))
);

create index if not exists amazon_product_photos_product_idx
  on public.amazon_product_photos (product_id, sort_order);

-- -----------------------------------------------------------------------------
-- Export / ligações futuras Moloni + Fleaber
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_export_links (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  product_id uuid not null references public.amazon_catalog_products(id) on delete cascade,
  target text not null check (target in ('moloni', 'fleaber_draft')),
  external_id text,
  status text not null default 'pending'
    check (status in ('pending', 'ok', 'error', 'skipped')),
  last_error text,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists amazon_export_links_product_idx
  on public.amazon_export_links (product_id, target);

-- -----------------------------------------------------------------------------
-- Erros de importação (retoma)
-- -----------------------------------------------------------------------------
create table if not exists public.amazon_import_row_errors (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  lot_id uuid not null references public.amazon_import_lots(id) on delete cascade,
  row_number int,
  lpn text,
  asin text,
  error_code text,
  error_message text,
  raw_row jsonb
);

create index if not exists amazon_import_row_errors_lot_idx
  on public.amazon_import_row_errors (lot_id);

-- -----------------------------------------------------------------------------
-- RLS — só admin importador
-- -----------------------------------------------------------------------------
alter table public.amazon_import_lots enable row level security;
alter table public.amazon_catalog_products enable row level security;
alter table public.amazon_catalog_units enable row level security;
alter table public.amazon_market_offers enable row level security;
alter table public.amazon_research_runs enable row level security;
alter table public.amazon_product_photos enable row level security;
alter table public.amazon_export_links enable row level security;
alter table public.amazon_import_row_errors enable row level security;

drop policy if exists amazon_import_lots_admin_all on public.amazon_import_lots;
create policy amazon_import_lots_admin_all on public.amazon_import_lots
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_catalog_products_admin_all on public.amazon_catalog_products;
create policy amazon_catalog_products_admin_all on public.amazon_catalog_products
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_catalog_units_admin_all on public.amazon_catalog_units;
create policy amazon_catalog_units_admin_all on public.amazon_catalog_units
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_market_offers_admin_all on public.amazon_market_offers;
create policy amazon_market_offers_admin_all on public.amazon_market_offers
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_research_runs_admin_all on public.amazon_research_runs;
create policy amazon_research_runs_admin_all on public.amazon_research_runs
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_product_photos_admin_all on public.amazon_product_photos;
create policy amazon_product_photos_admin_all on public.amazon_product_photos
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_export_links_admin_all on public.amazon_export_links;
create policy amazon_export_links_admin_all on public.amazon_export_links
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_import_row_errors_admin_all on public.amazon_import_row_errors;
create policy amazon_import_row_errors_admin_all on public.amazon_import_row_errors
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

-- Storage bucket (privado) — criar via dashboard se não existir; policy SQL:
-- object path prefix amazon_importer/

grant select, insert, update, delete on public.amazon_import_lots to authenticated;
grant select, insert, update, delete on public.amazon_catalog_products to authenticated;
grant select, insert, update, delete on public.amazon_catalog_units to authenticated;
grant select, insert, update, delete on public.amazon_market_offers to authenticated;
grant select, insert, update, delete on public.amazon_research_runs to authenticated;
grant select, insert, update, delete on public.amazon_product_photos to authenticated;
grant select, insert, update, delete on public.amazon_export_links to authenticated;
grant select, insert, update, delete on public.amazon_import_row_errors to authenticated;
