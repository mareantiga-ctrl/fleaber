-- Corrigir lives presas com badge LIVE na Home (status live + is_active true).
-- Idempotente: só afecta linhas claramente antigas.
-- Executar no SQL Editor do Supabase.

update public.lives
set
  status = 'ended',
  is_active = false
where lower(trim(coalesce(status, ''))) = 'live'
  and coalesce(is_active, false) = true
  and created_at < now() - interval '2 hours';

-- Opcional: ver o que ficou corrigido
-- select id, title, status, is_active, created_at, mux_vod_playback_id
-- from public.lives
-- where status = 'ended' and created_at > now() - interval '1 day'
-- order by created_at desc;
