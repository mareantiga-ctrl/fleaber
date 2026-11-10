-- Fleaber BATATA: histórico de «artigo a mostrar» por segundo (replay VOD).
-- Executar no SQL Editor do Supabase. Sem esta tabela, a gravação só reflecte o is_active final.

create table if not exists public.live_item_show_events (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid not null references public.lives (id) on delete cascade,
  live_item_id uuid not null references public.live_items (id) on delete cascade,
  shown_at timestamptz not null default now()
);

create index if not exists live_item_show_events_live_shown_idx
  on public.live_item_show_events (live_id, shown_at);

alter table public.live_item_show_events enable row level security;

drop policy if exists "live_item_show_events_select_for_live" on public.live_item_show_events;
create policy "live_item_show_events_select_for_live"
  on public.live_item_show_events
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

drop policy if exists "live_item_show_events_insert_own_live" on public.live_item_show_events;
create policy "live_item_show_events_insert_own_live"
  on public.live_item_show_events
  for insert
  with check (
    exists (
      select 1
      from public.lives l
      where l.id = live_id
        and (auth.uid() = l.seller_id or auth.uid() = l.vendedor_id)
    )
  );
