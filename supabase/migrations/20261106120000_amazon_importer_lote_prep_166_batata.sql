-- =============================================================================
-- ZIP 166-C2 — Preparação lote completo (584 ASIN / 625 unidades)
-- Isolado: só objectos amazon_*. Não toca Stripe / DPD / lives / bundles.
-- =============================================================================

-- Retoma / pausa no lote
alter table public.amazon_import_lots
  add column if not exists pause_requested boolean not null default false;

alter table public.amazon_import_lots
  add column if not exists cursor_row int not null default 0;

alter table public.amazon_import_lots
  add column if not exists source_csv_text text;

comment on column public.amazon_import_lots.source_csv_text is
  'CSV original (admin) para pausa/retoma sem reenviar ficheiro. Limpar após completed se desejado.';

-- Progresso por linha (dedupe + retoma sem repetir trabalho)
create table if not exists public.amazon_import_row_progress (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lot_id uuid not null references public.amazon_import_lots(id) on delete cascade,
  row_number int not null,
  lpn text,
  asin text,
  status text not null
    check (status in ('imported', 'duplicate', 'error', 'skipped')),
  error_code text,
  error_message text,
  unique (lot_id, row_number)
);

create index if not exists amazon_import_row_progress_lot_idx
  on public.amazon_import_row_progress (lot_id, row_number);

create unique index if not exists amazon_import_row_progress_lot_lpn_uidx
  on public.amazon_import_row_progress (lot_id, lpn)
  where lpn is not null and lpn <> '';

-- Campos de preparação / sync (sem publicar automático)
alter table public.amazon_catalog_products
  add column if not exists approved_at timestamptz;

alter table public.amazon_catalog_products
  add column if not exists approved_by uuid references auth.users(id);

alter table public.amazon_catalog_products
  add column if not exists missing_reasons text[] not null default '{}'::text[];

alter table public.amazon_catalog_products
  add column if not exists fleaber_product_id uuid;

alter table public.amazon_catalog_products
  add column if not exists moloni_product_id text;

alter table public.amazon_catalog_products
  add column if not exists fleaber_sync_status text not null default 'none'
    check (fleaber_sync_status in (
      'none', 'pending', 'simulated_ok', 'ok', 'error', 'blocked'
    ));

alter table public.amazon_catalog_products
  add column if not exists moloni_sync_status text not null default 'none'
    check (moloni_sync_status in (
      'none', 'pending', 'simulated_ok', 'ok', 'error', 'blocked'
    ));

alter table public.amazon_catalog_products
  add column if not exists fleaber_sync_error text;

alter table public.amazon_catalog_products
  add column if not exists moloni_sync_error text;

alter table public.amazon_catalog_products
  add column if not exists last_approved_note text;

-- Histórico de alterações / aprovações
create table if not exists public.amazon_approval_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  actor_id uuid references auth.users(id),
  product_id uuid not null references public.amazon_catalog_products(id) on delete cascade,
  action text not null
    check (action in (
      'approve', 'unapprove', 'edit_price', 'edit_copy', 'edit_condition',
      'mark_incomplete', 'simulate_fleaber', 'simulate_moloni', 'bulk_approve'
    )),
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  note text
);

create index if not exists amazon_approval_events_product_idx
  on public.amazon_approval_events (product_id, created_at desc);

-- View de prontidão (só leitura)
create or replace view public.amazon_catalog_readiness as
select
  p.id,
  p.asin,
  p.ean,
  p.title,
  p.catalog_status,
  p.approved_sale_eur,
  p.suggested_sale_eur,
  p.manifest_weight_kg,
  p.shipping_weight_kg,
  p.primary_image_url,
  p.missing_reasons,
  p.approved_at,
  p.fleaber_sync_status,
  p.moloni_sync_status,
  (
    coalesce(p.approved_sale_eur, p.suggested_sale_eur) is not null
    and coalesce(nullif(trim(p.title), ''), null) is not null
    and coalesce(nullif(trim(p.primary_image_url), ''), null) is not null
    and p.shipping_weight_kg is not null
  ) as is_ready_to_approve,
  (
    select count(*)::int from public.amazon_catalog_units u where u.product_id = p.id
  ) as unit_count
from public.amazon_catalog_products p;

comment on view public.amazon_catalog_readiness is
  'ZIP 166: prontidão para aprovação (não implica publicação Fleaber/Moloni).';

-- RLS
alter table public.amazon_import_row_progress enable row level security;
alter table public.amazon_approval_events enable row level security;

drop policy if exists amazon_import_row_progress_admin_all on public.amazon_import_row_progress;
create policy amazon_import_row_progress_admin_all on public.amazon_import_row_progress
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

drop policy if exists amazon_approval_events_admin_all on public.amazon_approval_events;
create policy amazon_approval_events_admin_all on public.amazon_approval_events
  for all to authenticated
  using (public.batata_is_amazon_importer_admin())
  with check (public.batata_is_amazon_importer_admin());

grant select, insert, update, delete on public.amazon_import_row_progress to authenticated;
grant select, insert, update, delete on public.amazon_approval_events to authenticated;
grant select on public.amazon_catalog_readiness to authenticated;

-- Função: recalcular missing_reasons
create or replace function public.batata_amazon_refresh_missing_reasons(p_product_id uuid)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.amazon_catalog_products%rowtype;
  reasons text[] := '{}';
begin
  if not public.batata_is_amazon_importer_admin() then
    raise exception 'not authorized';
  end if;
  select * into r from public.amazon_catalog_products where id = p_product_id;
  if not found then
    raise exception 'product not found';
  end if;
  if coalesce(r.approved_sale_eur, r.suggested_sale_eur) is null then
    reasons := array_append(reasons, 'missing_price');
  end if;
  if coalesce(nullif(trim(r.title), ''), null) is null then
    reasons := array_append(reasons, 'missing_title');
  end if;
  if coalesce(nullif(trim(r.description), ''), null) is null then
    reasons := array_append(reasons, 'missing_description');
  end if;
  if coalesce(nullif(trim(r.primary_image_url), ''), null) is null then
    reasons := array_append(reasons, 'missing_photo');
  end if;
  if r.shipping_weight_kg is null and r.manifest_weight_kg is null then
    reasons := array_append(reasons, 'missing_weight');
  end if;
  update public.amazon_catalog_products
    set missing_reasons = reasons,
        updated_at = timezone('utc', now())
    where id = p_product_id;
  return reasons;
end;
$$;

revoke all on function public.batata_amazon_refresh_missing_reasons(uuid) from public;
grant execute on function public.batata_amazon_refresh_missing_reasons(uuid)
  to authenticated, service_role;
