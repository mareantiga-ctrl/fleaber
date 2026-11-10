-- Stripe IDs + refund tracking on orders (Seguro Fleaber cancel → auto refund).

alter table if exists public.orders
  add column if not exists stripe_checkout_session_id text,
  add column if not exists stripe_payment_intent_id text,
  add column if not exists stripe_refund_id text,
  add column if not exists stripe_refunded_at timestamptz;

create index if not exists orders_stripe_session_idx
  on public.orders (stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create index if not exists orders_stripe_pi_idx
  on public.orders (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

comment on column public.orders.stripe_checkout_session_id is
  'Checkout Session id gravado no settle do Seguro Fleaber';
comment on column public.orders.stripe_payment_intent_id is
  'PaymentIntent id para refunds Stripe';
comment on column public.orders.stripe_refund_id is
  'Último refund Stripe desta encomenda (idempotência)';
comment on column public.orders.stripe_refunded_at is
  'Quando o refund Stripe foi registado na BD';
