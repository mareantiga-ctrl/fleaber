-- RT2035 Indep P1+P2 — GRANT drift (staging BATATA)
-- P1: batata_invoke_livekit_egress_cleanup executável por anon → DoS egress fleaber_*
-- P2: batata_backfill_handle_suggestions WRITE por anon (SQL fonte já service_role; LIVE drift)
-- production_touched: false · fase4: false

revoke all on function public.batata_invoke_livekit_egress_cleanup()
  from public, anon, authenticated;
grant execute on function public.batata_invoke_livekit_egress_cleanup()
  to service_role;

comment on function public.batata_invoke_livekit_egress_cleanup() is
  'RT2035: só service_role/cron. Anon/JWT não disparam stop de egress LiveKit.';

revoke all on function public.batata_backfill_handle_suggestions(boolean)
  from public, anon, authenticated;
grant execute on function public.batata_backfill_handle_suggestions(boolean)
  to service_role;

comment on function public.batata_backfill_handle_suggestions(boolean) is
  'RT2035: backfill handle_suggested só service_role (sem write anon).';

notify pgrst, 'reload schema';
