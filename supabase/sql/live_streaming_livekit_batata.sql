-- Fleaber BATATA: colunas LiveKit (aditivas — não remove Mux nem altera layout da app).
-- Executar no SQL Editor do Supabase após live_streaming_mux_batata.sql.

alter table public.lives
  add column if not exists publish_backend text default 'mux_rtmp',
  add column if not exists livekit_room_name text,
  add column if not exists livekit_egress_id text;

comment on column public.lives.publish_backend is
  'mux_rtmp | livekit_mux | livekit_mux_landscape (WebRTC LiveKit + egress Mux)';

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.lives'::regclass
      and conname = 'lives_publish_backend_check'
  ) then
    alter table public.lives drop constraint lives_publish_backend_check;
  end if;
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
end;
$$;
