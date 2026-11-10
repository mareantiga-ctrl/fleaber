-- =============================================================================
-- BATATA 2026-10-11 — Hub Página 05: leitura pública de avaliações de sellers
-- publicados no FleaHub. Staging-first. Não altera reviews_gerais (chat interno).
--
-- Causa: hub_reviews_public lia reviews_gerais (security_invoker) → RLS
-- reviews_select_parties bloqueava anon (só buyer/target autenticados).
-- Fix: espelhar hub_products_public — ler `reviews` via security_barrier,
-- só sellers em hub_profiles_public, sem expor buyer_id.
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
  'Avaliações públicas de sellers com FleaHub publicado. Sem buyer_id. SELECT-only anon/auth.';

revoke all on public.hub_reviews_public from public;
revoke insert, update, delete, truncate, references, trigger
  on public.hub_reviews_public from anon, authenticated;
grant select on public.hub_reviews_public to anon, authenticated;
grant all on public.hub_reviews_public to service_role;

notify pgrst, 'reload schema';
