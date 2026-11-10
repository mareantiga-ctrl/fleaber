-- Allow Face extension channel on LRR (alongside ocr|manual|graph|helper)
alter table public.live_reservation_requests
  drop constraint if exists live_reservation_requests_ingest_channel_chk;

alter table public.live_reservation_requests
  add constraint live_reservation_requests_ingest_channel_chk
  check (
    ingest_channel is null
    or ingest_channel = any (
      array['ocr', 'manual', 'graph', 'helper', 'extension']::text[]
    )
  );

notify pgrst, 'reload schema';
