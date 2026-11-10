# F-001 — create-payment-intent (tamper de montante)

**Data:** 2026-11-10 · C1 ZIP 190.1  
**Código examinado:** `supabase/functions/create-payment-intent/index.ts` (working tree actual)

## Veredicto

| Caminho | Usa `body.amount` para cobrar? | Resultado |
|---------|--------------------------------|-----------|
| Criação Checkout Session / PI (fluxo principal) | **Não** | Montante = `resolveServerCheckoutQuote(...).amountCents` (ORDER → preço BD / attempt selado / bundle selado) |
| Divergência cliente vs servidor | Só log `sec_fase1_client_amount_ignored` se \|Δ\| > 200¢ | Cliente **ignorado** |
| Stripe `unit_amount` | `amount` servidor | PASS |
| Gate piloto LIVE (`assertStripeLivePilotCheckout`) | **Antes:** podia usar `body.amount` se `amount_paid_cents` vazio | **FAIL parcial (policy)** — corrigido no working tree |

## Conclusão

A falha reportada pelo C3 (**«servidor aceita valores do cliente sem recalcular»** no cobro) **não se confirma** no fluxo principal actual: o total oficial é recalculado/selado no servidor.

Existia um risco **secundário** no gate do piloto LIVE: um `body.amount` baixo podia passar o teto `max_total_cents` e o PI ainda assim cobrar o total servidor (acima do teto). Correção: gate usa apenas `amount_paid_cents` ou `price_total` da encomenda.

## Deploy

Correcção está no snapshot C3. **Deploy Edge PROD** só com GO explícito (não feito nesta ronda).
