-- SEC-003b — Esconder stream keys: revoke SELECT na tabela + grant só colunas seguras
-- (REVOKE SELECT (col) sozinho não surtiu efeito no staging Supabase)

revoke select on table public.lives from authenticated;
revoke select on table public.lives from anon;

grant select (
  id,
  created_at,
  vendedor_id,
  playback_id,
  is_active,
  title,
  status,
  seller_id,
  mux_playback_id,
  publish_backend,
  livekit_room_name,
  mux_asset_id,
  mux_vod_playback_id,
  viewer_count,
  went_live_at,
  ended_at
) on table public.lives to authenticated, anon;

-- Colunas secretas NÃO concedidas: stream_key, mux_stream_key, mux_live_id, livekit_egress_id
-- Seller obtém stream_key via edge create-mux-live; edges usam service_role.

grant select on table public.lives to service_role;

notify pgrst, 'reload schema';
