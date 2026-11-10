-- Fecha o alerta Supabase rls_disabled_in_public em public.batata_anon_rate_limits
-- BATATA: tabela interna de rate-limit (SEC-008/016). Só SECURITY DEFINER / service_role.
-- Igual a public.batata_rpc_rate_limits (já tinha RLS, esta ficou de fora).
-- Não cria policies para anon/authenticated — o cliente nunca deve ler/escrever aqui.

alter table public.batata_anon_rate_limits enable row level security;

revoke all on table public.batata_anon_rate_limits from public, anon, authenticated;

notify pgrst, 'reload schema';
