-- SEC-007: drop policies legadas FlutterFlow que reabrem SELECT (OR com own-row)
drop policy if exists "Permitir leitura" on public.profiles;
drop policy if exists "Enable read access for all users" on public.profiles;
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
drop policy if exists "Public profiles are viewable by everyone." on public.profiles;

notify pgrst, 'reload schema';
