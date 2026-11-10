-- =============================================================================
-- BATATA 2026-10-11 — Página 05 validação final:
-- 1) Endurecer hub_reviews_public (SELECT-only, sem buyer_id, só Hub publicado)
-- 2) Stats globais (security definer, mesmos critérios da lista)
-- 3) Página keyset (limit 10) com filtro estrelas + ordenação estável
-- Staging only via apply controlado. Não tocar produção neste passo.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- View pública (reafirma contrato)
-- ---------------------------------------------------------------------------
create or replace view public.hub_reviews_public
with (security_barrier = true, security_invoker = false)
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
    when coalesce(r.is_automatic, false) then 'Avaliação automática'::text
    when nullif(trim(both from p.full_name), '') is not null
      then left(split_part(trim(both from p.full_name), ' ', 1), 24)
    else 'Compradora verificada'::text
  end as author_display
from public.reviews r
join public.hub_profiles_public hp on hp.id = r.target_id
left join public.profiles p on p.id = r.buyer_id
where coalesce(r.target_type, 'seller') = any (
  array['seller'::text, 'vendedor'::text, 'profile'::text]
);

comment on view public.hub_reviews_public is
  'P05: avaliações públicas de sellers Hub publicados. Sem buyer_id. SELECT-only.';

revoke all on public.hub_reviews_public from public;
revoke insert, update, delete, truncate, references, trigger
  on public.hub_reviews_public from anon, authenticated;
grant select on public.hub_reviews_public to anon, authenticated;
grant all on public.hub_reviews_public to service_role;

-- Index for keyset pagination (eligible seller reviews)
create index if not exists reviews_hub_public_target_created_id_idx
  on public.reviews (target_id, created_at desc, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

-- ---------------------------------------------------------------------------
-- Stats (full set, same eligibility as list)
-- ---------------------------------------------------------------------------
create or replace function public.batata_hub_reviews_public_stats(
  p_seller_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count bigint := 0;
  v_avg numeric := 0;
  v_d5 int := 0;
  v_d4 int := 0;
  v_d3 int := 0;
  v_d2 int := 0;
  v_d1 int := 0;
begin
  if p_seller_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'missing_seller',
      'count', 0,
      'average', 0,
      'distribution', jsonb_build_object('5',0,'4',0,'3',0,'2',0,'1',0)
    );
  end if;

  -- Seller must be Hub-published (same gate as view join)
  if not exists (
    select 1 from public.hub_profiles_public hp where hp.id = p_seller_id
  ) then
    return jsonb_build_object(
      'ok', true,
      'count', 0,
      'average', 0,
      'distribution', jsonb_build_object('5',0,'4',0,'3',0,'2',0,'1',0),
      'published', false
    );
  end if;

  select
    count(*)::bigint,
    coalesce(avg(r.stars)::numeric, 0),
    count(*) filter (where r.stars = 5)::int,
    count(*) filter (where r.stars = 4)::int,
    count(*) filter (where r.stars = 3)::int,
    count(*) filter (where r.stars = 2)::int,
    count(*) filter (where r.stars = 1)::int
  into v_count, v_avg, v_d5, v_d4, v_d3, v_d2, v_d1
  from public.reviews r
  where r.target_id = p_seller_id
    and coalesce(r.target_type, 'seller') = any (
      array['seller'::text, 'vendedor'::text, 'profile'::text]
    );

  return jsonb_build_object(
    'ok', true,
    'count', v_count,
    'average', round(v_avg, 2),
    'distribution', jsonb_build_object(
      '5', v_d5,
      '4', v_d4,
      '3', v_d3,
      '2', v_d2,
      '1', v_d1
    ),
    'published', true
  );
end;
$$;

revoke all on function public.batata_hub_reviews_public_stats(uuid) from public;
grant execute on function public.batata_hub_reviews_public_stats(uuid)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Page (keyset) — never returns buyer_id
-- p_sort: newest | oldest | highest | lowest
-- p_stars: null = all, else 1..5
-- ---------------------------------------------------------------------------
create or replace function public.batata_hub_reviews_public_page(
  p_seller_id uuid,
  p_limit integer default 10,
  p_stars integer default null,
  p_sort text default 'newest',
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_cursor_stars integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 10), 1), 50);
  v_sort text := lower(trim(coalesce(p_sort, 'newest')));
  v_rows jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_cnt int := 0;
begin
  if p_seller_id is null then
    return jsonb_build_object('ok', false, 'error', 'missing_seller', 'items', '[]'::jsonb);
  end if;

  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    return jsonb_build_object('ok', false, 'error', 'invalid_stars', 'items', '[]'::jsonb);
  end if;

  if v_sort not in ('newest', 'oldest', 'highest', 'lowest') then
    v_sort := 'newest';
  end if;

  if not exists (
    select 1 from public.hub_profiles_public hp where hp.id = p_seller_id
  ) then
    return jsonb_build_object(
      'ok', true,
      'items', '[]'::jsonb,
      'has_more', false,
      'published', false
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.ord), '[]'::jsonb), count(*)::int
  into v_rows, v_cnt
  from (
    select
      jsonb_build_object(
        'id', q.id,
        'target_id', q.target_id,
        'target_type', q.target_type,
        'stars', q.stars,
        'comment', q.comment,
        'created_at', q.created_at,
        'is_automatic', q.is_automatic,
        'author_display', q.author_display
      ) as item,
      q.ord
    from (
      select
        r.id,
        r.target_id,
        r.target_type,
        r.stars,
        r.comment,
        r.created_at,
        coalesce(r.is_automatic, false) as is_automatic,
        case
          when coalesce(r.is_automatic, false) then 'Avaliação automática'::text
          when nullif(trim(both from p.full_name), '') is not null
            then left(split_part(trim(both from p.full_name), ' ', 1), 24)
          else 'Compradora verificada'::text
        end as author_display,
        row_number() over (
          order by
            case when v_sort = 'newest' then r.created_at end desc nulls last,
            case when v_sort = 'oldest' then r.created_at end asc nulls last,
            case when v_sort = 'highest' then r.stars end desc nulls last,
            case when v_sort = 'lowest' then r.stars end asc nulls last,
            case when v_sort in ('highest', 'lowest') then r.created_at end desc nulls last,
            r.id desc
        ) as ord
      from public.reviews r
      left join public.profiles p on p.id = r.buyer_id
      where r.target_id = p_seller_id
        and coalesce(r.target_type, 'seller') = any (
          array['seller'::text, 'vendedor'::text, 'profile'::text]
        )
        and (p_stars is null or r.stars = p_stars)
        and (
          p_cursor_id is null
          or (
            v_sort = 'newest'
            and (r.created_at, r.id) < (p_cursor_created_at, p_cursor_id)
          )
          or (
            v_sort = 'oldest'
            and (r.created_at, r.id) > (p_cursor_created_at, p_cursor_id)
          )
          or (
            v_sort = 'highest'
            and p_cursor_stars is not null
            and (r.stars, r.created_at, r.id)
              < (p_cursor_stars, p_cursor_created_at, p_cursor_id)
          )
          or (
            v_sort = 'lowest'
            and p_cursor_stars is not null
            and (r.stars, r.created_at, r.id)
              > (p_cursor_stars, p_cursor_created_at, p_cursor_id)
          )
        )
    ) q
    where q.ord <= v_limit + 1
  ) x;

  v_has_more := coalesce(v_cnt, 0) > v_limit;

  if v_has_more then
    select coalesce(jsonb_agg(elem order by ord), '[]'::jsonb)
    into v_rows
    from jsonb_array_elements(coalesce(v_rows, '[]'::jsonb))
      with ordinality as t(elem, ord)
    where ord <= v_limit;
  end if;

  return jsonb_build_object(
    'ok', true,
    'items', coalesce(v_rows, '[]'::jsonb),
    'has_more', v_has_more,
    'published', true,
    'sort', v_sort,
    'stars_filter', p_stars,
    'limit', v_limit
  );
end;
$$;

revoke all on function public.batata_hub_reviews_public_page(
  uuid, integer, integer, text, timestamptz, uuid, integer
) from public;
grant execute on function public.batata_hub_reviews_public_page(
  uuid, integer, integer, text, timestamptz, uuid, integer
) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
