-- =============================================================================
-- BATATA 2026-10-11 — P05 correcção técnica final (staging only):
-- 1) Cursores oldest/lowest alinhados com ORDER BY (desempates mistos)
-- 2) Keyset real: WHERE cursor + ORDER BY + LIMIT (sem row_number sobre o conjunto)
-- 3) Índices de apoio às quatro ordenações
-- Não tocar produção neste passo.
-- =============================================================================

-- newest já coberto por reviews_hub_public_target_created_id_idx (migration anterior)

create index if not exists reviews_hub_public_target_created_asc_id_desc_idx
  on public.reviews (target_id, created_at asc, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

create index if not exists reviews_hub_public_target_stars_desc_created_id_idx
  on public.reviews (target_id, stars desc, created_at desc, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

create index if not exists reviews_hub_public_target_stars_asc_created_id_idx
  on public.reviews (target_id, stars asc, created_at desc, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

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
  v_fetch int;
  v_cnt int := 0;
begin
  if p_seller_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'missing_seller',
      'items', '[]'::jsonb,
      'has_more', false
    );
  end if;

  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_stars',
      'items', '[]'::jsonb,
      'has_more', false
    );
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

  -- Cursor incompleto → primeira página
  if p_cursor_id is not null
     and (
       p_cursor_created_at is null
       or (v_sort in ('highest', 'lowest') and p_cursor_stars is null)
     ) then
    p_cursor_id := null;
    p_cursor_created_at := null;
    p_cursor_stars := null;
  end if;

  v_fetch := v_limit + 1;

  /*
    Desempates (ORDER BY ≡ cursor):
      newest:  created_at DESC, id DESC
               cursor: (created_at, id) < cursor
      oldest:  created_at ASC,  id DESC
               cursor: created_at > c OR (created_at = c AND id < c_id)
      highest: stars DESC, created_at DESC, id DESC
               cursor: (stars, created_at, id) < cursor
      lowest:  stars ASC,  created_at DESC, id DESC
               cursor: stars > c
                    OR (stars = c AND created_at < c_at)
                    OR (stars = c AND created_at = c_at AND id < c_id)
  */

  if v_sort = 'newest' then
    with page as materialized (
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
      left join public.profiles p on p.id = r.buyer_id
      where r.target_id = p_seller_id
        and coalesce(r.target_type, 'seller') = any (
          array['seller'::text, 'vendedor'::text, 'profile'::text]
        )
        and (p_stars is null or r.stars = p_stars)
        and (
          p_cursor_id is null
          or (r.created_at, r.id) < (p_cursor_created_at, p_cursor_id)
        )
      order by r.created_at desc nulls last, r.id desc
      limit v_fetch
    )
    select
      count(*)::int,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', x.id,
              'target_id', x.target_id,
              'target_type', x.target_type,
              'stars', x.stars,
              'comment', x.comment,
              'created_at', x.created_at,
              'is_automatic', x.is_automatic,
              'author_display', x.author_display
            )
            order by x.created_at desc nulls last, x.id desc
          )
          from (
            select * from page
            order by created_at desc nulls last, id desc
            limit v_limit
          ) x
        ),
        '[]'::jsonb
      )
    into v_cnt, v_rows
    from page;

  elsif v_sort = 'oldest' then
    with page as materialized (
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
      left join public.profiles p on p.id = r.buyer_id
      where r.target_id = p_seller_id
        and coalesce(r.target_type, 'seller') = any (
          array['seller'::text, 'vendedor'::text, 'profile'::text]
        )
        and (p_stars is null or r.stars = p_stars)
        and (
          p_cursor_id is null
          or r.created_at > p_cursor_created_at
          or (r.created_at = p_cursor_created_at and r.id < p_cursor_id)
        )
      order by r.created_at asc nulls last, r.id desc
      limit v_fetch
    )
    select
      count(*)::int,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', x.id,
              'target_id', x.target_id,
              'target_type', x.target_type,
              'stars', x.stars,
              'comment', x.comment,
              'created_at', x.created_at,
              'is_automatic', x.is_automatic,
              'author_display', x.author_display
            )
            order by x.created_at asc nulls last, x.id desc
          )
          from (
            select * from page
            order by created_at asc nulls last, id desc
            limit v_limit
          ) x
        ),
        '[]'::jsonb
      )
    into v_cnt, v_rows
    from page;

  elsif v_sort = 'highest' then
    with page as materialized (
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
      left join public.profiles p on p.id = r.buyer_id
      where r.target_id = p_seller_id
        and coalesce(r.target_type, 'seller') = any (
          array['seller'::text, 'vendedor'::text, 'profile'::text]
        )
        and (p_stars is null or r.stars = p_stars)
        and (
          p_cursor_id is null
          or (r.stars, r.created_at, r.id)
            < (p_cursor_stars, p_cursor_created_at, p_cursor_id)
        )
      order by r.stars desc nulls last, r.created_at desc nulls last, r.id desc
      limit v_fetch
    )
    select
      count(*)::int,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', x.id,
              'target_id', x.target_id,
              'target_type', x.target_type,
              'stars', x.stars,
              'comment', x.comment,
              'created_at', x.created_at,
              'is_automatic', x.is_automatic,
              'author_display', x.author_display
            )
            order by x.stars desc nulls last, x.created_at desc nulls last, x.id desc
          )
          from (
            select * from page
            order by stars desc nulls last, created_at desc nulls last, id desc
            limit v_limit
          ) x
        ),
        '[]'::jsonb
      )
    into v_cnt, v_rows
    from page;

  else -- lowest
    with page as materialized (
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
      left join public.profiles p on p.id = r.buyer_id
      where r.target_id = p_seller_id
        and coalesce(r.target_type, 'seller') = any (
          array['seller'::text, 'vendedor'::text, 'profile'::text]
        )
        and (p_stars is null or r.stars = p_stars)
        and (
          p_cursor_id is null
          or r.stars > p_cursor_stars
          or (r.stars = p_cursor_stars and r.created_at < p_cursor_created_at)
          or (
            r.stars = p_cursor_stars
            and r.created_at = p_cursor_created_at
            and r.id < p_cursor_id
          )
        )
      order by r.stars asc nulls last, r.created_at desc nulls last, r.id desc
      limit v_fetch
    )
    select
      count(*)::int,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', x.id,
              'target_id', x.target_id,
              'target_type', x.target_type,
              'stars', x.stars,
              'comment', x.comment,
              'created_at', x.created_at,
              'is_automatic', x.is_automatic,
              'author_display', x.author_display
            )
            order by x.stars asc nulls last, x.created_at desc nulls last, x.id desc
          )
          from (
            select * from page
            order by stars asc nulls last, created_at desc nulls last, id desc
            limit v_limit
          ) x
        ),
        '[]'::jsonb
      )
    into v_cnt, v_rows
    from page;
  end if;

  v_has_more := coalesce(v_cnt, 0) > v_limit;

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

comment on function public.batata_hub_reviews_public_page(
  uuid, integer, integer, text, timestamptz, uuid, integer
) is
  'P05: keyset page Hub reviews. oldest/lowest cursors match mixed ASC/DESC ties.';

notify pgrst, 'reload schema';
