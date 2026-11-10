-- Playback do asset VOD Mux (gravação após terminar o direto).
alter table public.lives
  add column if not exists mux_asset_id text,
  add column if not exists mux_vod_playback_id text;

comment on column public.lives.mux_vod_playback_id is
  'Playback ID do asset gravado (VOD); usar quando status=ended';
