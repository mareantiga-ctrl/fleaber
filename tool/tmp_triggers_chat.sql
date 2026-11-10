-- Triggers on orders / chat_messages
select tgname, relname, pg_get_triggerdef(t.oid) as def
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('orders', 'chat_messages', 'chats')
  and not t.tgisinternal
order by relname, tgname;
