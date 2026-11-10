-- Fleaber BATATA: permissões de administração.
-- Define um admin através de profiles.user_type in ('admin', 'admim', 'administrador', 'administracao').

create or replace function public.batata_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $batata_admin$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.user_type, '')) in (
        'admin',
        'admim',
        'administrador',
        'administracao'
      )
  );
$batata_admin$;

drop policy if exists "orders_admin_all" on public.orders;
create policy "orders_admin_all"
  on public.orders
  for all
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists "products_admin_all" on public.products;
create policy "products_admin_all"
  on public.products
  for all
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists "profiles_admin_select" on public.profiles;
create policy "profiles_admin_select"
  on public.profiles
  for select
  using (public.batata_is_admin());

drop policy if exists "wallets_admin_select" on public.wallets;
create policy "wallets_admin_select"
  on public.wallets
  for select
  using (public.batata_is_admin());

drop policy if exists "wallet_transactions_admin_select" on public.wallet_transactions;
create policy "wallet_transactions_admin_select"
  on public.wallet_transactions
  for select
  using (public.batata_is_admin());

drop policy if exists "fleaber_commissions_admin_select" on public.fleaber_commissions;
create policy "fleaber_commissions_admin_select"
  on public.fleaber_commissions
  for select
  using (public.batata_is_admin());

drop policy if exists "order_disputes_admin_all" on public.order_disputes;
create policy "order_disputes_admin_all"
  on public.order_disputes
  for all
  using (public.batata_is_admin())
  with check (public.batata_is_admin());

drop policy if exists "order_dispute_replies_admin_all" on public.order_dispute_replies;
create policy "order_dispute_replies_admin_all"
  on public.order_dispute_replies
  for all
  using (public.batata_is_admin())
  with check (public.batata_is_admin());
