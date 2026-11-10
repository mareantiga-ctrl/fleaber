-- Fleaber BATATA: catálogo de artigos por live (viewer + vendedor).
-- Executar no SQL Editor do Supabase se os cards «artigos no directo» estiverem vazios.

create table if not exists public.live_items (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  live_id uuid not null references public.lives (id) on delete cascade,
  ref_code text not null,
  title text,
  price numeric,
  is_active boolean not null default false
);

-- Tabela já existia sem photo_url (erro PGRST204 no sync).
alter table public.live_items
  add column if not exists photo_url text;

create index if not exists live_items_live_id_idx
  on public.live_items (live_id, created_at);

alter table public.live_items enable row level security;

drop policy if exists "live_items_select_for_live" on public.live_items;
create policy "live_items_select_for_live"
  on public.live_items
  for select
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (
          l.status in ('live', 'ended')
          or l.is_active = true
          or auth.uid() = l.seller_id
          or auth.uid() = l.vendedor_id
        )
    )
  );

drop policy if exists "live_items_insert_own_live" on public.live_items;
create policy "live_items_insert_own_live"
  on public.live_items
  for insert
  with check (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (auth.uid() = l.seller_id or auth.uid() = l.vendedor_id)
    )
  );

drop policy if exists "live_items_update_own_live" on public.live_items;
create policy "live_items_update_own_live"
  on public.live_items
  for update
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (auth.uid() = l.seller_id or auth.uid() = l.vendedor_id)
    )
  )
  with check (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (auth.uid() = l.seller_id or auth.uid() = l.vendedor_id)
    )
  );

drop policy if exists "live_items_delete_own_live" on public.live_items;
create policy "live_items_delete_own_live"
  on public.live_items
  for delete
  using (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (auth.uid() = l.seller_id or auth.uid() = l.vendedor_id)
    )
  );
