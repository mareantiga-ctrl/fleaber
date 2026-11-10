-- BATATA: profiles.total_lives desalinhado da tabela lives (ex. joao84 = 0 com 382 lives).
-- Backfill + trigger. Não toca RLS nem stream keys.

-- 1) Backfill
update public.profiles p
set total_lives = coalesce((
  select count(*)::int
  from public.lives l
  where coalesce(l.seller_id, l.vendedor_id) = p.id
    and lower(coalesce(l.status, '')) in ('ended', 'live', 'scheduled')
), 0);

-- 2) Manter actualizado
create or replace function public.batata_profiles_refresh_total_lives()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
begin
  if tg_op = 'DELETE' then
    v_seller := coalesce(old.seller_id, old.vendedor_id);
  else
    v_seller := coalesce(new.seller_id, new.vendedor_id);
  end if;

  if v_seller is null then
    return coalesce(new, old);
  end if;

  update public.profiles
  set total_lives = (
    select count(*)::int
    from public.lives l
    where coalesce(l.seller_id, l.vendedor_id) = v_seller
      and lower(coalesce(l.status, '')) in ('ended', 'live', 'scheduled')
  )
  where id = v_seller;

  -- Se mudou dono (raro), actualiza o antigo também
  if tg_op = 'UPDATE' then
    if coalesce(old.seller_id, old.vendedor_id) is distinct from v_seller
       and coalesce(old.seller_id, old.vendedor_id) is not null then
      update public.profiles
      set total_lives = (
        select count(*)::int
        from public.lives l
        where coalesce(l.seller_id, l.vendedor_id) = coalesce(old.seller_id, old.vendedor_id)
          and lower(coalesce(l.status, '')) in ('ended', 'live', 'scheduled')
      )
      where id = coalesce(old.seller_id, old.vendedor_id);
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_batata_profiles_total_lives on public.lives;
create trigger trg_batata_profiles_total_lives
after insert or update of status, seller_id, vendedor_id or delete
on public.lives
for each row
execute function public.batata_profiles_refresh_total_lives();

comment on function public.batata_profiles_refresh_total_lives() is
  'BATATA: profiles.total_lives = count(lives ended|live|scheduled)';

notify pgrst, 'reload schema';
