select pg_get_functiondef(oid) as def
from pg_proc
where proname = 'batata_ingest_ocr_reservation_v2'
limit 1;
