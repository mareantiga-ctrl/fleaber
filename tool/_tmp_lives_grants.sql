-- Query current lives column grants for anon
select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_schema='public' and table_name='lives'
  and grantee in ('anon','authenticated','public')
  and column_name like 'mux%'
order by 1,3;
