-- Opcional: dados de pagamento do vendedor (reservas / MB WAY / IBAN).
-- Executar no SQL Editor do Supabase se as colunas ainda não existirem.

alter table public.profiles
  add column if not exists mb_way text,
  add column if not exists iban text;
