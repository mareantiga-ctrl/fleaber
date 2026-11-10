-- Fix AMB-09: app grava publish_backend=livekit_mux_landscape mas o CHECK
-- só permitia mux_rtmp | livekit_mux → erro vermelho no topo do studio.
-- Executar no SQL Editor staging (e prod quando aplicável).

alter table public.lives
  drop constraint if exists lives_publish_backend_check;

alter table public.lives
  add constraint lives_publish_backend_check
  check (
    publish_backend is null
    or publish_backend in (
      'mux_rtmp',
      'livekit_mux',
      'livekit_mux_landscape'
    )
  );

comment on column public.lives.publish_backend is
  'mux_rtmp | livekit_mux | livekit_mux_landscape (WebRTC LiveKit + egress Mux)';
