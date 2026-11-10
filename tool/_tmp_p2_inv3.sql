select * from pg_policies where schemaname='public' and tablename in ('live_messages','live_raffle_winners','follows','favorites') order by tablename;
select table_name, grantee, privilege_type from information_schema.role_table_grants where table_schema='public' and table_name='notifications_view';
select column_name from information_schema.columns where table_schema='public' and table_name='live_messages' order by 1;
select column_name from information_schema.columns where table_schema='public' and table_name='live_raffle_winners' order by 1;
