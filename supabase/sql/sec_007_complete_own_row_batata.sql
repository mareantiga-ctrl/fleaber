-- SEC-007 completo — BATATA
-- 1) View directory sem PII sensível (phone/shipping/iban/mb_way/legal_full_name)
-- 2) RLS authenticated: só a própria linha em public.profiles
-- 3) Admin lista via RPC SECURITY DEFINER
-- 4) Unicidade de nome via RPC (Conta)
-- Mantém: batata_get_my_payout_details, batata_seller_direct_payment_details
-- Hub: hub_profiles_public inalterado

-- =============================================================================
-- 1) Directory view (authenticated)
-- =============================================================================
create or replace view public.profiles_directory_public
with (security_barrier = true)
as
select
  p.id,
  p.created_at,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  p.user_type,
  p.handle,
  coalesce(p.vacation_mode, false) as vacation_mode,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  (p.phone_verified_at is not null) as phone_verified
from public.profiles p;

comment on view public.profiles_directory_public is
  'SEC-007: vitrine autenticada — sem phone/shipping/iban/mb_way/legal_full_name';

grant select on public.profiles_directory_public to authenticated;
-- anon continua a usar hub_profiles_public; não dar directory a anon
revoke all on public.profiles_directory_public from anon;

-- =============================================================================
-- 2) Admin list (só batata_is_admin)
-- =============================================================================
create or replace function public.batata_admin_list_profiles(p_limit int default 120)
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.batata_is_admin() then
    raise exception 'Acesso negado.';
  end if;
  return query
  select p.*
  from public.profiles p
  order by p.created_at desc nulls last
  limit greatest(1, least(coalesce(p_limit, 120), 500));
end;
$$;

revoke all on function public.batata_admin_list_profiles(int) from public;
grant execute on function public.batata_admin_list_profiles(int) to authenticated;

-- =============================================================================
-- 3) Nome em uso (Conta / registo) — sem expor linhas
-- =============================================================================
create or replace function public.batata_is_full_name_taken(p_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm text := lower(trim(coalesce(p_name, '')));
begin
  if auth.uid() is null then
    raise exception 'Não autenticado.';
  end if;
  if v_norm = '' then
    return false;
  end if;
  return exists (
    select 1
    from public.profiles p
    where lower(trim(coalesce(p.full_name, ''))) = v_norm
      and p.id is distinct from auth.uid()
  );
end;
$$;

revoke all on function public.batata_is_full_name_taken(text) from public;
grant execute on function public.batata_is_full_name_taken(text) to authenticated;

-- =============================================================================
-- 4) RLS — SELECT só próprio
-- =============================================================================
drop policy if exists "profiles_select_auth" on public.profiles;
create policy "profiles_select_auth"
  on public.profiles for select to authenticated
  using (id = auth.uid());

-- Policies FlutterFlow legadas (USING true) — OR com own-row = buraco reaberto
drop policy if exists "Permitir leitura" on public.profiles;
drop policy if exists "Enable read access for all users" on public.profiles;
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
drop policy if exists "Public profiles are viewable by everyone." on public.profiles;

-- Reforço: anon sem SELECT (idempotente com fase 1a)
drop policy if exists "profiles_select_anon" on public.profiles;
do $$
begin
  revoke select on table public.profiles from anon;
exception
  when undefined_object then null;
  when others then null;
end $$;

-- Colunas bancárias: manter revoke authenticated (fase 1b)
do $$
begin
  revoke select (iban, mb_way) on table public.profiles from authenticated;
exception
  when others then null;
end $$;

notify pgrst, 'reload schema';

comment on function public.batata_admin_list_profiles(int) is
  'SEC-007: lista perfis só para admin';
comment on function public.batata_is_full_name_taken(text) is
  'SEC-007: verifica unicidade de full_name sem SELECT aberto';
