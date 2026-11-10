-- =============================================================================
-- BATATA 2026-09-12 — Hub catálogo também em GRAVADO (ended)
--
-- hub_live_items_public só listava status=live → gravado = «Sem artigos».
-- Manter: sem paused/sold; stock; is_active = destaque (não filtro).
-- =============================================================================

create or replace view public.hub_live_items_public
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
join public.hub_lives_public hl on hl.id = li.live_id
where lower(trim(coalesce(hl.status, ''))) in ('live', 'ended')
  and (
    lower(trim(coalesce(hl.status, ''))) = 'ended'
    or coalesce(hl.is_active, false) = true
  )
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and (
    -- Gravado: mostrar catálogo mesmo com stock 0 (histórico / esgotado).
    lower(trim(coalesce(hl.status, ''))) = 'ended'
    or coalesce(
      (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
    ) > 0
  );

comment on view public.hub_live_items_public is
  'Catálogo Hub AO VIVO + GRAVADO. is_active = destaque, não filtro. '
  'Live activa: só stock>0. Ended: catálogo histórico.';

grant select on public.hub_live_items_public to anon, authenticated, service_role;

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
join public.hub_lives_discovery_public hl on hl.id = li.live_id
where lower(trim(coalesce(hl.status, ''))) in ('live', 'ended')
  and (
    lower(trim(coalesce(hl.status, ''))) = 'ended'
    or coalesce(hl.is_active, false) = true
  )
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and (
    lower(trim(coalesce(hl.status, ''))) = 'ended'
    or coalesce(
      (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
    ) > 0
  );

comment on view public.hub_live_items_discovery_public is
  'Discovery: igual a hub_live_items_public (live + ended).';

grant select on public.hub_live_items_discovery_public to anon, authenticated, service_role;
