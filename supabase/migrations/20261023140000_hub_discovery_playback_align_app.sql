-- Hub discovery: alinhar playback e gravados com a Home da app Fleaber.
-- ADDITIVE — sem DROP de dados; só redefine views públicas Hub.
--
-- Problemas corrigidos:
-- 1) View anulava mux_playback_id em ended → Hub só via VOD; app usa VOD ?? playback.
-- 2) Lives live+is_active=false (gravados na app) excluídas da discovery.
-- 3) Mesma lógica em hub_lives_public para o player/perfil.

BEGIN;

create or replace view public.hub_lives_public
with (security_barrier = true)
as
select
  l.id,
  coalesce(l.seller_id, l.vendedor_id) as seller_id,
  hp.handle as seller_handle,
  l.title,
  l.status,
  coalesce(l.is_active, false) as is_active,
  -- IDs Mux de playback são públicos; o cliente decide live vs VOD.
  l.mux_playback_id,
  l.mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend,
  l.cover_id
from public.lives l
join public.hub_profiles_public hp
  on hp.id = coalesce(l.seller_id, l.vendedor_id)
where lower(trim(coalesce(l.status, ''))) in ('scheduled', 'live', 'ended');

grant select on public.hub_lives_public to anon, authenticated;

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
  l.publish_backend,
  l.cover_id
from public.lives l
inner join public.profiles p
  on p.id = coalesce(l.seller_id, l.vendedor_id)
where coalesce(p.hub_published, false) = true
  and length(
    public.batata_profile_discovery_slug(p.handle, p.handle_suggested, p.full_name)
  ) >= 2
  and (
    (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = true
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'live'
      and coalesce(l.is_active, false) = false
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'scheduled'
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
    )
  );

grant select on public.hub_lives_discovery_public to anon, authenticated;

commit;
