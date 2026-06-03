-- Descontos em conjuntos (estilo Vinted) — definições do vendedor + propostas.

create table if not exists public.seller_bundle_discounts (
  seller_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  tier_2_pct numeric(5, 2) check (tier_2_pct is null or (tier_2_pct >= 0 and tier_2_pct <= 50)),
  tier_3_pct numeric(5, 2) check (tier_3_pct is null or (tier_3_pct >= 0 and tier_3_pct <= 50)),
  tier_5_pct numeric(5, 2) check (tier_5_pct is null or (tier_5_pct >= 0 and tier_5_pct <= 50)),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_bundles (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  chat_id uuid references public.chats(id) on delete set null,
  product_ids uuid[] not null,
  subtotal_eur numeric(12, 2) not null check (subtotal_eur >= 0),
  discount_pct numeric(5, 2) not null default 0 check (discount_pct >= 0 and discount_pct <= 50),
  discount_eur numeric(12, 2) not null default 0 check (discount_eur >= 0),
  total_eur numeric(12, 2) not null check (total_eur >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'purchased', 'cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create index if not exists product_bundles_chat_idx on public.product_bundles (chat_id);
create index if not exists product_bundles_buyer_idx on public.product_bundles (buyer_id, created_at desc);

alter table public.seller_bundle_discounts enable row level security;
alter table public.product_bundles enable row level security;

drop policy if exists "seller_bundle_discounts_select" on public.seller_bundle_discounts;
create policy "seller_bundle_discounts_select"
  on public.seller_bundle_discounts for select to authenticated using (true);

drop policy if exists "seller_bundle_discounts_upsert_own" on public.seller_bundle_discounts;
create policy "seller_bundle_discounts_upsert_own"
  on public.seller_bundle_discounts for all to authenticated
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());

drop policy if exists "product_bundles_select_parties" on public.product_bundles;
create policy "product_bundles_select_parties"
  on public.product_bundles for select to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "product_bundles_insert_buyer" on public.product_bundles;
create policy "product_bundles_insert_buyer"
  on public.product_bundles for insert to authenticated
  with check (buyer_id = auth.uid());

drop policy if exists "product_bundles_update_parties" on public.product_bundles;
create policy "product_bundles_update_parties"
  on public.product_bundles for update to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

alter table public.orders
  add column if not exists bundle_id uuid references public.product_bundles(id) on delete set null;
