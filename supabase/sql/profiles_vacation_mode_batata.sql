-- Modo de férias do vendedor: oculta anúncios/diretos no marketplace; bloqueia compras novas.
-- Executar também profiles_rls_batata.sql se UPDATE devolver PGRST116.
alter table public.profiles
  add column if not exists vacation_mode boolean not null default false;

comment on column public.profiles.vacation_mode is
  'true = vendedor de férias; sem compras novas; feed marketplace oculto';

notify pgrst, 'reload schema';
