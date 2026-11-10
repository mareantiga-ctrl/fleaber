-- Fleaber BATATA: feed de descoberta FleaHub (landing /fleahub).
-- E0817-A: perfis = hub_published OU directo real; lives ended = só hub_published.
-- Vitrine publicada continua em hub_profiles_public.
--
-- Ordem na app: 1) ao vivo  2) gravados recentes (loja publicada)  3) FleaHubs publicados

-- Slug público para descoberta: handle claimado → sugerido → derivado do nome (ex. Joao84 → joao84).
create or replace function public.batata_profile_discovery_slug(
  p_handle text,
  p_handle_suggested text,
  p_full_name text
) returns text
language sql
stable
set search_path = public, extensions
as $$
  select coalesce(
    nullif(public.batata_normalize_handle(coalesce(p_handle, '')), ''),
    nullif(public.batata_normalize_handle(coalesce(p_handle_suggested, '')), ''),
    nullif(
      public.batata_normalize_handle(
        regexp_replace(trim(coalesce(p_full_name, '')), '[^a-zA-Z0-9]+', '-', 'g')
      ),
      ''
    )
  );
$$;

comment on function public.batata_profile_discovery_slug(text, text, text) is
  'Slug FleaHub para descoberta sem handle claimado (fallback nome).';

grant execute on function public.batata_profile_discovery_slug(text, text, text)
  to anon, authenticated, service_role;

create or replace view public.hub_lives_discovery_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as seller_handle,
  nullif(trim(p.full_name), '') as seller_name,
  nullif(trim(p.photo_url), '') as seller_photo_url,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  l.mux_playback_id,
  l.mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
inner join public.profiles p
  on p.id = coalesce(l.seller_id, l.vendedor_id)
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = true
    )
    or (
      coalesce(l.is_active, false) = true
      and lower(trim(coalesce(l.status, ''))) in ('live', 'scheduled', 'ao_vivo', 'active')
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
      and coalesce(p.hub_published, false) = true
    )
  );

comment on view public.hub_lives_discovery_public is
  'E0817-2A: live activa OK; ended só se hub_published.';

grant select on public.hub_lives_discovery_public to anon, authenticated;

-- Perfil discovery: publicado OU directo real (não is_live sozinho).
create or replace view public.hub_profiles_discovery_public
with (security_barrier = true)
as
select
  p.id,
  public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
    as handle,
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
  nullif(trim(p.hub_bio), '') as hub_bio,
  coalesce(p.hub_published, false) as hub_published
from public.profiles p
left join public.v_seguidores_stats vs on vs.profile_id = p.id
where length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    coalesce(p.hub_published, false) = true
    or exists (
      select 1
      from public.lives l
      where coalesce(l.seller_id, l.vendedor_id) = p.id
        and (
          (
            lower(trim(coalesce(l.status, ''))) = 'live'
            and coalesce(l.is_active, false) = true
          )
          or (
            coalesce(l.is_active, false) = true
            and lower(trim(coalesce(l.status, ''))) in ('live', 'ao_vivo', 'active')
          )
        )
    )
  );

comment on view public.hub_profiles_discovery_public is
  'E0817-1A: hub_published OU directo real a decorrer (não is_live sozinho).';

grant select on public.hub_profiles_discovery_public to anon, authenticated;

-- Artigos de live na descoberta (join lives discovery, não só vitrine publicada).
create or replace view public.hub_live_items_discovery_public
with (security_barrier = true)
as
select
  li.id,
  li.live_id,
  hl.seller_id,
  hl.seller_handle,
  li.ref_code,
  li.title,
  li.photo_url,
  li.price,
  coalesce(li.is_active, false) as is_active,
  li.status,
  li.item_kind,
  li.clothing_size,
  li.gender,
  li.created_at
from public.live_items li
join public.hub_lives_discovery_public hl on hl.id = li.live_id;

comment on view public.hub_live_items_discovery_public is
  'Catálogo artigos live — feed descoberta (handle, sem hub_published).';

grant select on public.hub_live_items_discovery_public to anon, authenticated;

notify pgrst, 'reload schema';
