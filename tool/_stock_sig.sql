-- stock function signature
select pg_get_function_identity_arguments(oid) as args, proname
from pg_proc
where proname like '%live_item_stock%' or proname like '%batata_live_item%stock%';
