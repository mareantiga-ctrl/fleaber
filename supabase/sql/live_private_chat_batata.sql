-- Chat privado durante o directo (viewer ↔ vendedora) + histórico unificado.
-- Executar após live_room_batata.sql

create table if not exists public.live_private_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  kind text not null default 'private'
    check (kind in ('private', 'reservation', 'purchase')),
  meta jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists live_private_messages_live_recipient_idx
  on public.live_private_messages (live_id, recipient_id, is_read, created_at desc);

create index if not exists live_private_messages_live_pair_idx
  on public.live_private_messages (live_id, sender_id, recipient_id, created_at desc);

alter table public.live_private_messages enable row level security;

drop policy if exists "live_private_select_participant" on public.live_private_messages;
create policy "live_private_select_participant"
  on public.live_private_messages
  for select
  to authenticated
  using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
  );

drop policy if exists "live_private_insert_sender" on public.live_private_messages;
create policy "live_private_insert_sender"
  on public.live_private_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.lives l
      where l.id = live_id
        and (l.status = 'live' or l.is_active = true)
    )
  );

drop policy if exists "live_private_update_read" on public.live_private_messages;
create policy "live_private_update_read"
  on public.live_private_messages
  for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

do $$
begin
  alter publication supabase_realtime add table public.live_private_messages;
exception
  when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
