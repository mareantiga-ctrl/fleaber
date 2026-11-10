-- BATATA: capas automáticas de directos (MVP).
-- NÃO aplicar em produção sem autorização explícita.
-- cover_id estável (ex. fleaber_capa_01) — URLs/assets resolvidos no cliente.

begin;

alter table public.lives
  add column if not exists cover_id text;

comment on column public.lives.cover_id is
  'ID estável da capa (fleaber_capa_NN). Não muda ao substituir ficheiros HD.';

create table if not exists public.live_cover_pool (
  cover_id text primary key,
  categories text[] not null default '{}',
  cycle_used_at timestamptz,
  last_live_id uuid references public.lives (id) on delete set null
);

create index if not exists live_cover_pool_unused_idx
  on public.live_cover_pool (cover_id)
  where cycle_used_at is null;

create index if not exists live_cover_pool_cats_gin
  on public.live_cover_pool using gin (categories);

-- Seed / upsert catálogo (categorias alinhadas ao formulário de anúncio).
with seed(cover_id, categories) as (
  values
    ('fleaber_capa_01', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_02', array['Casa e Decoração']::text[]),
    ('fleaber_capa_03', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_04', array['Calçado']::text[]),
    ('fleaber_capa_05', array['Roupa e Acessórios','Colecionáveis']::text[]),
    ('fleaber_capa_06', array['Beleza e Cuidados','Roupa e Acessórios']::text[]),
    ('fleaber_capa_07', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_08', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_09', array['Casa e Decoração']::text[]),
    ('fleaber_capa_10', array['Casa e Decoração']::text[]),
    ('fleaber_capa_11', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_12', array['Calçado']::text[]),
    ('fleaber_capa_13', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_14', array['Casa e Decoração','Desporto e Ar Livre']::text[]),
    ('fleaber_capa_15', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_16', array['Beleza e Cuidados']::text[]),
    ('fleaber_capa_17', array['Beleza e Cuidados']::text[]),
    ('fleaber_capa_18', array['Calçado']::text[]),
    ('fleaber_capa_19', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_20', array['Casa e Decoração']::text[]),
    ('fleaber_capa_21', array['Casa e Decoração','Electrodomésticos']::text[]),
    ('fleaber_capa_22', array['Casa e Decoração','Electrodomésticos']::text[]),
    ('fleaber_capa_23', array['Brinquedos']::text[]),
    ('fleaber_capa_24', array['Brinquedos']::text[]),
    ('fleaber_capa_25', array['Casa e Decoração']::text[]),
    ('fleaber_capa_26', array['Casa e Decoração','Beleza e Cuidados']::text[]),
    ('fleaber_capa_27', array['Casa e Decoração','Beleza e Cuidados']::text[]),
    ('fleaber_capa_28', array['Electrodomésticos','Casa e Decoração']::text[]),
    ('fleaber_capa_29', array['Casa e Decoração']::text[]),
    ('fleaber_capa_30', array['Casa e Decoração','Outra']::text[]),
    ('fleaber_capa_31', array['Casa e Decoração','Colecionáveis']::text[]),
    ('fleaber_capa_32', array['Beleza e Cuidados','Casa e Decoração']::text[]),
    ('fleaber_capa_33', array['Roupa e Acessórios','Beleza e Cuidados']::text[]),
    ('fleaber_capa_34', array['Casa e Decoração','Roupa e Acessórios']::text[]),
    ('fleaber_capa_35', array['Outra','Casa e Decoração']::text[]),
    ('fleaber_capa_36', array['Desporto e Ar Livre']::text[]),
    ('fleaber_capa_37', array['Desporto e Ar Livre','Calçado']::text[]),
    ('fleaber_capa_38', array['Desporto e Ar Livre']::text[]),
    ('fleaber_capa_39', array['Eletrónica','Roupa e Acessórios']::text[]),
    ('fleaber_capa_40', array['Eletrónica']::text[]),
    ('fleaber_capa_41', array['Eletrónica']::text[]),
    ('fleaber_capa_42', array['Desporto e Ar Livre']::text[]),
    ('fleaber_capa_43', array['Calçado','Desporto e Ar Livre']::text[]),
    ('fleaber_capa_44', array['Outra']::text[]),
    ('fleaber_capa_45', array['Roupa e Acessórios','Desporto e Ar Livre','Outra']::text[]),
    ('fleaber_capa_46', array['Roupa e Acessórios','Beleza e Cuidados','Desporto e Ar Livre']::text[]),
    ('fleaber_capa_47', array['Livros e Media','Casa e Decoração']::text[]),
    ('fleaber_capa_48', array['Livros e Media','Casa e Decoração']::text[]),
    ('fleaber_capa_49', array['Outra']::text[]),
    ('fleaber_capa_50', array['Casa e Decoração','Colecionáveis']::text[]),
    ('fleaber_capa_51', array['Casa e Decoração','Outra']::text[]),
    ('fleaber_capa_52', array['Roupa e Acessórios']::text[]),
    ('fleaber_capa_53', array['Calçado']::text[]),
    ('fleaber_capa_54', array['Brinquedos','Roupa e Acessórios']::text[]),
    ('fleaber_capa_55', array['Livros e Media','Casa e Decoração']::text[]),
    ('fleaber_capa_56', array['Casa e Decoração']::text[]),
    ('fleaber_capa_57', array['Desporto e Ar Livre']::text[]),
    ('fleaber_capa_58', array['Roupa e Acessórios','Desporto e Ar Livre']::text[]),
    ('fleaber_capa_59', array['Outra','Casa e Decoração']::text[]),
    ('fleaber_capa_60', array['Casa e Decoração']::text[])
)
insert into public.live_cover_pool (cover_id, categories)
select cover_id, categories from seed
on conflict (cover_id) do update
  set categories = excluded.categories;

alter table public.live_cover_pool enable row level security;

drop policy if exists live_cover_pool_select_authenticated on public.live_cover_pool;
create policy live_cover_pool_select_authenticated
  on public.live_cover_pool for select
  to authenticated, anon
  using (true);

grant select on public.live_cover_pool to anon, authenticated;

-- Atribuição atómica (service_role ou seller dono da live).
create or replace function public.batata_assign_live_cover(p_live_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seller uuid;
  v_existing text;
  v_category text;
  v_cover text;
  v_avoid text[];
  v_uid uuid := auth.uid();
begin
  if p_live_id is null then
    raise exception 'live_id required';
  end if;

  select coalesce(seller_id, vendedor_id), cover_id
    into v_seller, v_existing
  from public.lives
  where id = p_live_id
  for update;

  if v_seller is null then
    raise exception 'live not found';
  end if;

  if v_existing is not null and length(trim(v_existing)) > 0 then
    return v_existing;
  end if;

  -- Seller próprio ou service_role (auth.uid null com service key).
  if v_uid is not null and v_uid is distinct from v_seller then
    raise exception 'not live owner';
  end if;

  -- Categoria com mais produtos publicados do vendedor.
  select p.category into v_category
  from public.products p
  where p.seller_id = v_seller
    and coalesce(p.list_on_marketplace, true) = true
    and coalesce(p.is_sold, false) = false
    and nullif(trim(coalesce(p.category, '')), '') is not null
  group by p.category
  order by count(*) desc, p.category asc
  limit 1;

  -- Evitar capas iguais às 3 lives mais recentes (activas ou ended recentes).
  select coalesce(array_agg(x.cover_id), '{}'::text[])
    into v_avoid
  from (
    select l.cover_id
    from public.lives l
    where l.cover_id is not null
      and l.id is distinct from p_live_id
    order by coalesce(l.went_live_at, l.created_at) desc nulls last
    limit 3
  ) x;

  -- Se o ciclo está completo, reinicia.
  if not exists (
    select 1 from public.live_cover_pool where cycle_used_at is null
  ) then
    update public.live_cover_pool set cycle_used_at = null, last_live_id = null;
  end if;

  -- 1) Preferir categoria + não usada + não em avoid
  select c.cover_id into v_cover
  from public.live_cover_pool c
  where c.cycle_used_at is null
    and (v_category is null or v_category = any (c.categories))
    and not (c.cover_id = any (v_avoid))
  order by random()
  for update skip locked
  limit 1;

  -- 2) Categoria sem avoid
  if v_cover is null and v_category is not null then
    select c.cover_id into v_cover
    from public.live_cover_pool c
    where c.cycle_used_at is null
      and v_category = any (c.categories)
    order by random()
    for update skip locked
    limit 1;
  end if;

  -- 3) Qualquer não usada, evitando vizinhos
  if v_cover is null then
    select c.cover_id into v_cover
    from public.live_cover_pool c
    where c.cycle_used_at is null
      and not (c.cover_id = any (v_avoid))
    order by random()
    for update skip locked
    limit 1;
  end if;

  -- 4) Qualquer não usada
  if v_cover is null then
    select c.cover_id into v_cover
    from public.live_cover_pool c
    where c.cycle_used_at is null
    order by random()
    for update skip locked
    limit 1;
  end if;

  -- 5) Reset ciclo e tenta de novo
  if v_cover is null then
    update public.live_cover_pool set cycle_used_at = null, last_live_id = null;
    select c.cover_id into v_cover
    from public.live_cover_pool c
    where not (c.cover_id = any (v_avoid))
    order by random()
    for update skip locked
    limit 1;
  end if;

  if v_cover is null then
    select c.cover_id into v_cover
    from public.live_cover_pool c
    order by random()
    for update skip locked
    limit 1;
  end if;

  if v_cover is null then
    raise exception 'no covers in pool';
  end if;

  update public.live_cover_pool
     set cycle_used_at = now(), last_live_id = p_live_id
   where cover_id = v_cover;

  update public.lives
     set cover_id = v_cover
   where id = p_live_id;

  return v_cover;
end;
$$;

revoke all on function public.batata_assign_live_cover(uuid) from public;
grant execute on function public.batata_assign_live_cover(uuid) to authenticated;
grant execute on function public.batata_assign_live_cover(uuid) to service_role;

-- Expor cover_id na view Hub (mantém regras de playback/VOD existentes).
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
  l.publish_backend,
  l.cover_id
from public.lives l
join public.hub_profiles_public hp
  on hp.id = coalesce(l.seller_id, l.vendedor_id)
where lower(trim(coalesce(l.status, ''))) in ('scheduled', 'live', 'ended');

grant select on public.hub_lives_public to anon, authenticated;

-- Discovery Hub (Home web): incluir cover_id.
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
      lower(trim(coalesce(l.status, ''))) = 'scheduled'
    )
    or (
      lower(trim(coalesce(l.status, ''))) = 'ended'
    )
  );

grant select on public.hub_lives_discovery_public to anon, authenticated;

commit;
