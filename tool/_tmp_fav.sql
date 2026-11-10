select policyname, cmd, roles::text, qual from pg_policies where tablename='favorites';
