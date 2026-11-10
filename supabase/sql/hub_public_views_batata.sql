-- Fleaber BATATA: views públicas Hub (#19) + RPC FOMO agregada.
-- Pré-requisito: supabase/sql/profile_handles_batata.sql (#20b) em staging.
-- Coluna opcional hub_bio: supabase/sql/hub_public_views_h_v1_batata.sql (Projecto H).
-- NÃO executar em produção sem aprovação explícita.
-- Backfill real de handles: ainda não aplicado (views vazias até hub_published + handle).
--
-- Rollback (ordem inversa):
--   revoke execute on function batata_hub_live_fomo_snapshot(uuid) from anon, authenticated;
--   drop function if exists batata_hub_live_fomo_snapshot(uuid);
--   drop view if exists hub_reviews_public, hub_live_messages_public, hub_live_items_public,
--     hub_products_public, hub_lives_public, hub_profiles_public;
--   -- Restaurar grants anon em tabelas base só se políticas anteriores forem re-aplicadas.

-- =============================================================================
-- 1) hub_profiles_public
-- =============================================================================
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

-- =============================================================================
-- 2) hub_lives_public
-- =============================================================================
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
  case
    when lower(trim(coalesce(l.status, ''))) = 'live'
         and coalesce(l.is_active, false) = true
      then l.mux_playback_id
    else null
  end as mux_playback_id,
  case
    when lower(trim(coalesce(l.status, ''))) = 'ended'
      then l.mux_vod_playback_id
    else null
  end as mux_vod_playback_id,
  coalesce(l.viewer_count, 0) as viewer_count,
  l.went_live_at,
  l.created_at,
  l.publish_backend
from public.lives l
join public.hub_profiles_public hp
  on hp.id = coalesce(l.seller_id, l.vendedor_id)
where lower(trim(coalesce(l.status, ''))) in ('scheduled', 'live', 'ended');

comment on view public.hub_lives_public is
  'Lives Hub: scheduled|live|ended apenas. VOD só ended; playback live só live+active. Sem stream keys.';

-- =============================================================================
-- 3) hub_products_public
-- =============================================================================
create or replace view public.hub_products_public
with (security_barrier = true)
as
select
  pr.id,
  pr.seller_id,
  hp.handle as seller_handle,
  pr.title,
  pr.price,
  pr.image_urls,
  pr.category,
  pr.state,
  pr.description,
  pr.ref_code,
  pr.clothing_size,
  pr.gender,
  pr.created_at,
  coalesce(pr.is_sold, false) as is_sold
from public.products pr
join public.hub_profiles_public hp on hp.id = pr.seller_id
where coalesce(pr.list_on_marketplace, false) = true
  and coalesce(pr.is_sold, false) = false
  and public.batata_product_hub_sellable(pr.id) = true;

comment on view public.hub_products_public is
  'Marketplace público: listado, não vendido, com stock efectivo (holds).';

-- =============================================================================
-- 4) hub_live_items_public
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
join public.hub_lives_public hl on hl.id = li.live_id;

comment on view public.hub_live_items_public is
  'Catálogo de artigos de lives públicas. Sem quantity exacta (FOMO via RPC).';

-- =============================================================================
-- 5) hub_live_messages_public
-- =============================================================================
create or replace view public.hub_live_messages_public
with (security_barrier = true)
as
select
  m.id,
  m.live_id,
  m.kind,
  m.body,
  m.sender_label,
  m.tip_amount,
  m.created_at,
  coalesce(m.channel, 'fleaber') as channel
from public.live_messages m
join public.hub_lives_public hl on hl.id = m.live_id
where m.kind in ('chat', 'tip', 'system');

comment on view public.hub_live_messages_public is
  'Chat público do directo (leitura). Sem user_id nem tip_id. Inclui channel.';

-- =============================================================================
-- 6) hub_reviews_public
-- =============================================================================
create or replace view public.hub_reviews_public
with (security_barrier = true)
as
select
  r.id,
  r.target_id,
  r.target_type,
  r.stars,
  r.comment,
  r.created_at,
  coalesce(r.is_automatic, false) as is_automatic,
  case
    when coalesce(r.is_automatic, false) then 'Avaliação automática'
    when nullif(trim(p.full_name), '') is not null then
      left(split_part(trim(p.full_name), ' ', 1), 24)
    else 'Compradora verificada'
  end as author_display
from public.reviews_gerais r
join public.hub_profiles_public hp on hp.id = r.target_id
left join public.profiles p on p.id = r.buyer_id
where coalesce(r.target_type, 'seller') in ('seller', 'vendedor', 'profile');

comment on view public.hub_reviews_public is
  'Avaliações públicas do seller Hub. Sem buyer_id.';

-- =============================================================================
-- 7) RPC batata_hub_live_fomo_snapshot (agregados — sem PII)
-- =============================================================================
create or replace function public.batata_hub_live_fomo_snapshot(p_live_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_live public.hub_lives_public%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_row record;
  v_stock jsonb;
  v_pending int;
begin
  if p_live_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_live_id');
  end if;

  select * into v_live
  from public.hub_lives_public hl
  where hl.id = p_live_id;

  if v_live.id is null then
    return jsonb_build_object('ok', false, 'error', 'live_not_public');
  end if;

  for v_row in
    select li.id as live_item_id, li.status as item_status
    from public.hub_live_items_public li
    where li.live_id = p_live_id
    order by li.is_active desc, li.created_at asc
  loop
    v_stock := public.batata_live_item_stock(v_row.live_item_id);

    select coalesce(count(*)::int, 0) into v_pending
    from public.live_reservation_requests r
    where r.live_item_id = v_row.live_item_id
      and r.status = 'pending'
      and r.source = 'fleaber_live';

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'live_item_id', v_row.live_item_id,
      'status', coalesce(v_row.item_status, 'unknown'),
      'available_qty', coalesce((v_stock->>'available_qty')::int, 0),
      'pending_queue_count', v_pending,
      'is_last_unit',
        coalesce((v_stock->>'total_qty')::int, 1) >= 2
        and coalesce((v_stock->>'available_qty')::int, 0) = 1,
      'display_reserved_qty',
        coalesce((v_stock->>'reserved_accepted_qty')::int, 0)
        + coalesce((v_stock->>'pending_bag_qty')::int, 0)
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'live_id', v_live.id,
    'viewer_count', coalesce(v_live.viewer_count, 0),
    'live_status', v_live.status,
    'is_active', v_live.is_active,
    'items', v_items
  );
end;
$$;

revoke all on function public.batata_hub_live_fomo_snapshot(uuid) from public;
grant execute on function public.batata_hub_live_fomo_snapshot(uuid) to anon, authenticated;

-- =============================================================================
-- 8) Grants views + revoga SELECT anon em tabelas base (substitui R24/R25)
-- =============================================================================
grant select on public.hub_profiles_public to anon, authenticated;
grant select on public.hub_lives_public to anon, authenticated;
grant select on public.hub_products_public to anon, authenticated;
grant select on public.hub_live_items_public to anon, authenticated;
grant select on public.hub_live_messages_public to anon, authenticated;
grant select on public.hub_reviews_public to anon, authenticated;

revoke all on table public.profiles from anon;
revoke all on table public.lives from anon;
revoke all on table public.products from anon;
revoke all on table public.live_items from anon;
revoke all on table public.live_messages from anon;
revoke all on table public.reviews_gerais from anon;

drop policy if exists "profiles_select_anon" on public.profiles;
drop policy if exists "lives_select_public_live" on public.lives;

-- Realtime Hub chat: publicação opcional pós-deploy (Hub web subscreve view ou tabela com policy)
-- alter publication supabase_realtime add table public.live_messages;
-- (preferir filtrar no cliente via hub_live_messages_public — Realtime em views limitado)

-- =============================================================================
-- 9) Self-tests (NOTICE — correr no SQL Editor ou psql)
-- =============================================================================
do $$
declare
  v_view text;
begin
  foreach v_view in array array[
    'hub_profiles_public',
    'hub_lives_public',
    'hub_products_public',
    'hub_live_items_public',
    'hub_live_messages_public',
    'hub_reviews_public'
  ]
  loop
    if not exists (
      select 1 from pg_views
      where schemaname = 'public' and viewname = v_view
    ) then
      raise exception 'self_test_fail: view % missing', v_view;
    end if;
  end loop;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'batata_hub_live_fomo_snapshot'
  ) then
    raise exception 'self_test_fail: batata_hub_live_fomo_snapshot missing';
  end if;

  -- Colunas sensíveis NÃO presentes nas views (auditoria pg_attribute)
  if exists (
    select 1
    from pg_views v
    join pg_class c on c.relname = v.viewname and c.relkind = 'v'
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    where v.schemaname = 'public'
      and v.viewname like 'hub\_%' escape '\'
      and (
        lower(a.attname) in (
          'phone', 'legal_full_name', 'iban', 'mb_way',
          'shipping_line1', 'shipping_line2', 'shipping_postal_code',
          'shipping_city', 'shipping_country', 'user_type', 'email',
          'mux_stream_key', 'stream_key', 'mux_live_id',
          'livekit_room_name', 'livekit_egress_id', 'mux_asset_id',
          'buyer_id', 'order_id', 'user_id', 'tip_id'
        )
        or (
          lower(a.attname) = 'seller_id'
          and v.viewname = 'hub_profiles_public'
        )
      )
  ) then
    raise exception 'self_test_fail: sensitive column exposed in hub_* view';
  end if;

  if not has_function_privilege('anon', 'public.batata_hub_live_fomo_snapshot(uuid)', 'EXECUTE') then
    raise exception 'self_test_fail: anon cannot execute batata_hub_live_fomo_snapshot';
  end if;

  if has_table_privilege('anon', 'public.profiles', 'SELECT') then
    raise exception 'self_test_fail: anon still has SELECT on profiles';
  end if;

  raise notice 'hub_public_views_batata self_tests OK';
end;
$$;

notify pgrst, 'reload schema';
