-- Live Director Platform — marker migration (staging).
-- Aplicar manualmente no SQL Editor (ordem):
--   1. supabase/sql/live_director_batata.sql
--   2. supabase/sql/live_director_raffle_sim_batata.sql
--
-- NÃO aplicar em produção sem revisão.

select 1 as live_director_platform_migration_marker;
