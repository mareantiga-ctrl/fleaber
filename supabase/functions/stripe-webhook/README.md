# stripe-webhook (SEC-005)

## O que faz

Quando Stripe confirma `payment_status=paid`, esta edge chama o **mesmo** settle que o return URL GET (`create-payment-intent` ou `create-live-tip-checkout`).

O redirect da app **não foi removido** — o webhook é rede de segurança.

## Setup staging

1. Deploy:
   ```bash
   npx supabase functions deploy stripe-webhook --project-ref fxdknzrqjenzqcvnwqqq
   ```
2. No Stripe Dashboard (test) → Developers → Webhooks → Add endpoint:
   - URL: `https://fxdknzrqjenzqcvnwqqq.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`
3. Copiar o signing secret (`whsec_…`) e:
   ```bash
   npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_… --project-ref fxdknzrqjenzqcvnwqqq
   ```
4. QA: `APP-SEC-005` em `tool/SECURITY_QA_RETEST.md`

## Anti-regressão

- Compra normal com return URL continua igual
- Trigger de stock só decrementa na **mudança** para `pago` (re-settle seguro)
- Mensagens de chat de pagamento já evitam duplicados quando possível
