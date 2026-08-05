-- Forçar revoke colunas stream key (SEC-003)
revoke select (mux_stream_key, stream_key) on table public.lives from authenticated;
revoke select (mux_stream_key, stream_key) on table public.lives from anon;

notify pgrst, 'reload schema';
