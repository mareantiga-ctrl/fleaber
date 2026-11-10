-- Projecto H v1: seguidores públicos + bio FleaHub (Sobre).
-- Pré-requisito: hub_public_views_batata.sql (#19) em staging.
-- NÃO executar em produção sem aprovação explícita.
--
-- Rollback:
--   drop view if exists hub_profiles_public;
--   alter table public.profiles drop column if exists hub_bio;
--   -- Re-aplicar hub_public_views_batata.sql secção hub_profiles_public

alter table public.profiles
  add column if not exists hub_bio text;

comment on column public.profiles.hub_bio is
  'Texto público «Sobre» no FleaHub. Omitir secção se NULL/vazio.';

create or replace view public.hub_profiles_public
with (security_barrier = true)
as
select
  p.id,
  p.handle,
  p.full_name,
  p.photo_url,
  p.location,
  p.is_live,
  p.next_live,
  p.last_live,
  p.total_lives,
  coalesce(p.vacation_mode, false) as vacation_mode,
  (p.phone_verified_at is not null) as phone_verified,
  coalesce(p.external_payments_enabled, false) as external_payments_enabled,
  coalesce(vs.total_seguidores, 0)::int as follower_count,
  nullif(trim(p.hub_bio), '') as hub_bio
from public.profiles p
left join public.v_seguidores_stats vs on vs.profile_id = p.id
where p.hub_published = true
  and p.handle is not null
  and trim(p.handle) <> '';

comment on view public.hub_profiles_public is
  'Vitrine pública Hub Perfil. Whitelist — sem PII financeira/morada.';

grant select on public.hub_profiles_public to anon, authenticated;

notify pgrst, 'reload schema';
