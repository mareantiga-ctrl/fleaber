select pg_get_functiondef(oid) from pg_proc where proname like '%orders%live%coherence%' or proname like '%assert_live%' limit 5;
