-- Fleaber BATATA: políticas mínimas para `orders` (SELECT + UPDATE pelo vendedor).
-- Sintoma na app: `status_raw=pago` após «anular venda» → o UPDATE `status = cancelado`
-- não afectava nenhuma linha (RLS), sem erro visível.
--
-- Executa no SQL Editor do Supabase. Se já existirem políticas equivalentes,
-- ajusta os nomes ou funde com as tuas regras (não dupliques lógica conflituosa).

alter table if exists public.orders enable row level security;

-- Leitura: comprador ou vendedor da encomenda vê a linha.
drop policy if exists "orders_select_parties" on public.orders;
create policy "orders_select_parties"
  on public.orders
  for select
  to authenticated
  using (
    buyer_id = auth.uid()
    or seller_id = auth.uid()
  );

-- Inserção: só quem participa (comprador ou vendedor) — alinha com checkout na app.
drop policy if exists "orders_insert_parties" on public.orders;
create policy "orders_insert_parties"
  on public.orders
  for insert
  to authenticated
  with check (
    buyer_id = auth.uid()
    or seller_id = auth.uid()
  );

-- UPDATE: vendedor pode alterar a própria encomenda (cancelar, enviar, etc.).
drop policy if exists "orders_update_seller_own" on public.orders;
create policy "orders_update_seller_own"
  on public.orders
  for update
  to authenticated
  using (seller_id = auth.uid())
  with check (seller_id = auth.uid());

-- UPDATE: comprador pode alterar apenas a própria encomenda (ex.: comprovativo, estados iniciais).
drop policy if exists "orders_update_buyer_own" on public.orders;
create policy "orders_update_buyer_own"
  on public.orders
  for update
  to authenticated
  using (buyer_id = auth.uid())
  with check (buyer_id = auth.uid());
