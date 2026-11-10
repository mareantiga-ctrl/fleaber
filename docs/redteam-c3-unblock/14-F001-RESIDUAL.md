# F-001 — residual (sem Stripe LIVE)

- PaymentIntent: montante cotado no **servidor**.
- Gate piloto LIVE: não usa `body.amount` (código snapshot).
- Residual: se `amount_paid_cents=0`, teto piloto pode usar `price_total` BD.
- **Stripe LIVE continua OFF** — sem pagamentos reais nesta ronda.
