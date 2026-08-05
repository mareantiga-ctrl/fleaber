-- SEC-007 fase 1a — BATATA (risco mínimo)
-- Remove SELECT **anon** em public.profiles (dump PII / IBAN / MB WAY / morada sem login).
--
-- NÃO altera:
--   - profiles_select_auth (authenticated USING true) — app Flutter intacta
--   - INSERT/UPDATE own
--   - hub_profiles_public (vitrine Hub sem PII financeira)
--
-- Residual (fase futura, risco alto): restringir SELECT authenticated a próprio + campos públicos.
-- Correr tu no SQL Editor staging. Idempotente.

drop policy if exists "profiles_select_anon" on public.profiles;

-- Reforço: se existir grant de tabela a anon, revogar SELECT (views públicas mantêm grants próprios).
do $$
begin
  revoke select on table public.profiles from anon;
exception
  when undefined_object then null;
  when others then
    raise notice 'SEC-007 revoke anon select skipped: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

-- Diagnóstico (só leitura) — deve devolver 0 policies anon SELECT em profiles:
-- select polname, polroles::regrole[]
-- from pg_policy
-- where polrelid = 'public.profiles'::regclass;
