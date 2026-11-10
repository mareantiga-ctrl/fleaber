select column_name, is_nullable from information_schema.columns
where table_schema='public' and table_name='orders' and column_name in ('buyer_id','guest_session_id');
