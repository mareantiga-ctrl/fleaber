-- Projecto H v1 staging: view follower_count/hub_bio + seller demo UX (só staging).
-- NÃO aplicar em produção.

-- =============================================================================
-- 1) H-v1 hub_profiles_public
-- =============================================================================
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

-- =============================================================================
-- 2) Seed seller demo UX (dados fictícios — só validação visual)
-- =============================================================================
create or replace function public.batata_staging_h_v1_ux_demo_seed(
  p_seller_id uuid default '980f4fa1-0004-42f9-abca-69f1a9c29588'::uuid,
  p_buyer_id uuid default '7848848c-92df-4341-ad2a-7a5c24f1c250'::uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_handle text := 'fleahub-demo-ux';
  v_live_id uuid;
  v_followers int := 0;
  v_products int := 0;
  v_reviews int := 0;
  v_gravados int := 0;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'seller_required');
  end if;

  perform set_config('batata.handle_rpc', '1', true);

  update public.profiles p
  set
    handle = v_handle,
    hub_published = true,
    full_name = 'Maria Demo FleaHub',
    photo_url = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800&auto=format&fit=crop',
    location = 'Lisboa, Portugal',
    hub_bio = '✦ Dados de demonstração UX — não são dados reais de negócio. Roupa vintage e peças únicas curadas em Lisboa.',
    is_live = true
  where p.id = p_seller_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'profile_not_found');
  end if;

  -- Uma live activa para «Em directo agora»
  update public.lives l
  set is_active = false, status = 'ended'
  where coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    and l.status = 'live'
    and coalesce(l.is_active, false) = true;

  select l.id into v_live_id
  from public.lives l
  where coalesce(l.seller_id, l.vendedor_id) = p_seller_id
    and l.mux_playback_id is not null
  order by l.created_at desc nulls last
  limit 1;

  if v_live_id is not null then
    update public.lives l
    set
      title = 'Directo demo UX — FleaHub H-v1',
      status = 'live',
      is_active = true,
      viewer_count = greatest(coalesce(l.viewer_count, 0), 24)
    where l.id = v_live_id;
  end if;

  select count(*)::int into v_gravados
  from public.hub_lives_public hl
  where hl.seller_id = p_seller_id
    and hl.status = 'ended'
    and coalesce(hl.mux_playback_id, hl.mux_vod_playback_id) is not null;

  -- Produtos demo marketplace
  delete from public.products pr
  where pr.seller_id = p_seller_id
    and coalesce(pr.ref_code, '') like 'UX-DEMO-%';

  insert into public.products (
    seller_id, title, price, image_urls, ref_code, category, state,
    list_on_marketplace, available_for_live, quantity, is_sold, description
  )
  values
    (
      p_seller_id,
      'Casaco vintage lã · UX demo',
      45.00,
      array['https://images.unsplash.com/photo-1551028719-00167b16c0a9?w=600&auto=format&fit=crop'],
      'UX-DEMO-001',
      'Roupa',
      'Como novo',
      true, false, 1, false,
      'Peça de demonstração FleaHub H-v1.'
    ),
    (
      p_seller_id,
      'Vestido floral · UX demo',
      32.00,
      '["https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=600&auto=format&fit=crop"]'::jsonb,
      'UX-DEMO-002',
      'Roupa',
      'Bom estado',
      true, false, 1, false,
      'Peça de demonstração FleaHub H-v1.'
    ),
    (
      p_seller_id,
      'Bolsa pele · UX demo',
      58.00,
      '["https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=600&auto=format&fit=crop"]'::jsonb,
      'UX-DEMO-003',
      'Acessórios',
      'Como novo',
      true, false, 1, false,
      'Peça de demonstração FleaHub H-v1.'
    ),
    (
      p_seller_id,
      'Sapatilhas retro · UX demo',
      41.00,
      '["https://images.unsplash.com/photo-1460353581641-37baddab0fa2?w=600&auto=format&fit=crop"]'::jsonb,
      'UX-DEMO-004',
      'Calçado',
      'Bom estado',
      true, false, 1, false,
      'Peça de demonstração FleaHub H-v1.'
    );

  get diagnostics v_products = row_count;

  -- Reviews demo
  delete from public.reviews_gerais r
  where r.target_id = p_seller_id
    and coalesce(r.comment, '') like '%UX demo FleaHub%';

  insert into public.reviews_gerais (
    target_id, buyer_id, stars, comment, target_type, is_automatic
  )
  values
    (p_seller_id, p_buyer_id, 5, 'Entrega rápida e peça como descrita. UX demo FleaHub.', 'seller', false),
    (p_seller_id, p_buyer_id, 4, 'Boa comunicação durante a compra. UX demo FleaHub.', 'seller', false),
    (p_seller_id, p_buyer_id, 5, 'Recomendo — experiência muito positiva. UX demo FleaHub.', 'seller', false);

  get diagnostics v_reviews = row_count;

  -- Seguidores demo (contagem agregada via v_seguidores_stats)
  delete from public.follows f
  where f.following_id = p_seller_id
    and f.follower_id in (
      select p.id from public.profiles p
      where p.id <> p_seller_id
      order by p.created_at nulls last
      limit 12
    );

  insert into public.follows (follower_id, following_id)
  select p.id, p_seller_id
  from public.profiles p
  where p.id <> p_seller_id
  order by p.created_at nulls last
  limit 12
  on conflict do nothing;

  select coalesce(vs.total_seguidores, 0)::int into v_followers
  from public.v_seguidores_stats vs
  where vs.profile_id = p_seller_id;

  return jsonb_build_object(
    'ok', true,
    'handle', v_handle,
    'profile_id', p_seller_id,
    'hub_published', true,
    'live_id', v_live_id,
    'follower_count', v_followers,
    'products_seeded', v_products,
    'reviews_seeded', v_reviews,
    'gravados_public', v_gravados,
    'disclaimer', 'Dados fictícios — só validação UX staging'
  );
end;
$$;

revoke all on function public.batata_staging_h_v1_ux_demo_seed(uuid, uuid) from public;
grant execute on function public.batata_staging_h_v1_ux_demo_seed(uuid, uuid) to service_role;

notify pgrst, 'reload schema';
