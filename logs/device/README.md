# Logs da app Fleaber

Os erros são enviados automaticamente para **Supabase → tabela `app_logs`**.

Executa o SQL em `supabase/sql/app_logs_batata.sql` no painel Supabase.

Consulta no Table Editor ou SQL:

```sql
select created_at, category, error_message, device_info
from public.app_logs
order by created_at desc
limit 50;
```

Backup local opcional: `fleaber_app.log` na pasta Documents da app (sem cabo USB).
