# stripe-webhook (SEC-005 / ZIP 128)

## O que faz

1. **Checkout** — quando Stripe confirma `payment_status=paid`, chama o **mesmo** settle que o return URL GET (`create-payment-intent` / `create-live-tip-checkout`). O redirect da app **não foi removido**.
2. **Disputas** — `charge.dispute.created|updated|closed` → RPC `batata_apply_stripe_dispute_freeze` / `batata_release_stripe_dispute_freeze` (freeze **parcial** do valor contestado).

## Events (Dashboard Stripe — Sandbox / futuro Live)

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `charge.dispute.created`
- `charge.dispute.updated`
- `charge.dispute.closed`

## Deploy PROD

```powershell
powershell -File tool/deploy_edge_functions_safe.ps1 `
  -ProjectRef bpmpkzwnrbmuqnhgdscf `
  -Functions stripe-webhook
```

URL: `https://bpmpkzwnrbmuqnhgdscf.supabase.co/functions/v1/stripe-webhook`

## Anti-regressão

- Compra normal com return URL continua igual
- Emails E1–E3 (ZIP 123.10) não duplicados; disputa usa kind `stripe_dispute_opened`
- Sem cobrança a cartões guardados do vendedor
