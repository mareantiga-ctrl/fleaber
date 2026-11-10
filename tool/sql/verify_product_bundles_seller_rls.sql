-- Pós-aplicar product_bundles_seller_counter_rls_batata.sql no staging.
-- Esperado: 1 linha com policy product_bundles_insert_seller (cmd = INSERT).

select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'product_bundles'
  and policyname = 'product_bundles_insert_seller';
