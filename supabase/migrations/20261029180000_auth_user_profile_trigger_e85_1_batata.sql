-- E85.1 — trigger auth.users → profiles (produção: função existia, trigger ausente).
-- Não desactiva confirmação de e-mail.

create or replace function public.batata_handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_user_type boolean;
  v_has_phone boolean;
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

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'phone'
  ) into v_has_phone;

  if v_has_user_type and v_has_phone then
    insert into public.profiles (id, full_name, phone, user_type)
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(new.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Utilizador'
      ),
      nullif(trim(coalesce(new.raw_user_meta_data->>'phone', '')), ''),
      coalesce(nullif(trim(new.raw_user_meta_data->>'user_type'), ''), 'vendedor')
    );
  elsif v_has_user_type then
    insert into public.profiles (id, full_name, user_type)
    values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
        nullif(trim(new.raw_user_meta_data->>'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Utilizador'
      ),
      coalesce(nullif(trim(new.raw_user_meta_data->>'user_type'), ''), 'vendedor')
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

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row
  execute function public.batata_handle_new_user_profile();
