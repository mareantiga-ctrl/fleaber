-- Telefone verificado (opcional; usado após confirmação SMS no registo).
alter table public.profiles
  add column if not exists phone_verified_at timestamptz;
