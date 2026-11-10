-- Fleaber BATATA: ligacao directa orders <-> sessao live (Centro de Resultados Pos-Live).
-- Idempotente. Executar no SQL Editor ou:
-- npx supabase db query --linked -f supabase/sql/orders_live_context_batata.sql

alter table public.orders
  add column if not exists live_id uuid references public.lives (id) on delete set null;

alter table public.orders
  add column if not exists live_item_id uuid references public.live_items (id) on delete set null;

create index if not exists orders_live_id_idx
  on public.orders (live_id);

create index if not exists orders_live_item_id_idx
  on public.orders (live_item_id);

comment on column public.orders.live_id is
  'Sessao live de origem (player live/VOD/reserva convertida). Nullable para marketplace legado.';

comment on column public.orders.live_item_id is
  'Artigo do catalogo live associado a encomenda. Nullable para marketplace legado.';
