-- Activar/desactivar pagamentos fora da app (MB Way / IBAN).

alter table public.profiles
  add column if not exists external_payments_enabled boolean not null default false;

comment on column public.profiles.external_payments_enabled is
  'Se true, o vendedor aceita MB Way / transferência fora da app no checkout.';
