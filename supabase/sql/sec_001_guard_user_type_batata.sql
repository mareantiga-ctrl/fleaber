-- SEC-001 — Impedir auto-promoção a admin via profiles.user_type
-- Risco regressão: Médio (registo/perfil continuam a poder pôr vendedor/comprador)
-- Executar no SQL Editor / staging. Admins legítimos: Dashboard SQL ou service_role.

create or replace function public.batata_profiles_guard_user_type()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_new text := lower(trim(coalesce(NEW.user_type, '')));
  v_is_admin_claim boolean := v_new in (
    'admin',
    'admim',
    'administrador',
    'administracao'
  );
begin
  if not v_is_admin_claim then
    return NEW;
  end if;

  -- Só bloquear clientes autenticados (JWT role=authenticated).
  -- service_role / SQL Editor (sem uid de end-user) podem promover admins.
  if auth.uid() is not null
     and coalesce(auth.role(), '') = 'authenticated' then
    if TG_OP = 'UPDATE' then
      NEW.user_type := OLD.user_type;
    else
      -- INSERT a tentar nascer admin → demote para vendedor (fluxo registo seller)
      NEW.user_type := 'vendedor';
    end if;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists trg_batata_profiles_guard_user_type on public.profiles;
create trigger trg_batata_profiles_guard_user_type
  before insert or update of user_type
  on public.profiles
  for each row
  execute function public.batata_profiles_guard_user_type();

comment on function public.batata_profiles_guard_user_type() is
  'SEC-001: authenticated users cannot set user_type to admin*; service_role/SQL OK.';

notify pgrst, 'reload schema';
