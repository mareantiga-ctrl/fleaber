-- =============================================================================
-- BATATA 2026-10-11 — P05: revogar escrita anon em public.reviews
-- SELECT já revogado em 20261011141000. Staging only neste passo.
-- =============================================================================

revoke insert, update, delete, truncate, references, trigger
  on table public.reviews from anon;

-- authenticated: manter só o necessário (SELECT via policy; INSERT/UPDATE/DELETE via policies)
-- Não alargar grants aqui.

notify pgrst, 'reload schema';
