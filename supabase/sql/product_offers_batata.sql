-- Propostas de preço (estilo Vinted) — marketplace.
-- Executar no SQL Editor do Supabase.

create table if not exists public.product_offers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  chat_id uuid references public.chats(id) on delete set null,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12, 2) not null check (amount > 0),
  list_price numeric(12, 2),
  offered_by text not null check (offered_by in ('buyer', 'seller')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'superseded', 'expired')),
  parent_offer_id uuid references public.product_offers(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '48 hours'),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create index if not exists product_offers_product_buyer_idx
  on public.product_offers (product_id, buyer_id, created_at desc);

create index if not exists product_offers_chat_idx
  on public.product_offers (chat_id);

create unique index if not exists product_offers_one_pending_per_thread
  on public.product_offers (product_id, buyer_id)
  where status = 'pending';

alter table public.product_offers enable row level security;

drop policy if exists "product_offers_select_parties" on public.product_offers;
create policy "product_offers_select_parties"
  on public.product_offers
  for select
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "product_offers_insert_parties" on public.product_offers;
create policy "product_offers_insert_parties"
  on public.product_offers
  for insert
  to authenticated
  with check (
    (offered_by = 'buyer' and buyer_id = auth.uid())
    or (offered_by = 'seller' and seller_id = auth.uid())
  );

drop policy if exists "product_offers_update_parties" on public.product_offers;
create policy "product_offers_update_parties"
  on public.product_offers
  for update
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid())
  with check (buyer_id = auth.uid() or seller_id = auth.uid());
