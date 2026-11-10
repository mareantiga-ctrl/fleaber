-- Fleaber BATATA: cron horário para livekit-egress-cleanup (edge function).
-- Pré-requisitos (Dashboard → Edge Functions → Secrets):
--   LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (já usados pelo publisher)
--   LIVEKIT_EGRESS_CLEANUP_SECRET = mesmo valor guardado no Vault abaixo
--
-- Deploy da function (local):
--   npx supabase login
--   npx supabase functions deploy livekit-egress-cleanup --project-ref fxdknzrqjenzqcvnwqqq
--   npx supabase secrets set LIVEKIT_EGRESS_CLEANUP_SECRET=<segredo> --project-ref fxdknzrqjenzqcvnwqqq
--
-- 1) Gerar segredo (PowerShell): [guid]::NewGuid().ToString('N')
-- 2) Guardar no Vault (substituir YOUR_SECRET):
-- select vault.create_secret(
--   'YOUR_SECRET',
--   'livekit_egress_cleanup_secret',
--   'Auth cron → livekit-egress-cleanup'
-- );

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create or replace function public.batata_invoke_livekit_egress_cleanup()
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $batata_invoke_livekit_egress_cleanup$
declare
  v_secret text;
  v_request_id bigint;
  v_url text := 'https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/livekit-egress-cleanup';
begin
  select decrypted_secret
  into v_secret
  from vault.decrypted_secrets
  where name = 'livekit_egress_cleanup_secret'
  limit 1;

  if v_secret is null or v_secret = '' then
    raise warning 'batata_invoke_livekit_egress_cleanup: vault secret livekit_egress_cleanup_secret em falta';
    return null;
  end if;

  select net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cleanup-secret', v_secret
    ),
    body := '{}'::jsonb
  )
  into v_request_id;

  return v_request_id;
end;
$batata_invoke_livekit_egress_cleanup$;

comment on function public.batata_invoke_livekit_egress_cleanup() is
  'Invoca edge livekit-egress-cleanup. EXECUTE só service_role/cron (RT2035).';

revoke all on function public.batata_invoke_livekit_egress_cleanup()
  from public, anon, authenticated;
grant execute on function public.batata_invoke_livekit_egress_cleanup()
  to service_role;
do $cron_unschedule$
begin
  perform cron.unschedule('batata-livekit-egress-cleanup');
exception
  when others then
    null;
end;
$cron_unschedule$;

-- A cada hora, minuto 0 (UTC).
select cron.schedule(
  'batata-livekit-egress-cleanup',
  '0 * * * *',
  $$ select public.batata_invoke_livekit_egress_cleanup(); $$
);

-- Teste manual imediato (opcional):
-- select public.batata_invoke_livekit_egress_cleanup();
