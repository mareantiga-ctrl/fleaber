-- ZIP 144.2 — Edges (service_role) precisam ler fleaber_feature_flags.
-- RLS já tem SELECT para anon/authenticated; faltava GRANT ao role service_role.
grant select on table public.fleaber_feature_flags to service_role;
