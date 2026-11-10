select pg_get_constraintdef(oid)
from pg_constraint
where conname = 'live_reservation_requests_status_chk';
