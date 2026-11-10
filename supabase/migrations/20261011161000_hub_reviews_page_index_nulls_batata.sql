-- =============================================================================
-- BATATA 2026-10-11 — P05: índices com NULLS LAST alinhados ao ORDER BY
-- (DESC default é NULLS FIRST → mismatch forçava scan completo + top-N sort)
-- Staging only.
-- =============================================================================

drop index if exists public.reviews_hub_public_target_created_id_idx;
drop index if exists public.reviews_hub_public_target_created_asc_id_desc_idx;
drop index if exists public.reviews_hub_public_target_stars_desc_created_id_idx;
drop index if exists public.reviews_hub_public_target_stars_asc_created_id_idx;

create index reviews_hub_public_target_created_id_idx
  on public.reviews (target_id, created_at desc nulls last, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

create index reviews_hub_public_target_created_asc_id_desc_idx
  on public.reviews (target_id, created_at asc nulls last, id desc)
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

create index reviews_hub_public_target_stars_desc_created_id_idx
  on public.reviews (
    target_id,
    stars desc nulls last,
    created_at desc nulls last,
    id desc
  )
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

create index reviews_hub_public_target_stars_asc_created_id_idx
  on public.reviews (
    target_id,
    stars asc nulls last,
    created_at desc nulls last,
    id desc
  )
  where coalesce(target_type, 'seller') = any (
    array['seller'::text, 'vendedor'::text, 'profile'::text]
  );

analyze public.reviews;

notify pgrst, 'reload schema';
