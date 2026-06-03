-- Executar no SQL Editor do Supabase (projeto Fleaber).
-- Tabela de inventário para anúncios (marketplace + live).

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  price numeric(12, 2) not null check (price >= 0),
  image_urls jsonb not null default '[]'::jsonb,
  category text,
  brand text,
  condition text,
  description text,
  list_on_marketplace boolean not null default true,
  available_for_live boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists products_seller_id_idx on public.products (seller_id);
create index if not exists products_list_marketplace_idx on public.products (list_on_marketplace);
create index if not exists products_available_live_idx on public.products (available_for_live);

alter table public.products enable row level security;

create policy "products_select_marketplace_or_own"
  on public.products
  for select
  to authenticated
  using (list_on_marketplace = true or seller_id = auth.uid());

create policy "products_insert_own"
  on public.products
  for insert
  to authenticated
  with check (auth.uid() = seller_id);

create policy "products_update_own"
  on public.products
  for update
  to authenticated
  using (auth.uid() = seller_id)
  with check (auth.uid() = seller_id);

create policy "products_delete_own"
  on public.products
  for delete
  to authenticated
  using (auth.uid() = seller_id);

-- Opcional: bucket dedicado "product_media" com políticas de upload.
-- O app usa por defeito o bucket "chat_media" com prefixo product_photos/ (igual ao chat).

-- Campos adicionais (executar mesmo que a tabela já exista).
alter table public.products add column if not exists ref_code text;
alter table public.products add column if not exists clothing_size text;
alter table public.products add column if not exists gender text;
