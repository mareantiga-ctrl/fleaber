-- Nome legal completo (etiquetas, pagamentos, dados bancários).
-- `full_name` mantém-se como nome de utilizador visível na app.
-- Correr no SQL Editor Supabase.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS legal_full_name text;

COMMENT ON COLUMN public.profiles.full_name IS
  'Nome de utilizador na app (chat, perfil público, directos).';
COMMENT ON COLUMN public.profiles.legal_full_name IS
  'Nome legal completo (CC) — envio, etiquetas, pagamentos, dados bancários.';
