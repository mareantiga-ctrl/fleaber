-- SEC-029 OBSERVE ONLY — não altera dados, RLS, nem RPCs.
-- Corre no SQL Editor (staging) para ver divergências seller_id vs vendedor_id.
-- BATATA: zero risco de regressão; só diagnóstico antes de qualquer normalização futura.

-- 1) Lives com as duas colunas preenchidas e diferentes
select
  id,
  seller_id,
  vendedor_id,
  status,
  created_at
from public.lives
where seller_id is not null
  and vendedor_id is not null
  and seller_id is distinct from vendedor_id
order by created_at desc
limit 100;

-- 2) Contagens (resumo)
select
  count(*) filter (
    where seller_id is not null and vendedor_id is not null
      and seller_id is distinct from vendedor_id
  ) as both_set_mismatch,
  count(*) filter (
    where seller_id is null and vendedor_id is not null
  ) as only_vendedor_id,
  count(*) filter (
    where seller_id is not null and vendedor_id is null
  ) as only_seller_id,
  count(*) filter (
    where seller_id is not null and vendedor_id is not null
      and seller_id = vendedor_id
  ) as both_set_match,
  count(*) as total_lives
from public.lives;
