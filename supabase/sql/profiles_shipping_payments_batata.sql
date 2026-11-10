-- Morada de envio + pagamentos opcionais (MB Way / IBAN) em profiles.
-- Correr no SQL Editor Supabase.
-- Se guardar falhar com PGRST116, correr também profiles_rls_batata.sql.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS shipping_line1 text,
  ADD COLUMN IF NOT EXISTS shipping_line2 text,
  ADD COLUMN IF NOT EXISTS shipping_postal_code text,
  ADD COLUMN IF NOT EXISTS shipping_city text,
  ADD COLUMN IF NOT EXISTS shipping_country text DEFAULT 'PT',
  ADD COLUMN IF NOT EXISTS mb_way text,
  ADD COLUMN IF NOT EXISTS iban text;

COMMENT ON COLUMN public.profiles.shipping_line1 IS 'Morada — rua e número';
COMMENT ON COLUMN public.profiles.shipping_line2 IS 'Morada — andar / bloco (opcional)';
COMMENT ON COLUMN public.profiles.shipping_postal_code IS 'Código postal';
COMMENT ON COLUMN public.profiles.shipping_city IS 'Localidade';
COMMENT ON COLUMN public.profiles.shipping_country IS 'País (ISO2, ex. PT)';
COMMENT ON COLUMN public.profiles.mb_way IS 'MB Way opcional — pagamentos fora da app';
COMMENT ON COLUMN public.profiles.iban IS 'IBAN opcional — pagamentos fora da app';
