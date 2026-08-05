-- SEC-014 — Helper não pode alargar permissions / identidade ao aceitar convite
-- BATATA: aceitar/rejeitar convite continua; só o seller muda permissions.
-- Staging / SQL Editor — idempotente.

create or replace function public.batata_seller_helpers_guard_helper_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  -- service_role / sem JWT (jobs): não interferir
  if v_uid is null or v_role is distinct from 'authenticated' then
    return NEW;
  end if;

  -- Dono da loja: pode alterar tudo (incluindo permissions)
  if NEW.seller_id is not null and NEW.seller_id = v_uid then
    return NEW;
  end if;

  -- Helper: só pode responder ao convite (ou campos de presença), nunca permissions
  if NEW.helper_user_id is not null and NEW.helper_user_id = v_uid then
    -- Identidade e permissões imutáveis para o helper
    NEW.seller_id := OLD.seller_id;
    NEW.helper_user_id := OLD.helper_user_id;
    NEW.permissions := OLD.permissions;
    NEW.invited_by := OLD.invited_by;
    NEW.invited_email := OLD.invited_email;
    NEW.invitation_note := OLD.invitation_note;
    NEW.display_name := OLD.display_name;

    if OLD.invitation_status = 'pending' then
      -- Só accepted / rejected
      if NEW.invitation_status is distinct from 'accepted'
         and NEW.invitation_status is distinct from 'rejected' then
        NEW.invitation_status := OLD.invitation_status;
      end if;
      if NEW.invitation_status = 'accepted' then
        NEW.active := true;
      elsif NEW.invitation_status = 'rejected' then
        NEW.active := false;
      end if;
      NEW.responded_at := coalesce(NEW.responded_at, now());
    else
      -- Já respondeu: não muda estado do convite / active via UPDATE directo
      NEW.invitation_status := OLD.invitation_status;
      NEW.active := OLD.active;
      NEW.responded_at := OLD.responded_at;
      -- last_active_at / updated_at podem mudar (se a policy RLS permitir)
    end if;

    return NEW;
  end if;

  return NEW;
end;
$fn$;

drop trigger if exists batata_seller_helpers_guard_helper_update_tg
  on public.seller_helpers;

create trigger batata_seller_helpers_guard_helper_update_tg
  before update on public.seller_helpers
  for each row
  execute function public.batata_seller_helpers_guard_helper_update();

-- Reforço RLS: helper só UPDATE enquanto pending; seller sempre
-- (imutabilidade de permissions/identidade = trigger acima)
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

notify pgrst, 'reload schema';
