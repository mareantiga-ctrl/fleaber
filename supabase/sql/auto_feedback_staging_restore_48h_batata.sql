-- Fleaber BATATA: repor feedback automático de STAGING para 48 horas.
--
-- Executar (projecto ligado):
--   npx supabase db query --linked -f supabase/sql/auto_feedback_batata.sql
--
-- Ou colar no SQL Editor do Supabase o conteúdo completo de auto_feedback_batata.sql
-- (este ficheiro é só documentação — a fonte de verdade é auto_feedback_batata.sql).

-- Confirmação pós-apply: a função deve conter interval '48 hours':
--   select pg_get_functiondef('public.batata_generate_auto_feedback'::regproc);
