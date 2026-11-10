-- Fleaber BATATA: limpeza única de livekit_egress_id em lives já terminadas.
-- Executar no SQL Editor do Supabase (Dashboard → SQL → New query).
-- Seguro se não houver egress activos no LiveKit Cloud (ver scripts/check_livekit_egress.ts).

update public.lives
set livekit_egress_id = null
where status = 'ended'
  and livekit_egress_id is not null;

-- Verificar quantas ficaram limpas:
select
  count(*) filter (where livekit_egress_id is not null) as lives_com_egress_id,
  count(*) filter (where status = 'ended' and livekit_egress_id is not null) as ended_com_egress_id
from public.lives;
