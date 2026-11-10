-- Canal de origem do chat público (Fleaber / Hub / Facebook).
-- Face Lab + PS espelham comentários FB com channel = 'facebook'.

alter table public.live_messages
  add column if not exists channel text;

update public.live_messages
set channel = 'fleaber'
where channel is null or trim(channel) = '';

alter table public.live_messages
  alter column channel set default 'fleaber';

alter table public.live_messages
  alter column channel set not null;

do $$
declare
  c text;
begin
  select conname into c
  from pg_constraint
  where conrelid = 'public.live_messages'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%channel%';
  if c is not null then
    execute format('alter table public.live_messages drop constraint if exists %I', c);
  end if;
end $$;

alter table public.live_messages
  drop constraint if exists live_messages_channel_check;

alter table public.live_messages
  add constraint live_messages_channel_check
  check (channel in ('fleaber', 'hub', 'facebook'));

comment on column public.live_messages.channel is
  'Origem: fleaber | hub | facebook (badge F no chat público).';

create index if not exists live_messages_live_channel_idx
  on public.live_messages (live_id, channel, created_at desc);

-- View pública Hub: expor channel.
create or replace view public.hub_live_messages_public
with (security_barrier = true)
as
select
  m.id,
  m.live_id,
  m.kind,
  m.body,
  m.sender_label,
  m.tip_amount,
  m.created_at,
  m.channel
from public.live_messages m
join public.hub_lives_public hl on hl.id = m.live_id
where m.kind in ('chat', 'tip', 'system');

comment on view public.hub_live_messages_public is
  'Chat público do directo (leitura). Sem user_id nem tip_id. Inclui channel.';

grant select on public.hub_live_messages_public to anon, authenticated;

-- Espelho Face/PS → chat (service role / security definer).
create or replace function public.batata_live_mirror_facebook_chat(
  p_live_id uuid,
  p_sender_label text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_label text := nullif(trim(coalesce(p_sender_label, '')), '');
  v_body text := nullif(trim(coalesce(p_body, '')), '');
begin
  if p_live_id is null or v_body is null then
    return null;
  end if;
  if v_label is null then
    v_label := 'Facebook';
  end if;
  if not exists (
    select 1 from public.lives l
    where l.id = p_live_id
  ) then
    raise exception 'live_not_found';
  end if;

  insert into public.live_messages (
    live_id,
    user_id,
    kind,
    body,
    sender_label,
    channel
  ) values (
    p_live_id,
    null,
    'chat',
    v_body,
    v_label,
    'facebook'
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.batata_live_mirror_facebook_chat(uuid, text, text) from public;
grant execute on function public.batata_live_mirror_facebook_chat(uuid, text, text)
  to service_role;

comment on function public.batata_live_mirror_facebook_chat(uuid, text, text) is
  'Espelha comentário Facebook (Lab/PS) para live_messages com channel=facebook.';
