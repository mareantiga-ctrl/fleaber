-- Chat público do directo + presença de espectadores (BATATA).
-- Executar no SQL Editor Supabase após live_streaming_mux_batata.sql e live_tips_batata.sql.

create table if not exists public.live_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  kind text not null default 'chat'
    check (kind in ('chat', 'tip')),
  body text not null,
  sender_label text,
  tip_amount numeric(12, 2),
  tip_id uuid references public.live_tips(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists live_messages_live_created_idx
  on public.live_messages (live_id, created_at desc);

create table if not exists public.live_viewers (
  live_id uuid not null references public.lives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  primary key (live_id, user_id)
);

create index if not exists live_viewers_live_seen_idx
  on public.live_viewers (live_id, last_seen_at desc);

alter table public.live_messages enable row level security;
alter table public.live_viewers enable row level security;

drop policy if exists "live_messages_select_auth" on public.live_messages;
create policy "live_messages_select_auth"
  on public.live_messages
  for select
  to authenticated
  using (true);

drop policy if exists "live_messages_insert_chat" on public.live_messages;
create policy "live_messages_insert_chat"
  on public.live_messages
  for insert
  to authenticated
  with check (
    kind = 'chat'
    and user_id = auth.uid()
    and exists (
      select 1 from public.lives l
      where l.id = live_id
        and (l.status = 'live' or l.is_active = true)
    )
  );

drop policy if exists "live_viewers_select_auth" on public.live_viewers;
create policy "live_viewers_select_auth"
  on public.live_viewers
  for select
  to authenticated
  using (true);

drop policy if exists "live_viewers_upsert_self" on public.live_viewers;
create policy "live_viewers_upsert_self"
  on public.live_viewers
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Gorjeta concluída → mensagem pública sem nome (identidade só na live_tips).
create or replace function public.batata_live_tip_broadcast_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed'
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and new.live_id is not null then
    insert into public.live_messages (
      live_id,
      user_id,
      kind,
      body,
      sender_label,
      tip_amount,
      tip_id
    ) values (
      new.live_id,
      new.buyer_id,
      'tip',
      'Recebeu uma gorjeta',
      null,
      round(new.amount, 2),
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists live_tips_broadcast_message_trg on public.live_tips;
create trigger live_tips_broadcast_message_trg
  after insert or update of status on public.live_tips
  for each row
  execute function public.batata_live_tip_broadcast_message();

-- Heartbeat do espectador; devolve nº de utilizadores activos (~45 s).
create or replace function public.batata_live_viewer_ping(p_live_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null or p_live_id is null then
    return 0;
  end if;

  insert into public.live_viewers (live_id, user_id, last_seen_at)
  values (p_live_id, v_uid, now())
  on conflict (live_id, user_id)
  do update set last_seen_at = excluded.last_seen_at;

  delete from public.live_viewers
  where live_id = p_live_id
    and last_seen_at < now() - interval '45 seconds';

  select count(*)::integer into v_count
  from public.live_viewers
  where live_id = p_live_id;

  update public.lives
  set viewer_count = v_count
  where id = p_live_id;

  return v_count;
end;
$$;

alter table public.lives
  add column if not exists viewer_count integer not null default 0;

grant execute on function public.batata_live_viewer_ping(uuid) to authenticated;

-- Realtime (chat público visível durante o directo)
do $$
begin
  alter publication supabase_realtime add table public.live_messages;
exception
  when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
