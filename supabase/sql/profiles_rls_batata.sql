-- !!! QUARANTINED FASE 3B — NÃO APLICAR
-- Este ficheiro contém policies `USING (true)` / anon SELECT aberto em profiles.
-- Reaplicar REABRE dump PII. Fonte de verdade: SCHEMA_SOURCE_OF_TRUTH.md +
-- scripts SEC de profiles endurecidos (não este ficheiro).
do $$ begin
  raise exception 'QUARANTINED: profiles_rls_batata.sql — não aplicar (reabre RLS perigoso)';
end $$;

-- Perfis: linha garantida + RLS para UPDATE/INSERT do próprio utilizador.
-- Correr no SQL Editor Supabase (resolve PGRST116 ao guardar morada / modo férias).
--
-- Causa habitual de falha na versão anterior: ON CONFLICT (id) sem UNIQUE em profiles.id.

-- 0) Índice único em id (opcional; ignora se houver duplicados)
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'profiles' and indexname = 'profiles_id_uidx'
  ) and not exists (
    select 1 from public.profiles group by id having count(*) > 1
  ) then
    create unique index profiles_id_uidx on public.profiles (id);
  end if;
exception when others then
  raise notice 'profiles_id_uidx skipped: %', sqlerrm;
end $$;

-- 1) Backfill: auth.users sem linha em profiles
do $$
declare
  v_has_user_type boolean;
begin
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'user_type'
  ) into v_has_user_type;

  if v_has_user_type then
    insert into public.profiles (id, full_name, user_type)
    select
      u.id,
      coalesce(
        nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(u.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
        'Utilizador'
      ),
      'vendedor'
    from auth.users u
    where not exists (select 1 from public.profiles p where p.id = u.id);
  else
    insert into public.profiles (id, full_name)
    select
      u.id,
      coalesce(
        nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(u.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
        'Utilizador'
      )
    from auth.users u
    where not exists (select 1 from public.profiles p where p.id = u.id);
  end if;
end $$;

-- 2) Função + trigger (opcional; se falhar, RLS e backfill mantêm-se)
create or replace function public.batata_handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_user_type boolean;
begin
  if exists (select 1 from public.profiles p where p.id = new.id) then
    return new;
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'user_type'
  ) into v_has_user_type;

  if v_has_user_type then
    insert into public.profiles (id, full_name, user_type)
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(new.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Utilizador'
      ),
      'vendedor'
    );
  else
    insert into public.profiles (id, full_name)
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(new.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Utilizador'
      )
    );
  end if;
  return new;
exception when others then
  raise notice 'batata_handle_new_user_profile: %', sqlerrm;
  return new;
end;
$$;

do $$
begin
  drop trigger if exists on_auth_user_created_profile on auth.users;
  create trigger on_auth_user_created_profile
    after insert on auth.users
    for each row
    execute function public.batata_handle_new_user_profile();
exception when others then
  raise notice 'Trigger auth.users skipped (normal em alguns projectos): %', sqlerrm;
end $$;

-- 3) RLS — parte crítica para UPDATE funcionar na app
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_auth" on public.profiles;
create policy "profiles_select_auth"
  on public.profiles for select to authenticated using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "profiles_select_anon" on public.profiles;
create policy "profiles_select_anon"
  on public.profiles for select to anon using (true);

notify pgrst, 'reload schema';
