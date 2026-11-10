-- =============================================================================
-- BATATA — is_active = «a mostrar agora» (destaque), NÃO «vendável / no catálogo»
--
-- Regressão observada 2026-09-12 (live f90d7927-…):
--   FX1/FX2 existiam (status=available, qty>0) com is_active=false
--   → hub_live_items_public devolvia 0 linhas («Zero artigos»)
--   → trigger sellable levantava live_item_not_sellable no PS ingest
--
-- Mantém bloqueio por status paused/inactive/sold/reserved_full + stock.
-- NÃO reabre RLS nem grants.
-- =============================================================================

-- 1) Reserva / accept: não exigir is_active
create or replace function public.batata_live_reservation_requests_guard_item_sellable()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_status text;
begin
  select lower(trim(coalesce(li.status, '')))
  into v_status
  from public.live_items li
  where li.id = NEW.live_item_id;
  if v_status is null then
    raise exception 'live_item_not_found' using errcode = '23514';
  end if;
  if v_status in ('paused', 'inactive', 'sold', 'reserved_full') then
    raise exception 'live_item_not_sellable' using errcode = '42501';
  end if;
  return NEW;
end;
$fn$;

comment on function public.batata_live_reservation_requests_guard_item_sellable() is
  'Bloqueia pending/accept se status do item for paused/inactive/sold/reserved_full. '
  'is_active (destaque vitrine) NÃO bloqueia venda.';

-- 2) Hub catálogo AO VIVO: todos os itens vendáveis (destaque só ordena na UI)
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
where lower(trim(coalesce(hl.status, ''))) = 'live'
  and coalesce(hl.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

comment on view public.hub_live_items_public is
  'Catálogo público AO VIVO: itens vendáveis com stock. '
  'is_active = destaque (ordenar na UI), não filtro de pertença.';

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
where lower(trim(coalesce(hl.status, ''))) = 'live'
  and coalesce(hl.is_active, false) = true
  and lower(trim(coalesce(li.status, ''))) not in (
    'paused', 'inactive', 'sold', 'reserved_full'
  )
  and (
    lower(trim(coalesce(li.item_kind, ''))) = 'marketplace_product'
    or coalesce(li.quantity, 0) > 0
  )
  and coalesce(
    (public.batata_live_item_stock(li.id)->>'available_qty')::int, 0
  ) > 0;

comment on view public.hub_live_items_discovery_public is
  'Discovery: igual a hub_live_items_public (sem filtrar is_active).';

grant select on public.hub_live_items_discovery_public to anon, authenticated, service_role;
