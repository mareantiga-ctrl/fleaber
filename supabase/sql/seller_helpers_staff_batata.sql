-- Fleaber BATATA: colaboradores (helpers) com permissões granulares + auditoria.
-- Executar no SQL Editor do Supabase.

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------

create table if not exists public.seller_helpers (
  id uuid primary key default extensions.gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  helper_user_id uuid not null references public.profiles (id) on delete cascade,
  invited_email text,
  display_name text not null default '',
  active boolean not null default true,
  invitation_status text not null default 'pending',
  invitation_note text,
  responded_at timestamptz,
  permissions jsonb not null default '{}'::jsonb,
  last_active_at timestamptz,
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint seller_helpers_unique_member unique (seller_id, helper_user_id),
  constraint seller_helpers_not_self check (seller_id <> helper_user_id),
  constraint seller_helpers_invitation_status_chk
    check (invitation_status in ('pending', 'accepted', 'rejected'))
);

alter table public.seller_helpers
  add column if not exists invited_email text;
alter table public.seller_helpers
  add column if not exists invitation_status text not null default 'pending';
alter table public.seller_helpers
  add column if not exists invitation_note text;
alter table public.seller_helpers
  add column if not exists responded_at timestamptz;

create index if not exists seller_helpers_seller_idx
  on public.seller_helpers (seller_id, active);

create index if not exists seller_helpers_helper_idx
  on public.seller_helpers (helper_user_id, active);

create table if not exists public.staff_action_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  seller_id uuid not null references public.profiles (id) on delete cascade,
  performed_by_user_id uuid not null references public.profiles (id) on delete cascade,
  target_entity text not null,
  target_id text,
  action_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists staff_action_logs_seller_created_idx
  on public.staff_action_logs (seller_id, created_at desc);

create index if not exists staff_action_logs_actor_idx
  on public.staff_action_logs (performed_by_user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Funções auxiliares (validação server-side)
-- ---------------------------------------------------------------------------

create or replace function public.batata_find_user_id_by_email(p_email text)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select u.id
  from auth.users u
  where lower(trim(u.email)) = lower(trim(p_email))
  limit 1;
$$;

revoke all on function public.batata_find_user_id_by_email(text) from public;
grant execute on function public.batata_find_user_id_by_email(text) to authenticated;

create or replace function public.batata_is_seller_owner(p_seller_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select auth.uid() is not null and auth.uid() = p_seller_id;
$$;

revoke all on function public.batata_is_seller_owner(uuid) from public;
grant execute on function public.batata_is_seller_owner(uuid) to authenticated;

create or replace function public.batata_staff_has_permission(
  p_seller_id uuid,
  p_permission text
)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_perms jsonb;
begin
  if auth.uid() is null or p_seller_id is null then
    return false;
  end if;

  if auth.uid() = p_seller_id then
    return true;
  end if;

  select h.permissions
  into v_perms
  from public.seller_helpers h
  where h.seller_id = p_seller_id
    and h.helper_user_id = auth.uid()
    and h.active = true
    and h.invitation_status = 'accepted'
  limit 1;

  if v_perms is null then
    return false;
  end if;

  return coalesce((v_perms ->> p_permission)::boolean, false);
end;
$$;

revoke all on function public.batata_staff_has_permission(uuid, text) from public;
grant execute on function public.batata_staff_has_permission(uuid, text) to authenticated;

create or replace function public.batata_staff_ping_active(p_seller_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;
  update public.seller_helpers
  set last_active_at = now(), updated_at = now()
  where seller_id = p_seller_id
    and helper_user_id = auth.uid()
    and active = true;
end;
$$;

revoke all on function public.batata_staff_ping_active(uuid) from public;
grant execute on function public.batata_staff_ping_active(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.seller_helpers enable row level security;
alter table public.staff_action_logs enable row level security;

drop policy if exists seller_helpers_select on public.seller_helpers;
create policy seller_helpers_select on public.seller_helpers
  for select using (
    seller_id = auth.uid()
    or helper_user_id = auth.uid()
  );

drop policy if exists seller_helpers_insert on public.seller_helpers;
create policy seller_helpers_insert on public.seller_helpers
  for insert with check (
    seller_id = auth.uid()
    and invited_by = auth.uid()
    and helper_user_id <> auth.uid()
  );

drop policy if exists seller_helpers_update on public.seller_helpers;
create policy seller_helpers_update on public.seller_helpers
  for update using (
    seller_id = auth.uid()
    or (helper_user_id = auth.uid() and invitation_status = 'pending')
  )
  with check (
    seller_id = auth.uid()
    or (
      helper_user_id = auth.uid()
      and invitation_status in ('accepted', 'rejected')
      and responded_at is not null
    )
  );

drop policy if exists seller_helpers_delete on public.seller_helpers;
create policy seller_helpers_delete on public.seller_helpers
  for delete using (seller_id = auth.uid());

drop policy if exists staff_action_logs_select on public.staff_action_logs;
create policy staff_action_logs_select on public.staff_action_logs
  for select using (
    seller_id = auth.uid()
    or performed_by_user_id = auth.uid()
    or public.batata_staff_has_permission(seller_id, 'can_view_analytics')
  );

drop policy if exists staff_action_logs_insert on public.staff_action_logs;
create policy staff_action_logs_insert on public.staff_action_logs
  for insert with check (
    performed_by_user_id = auth.uid()
    and (
      seller_id = auth.uid()
      or exists (
        select 1 from public.seller_helpers h
        where h.seller_id = staff_action_logs.seller_id
          and h.helper_user_id = auth.uid()
          and h.active = true
      )
    )
  );

-- Notificação in-app ao colaborador (RLS de user_notifications não permite INSERT directo).
create or replace function public.batata_notify_helper_invitation(
  p_helper_user_id uuid,
  p_seller_helpers_id uuid,
  p_actor_id uuid default auth.uid()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_helper_user_id is null or p_seller_helpers_id is null then
    return null;
  end if;

  if not exists (
    select 1
    from public.seller_helpers h
    where h.id = p_seller_helpers_id
      and h.helper_user_id = p_helper_user_id
      and h.seller_id = auth.uid()
      and h.invitation_status = 'pending'
  ) then
    raise exception 'not_allowed: seller_helpers row missing or not pending for this owner';
  end if;

  insert into public.user_notifications (
    user_id,
    kind,
    title,
    body,
    actor_id,
    is_read
  )
  values (
    p_helper_user_id,
    'helper_invitation:' || p_seller_helpers_id::text,
    'Convite para colaborar numa loja',
    'Recebeste um convite para colaborar numa loja Fleaber.',
    coalesce(p_actor_id, auth.uid()),
    false
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.batata_notify_helper_invitation(uuid, uuid, uuid) from public;
grant execute on function public.batata_notify_helper_invitation(uuid, uuid, uuid) to authenticated;
