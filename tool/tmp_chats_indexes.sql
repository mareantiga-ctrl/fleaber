select indexname, indexdef
from pg_indexes
where tablename = 'chats' and schemaname = 'public';
