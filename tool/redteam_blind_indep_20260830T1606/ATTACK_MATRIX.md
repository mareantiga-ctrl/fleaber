# Matriz de ataques — RTI1606 (congelada)

FROZEN_AT: `2026-08-30T15:32:00Z`

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA |
|------------|--------|------------|-----------|---------|------------|-----------|
| ORDERS PATCH | status/preço/qty/PI/`amount_paid` | buyer JWT | 200 eco; sem persistência | nenhum financeiro | P3 | pass1 |
| ORDERS INSERT | preço 0,50 / qty 99 / buyer alheio | buyer JWT | selo catálogo / hold / attribution denied | nenhum | — | pass1–2 |
| CHECKOUT Edge | `amount=50`; checkout alheio | buyer / helper / seller | servidor 2060; bloqueio alheio | nenhum | — | pass2 |
| CHECKOUT × race | 2 Sessions paralelas + 2 pagamentos TEST | buyer + Stripe TEST | 2 capturas; PI B reembolsada; 1 venda | janela + taxas refund | **P2** | pass3b + 4242 |
| STOCK | 10 INSERT stock=1 | buyer + helper | 1 hold | nenhum | — | pass2 |
| WALLET | INSERT saldo; RPCs privilegiados | buyer JWT | 403 / denied | nenhum | — | pass1 |
| PAYOUT | mesma vs distinta idempotency key | seller JWT | 1 Transfer vs 2 Transfers | I/J mantidos | — | pass2 |
| REFUND | buyer + 6× seller paralelo | buyer / seller | buyer 403; 1 refund Stripe | nenhum extra | — | pass3c |
| OFFERS | self-accept; mutar amount | buyer / seller | denied; contrato 5,00 € | nenhum | — | pass2 |
| REVIEWS | sem order / alheio / duplicado | buyer / helper | erros / 409 | nenhum | — | pass2 |
| MB WAY FSM | seller pago; buyer concluido; review | seller → buyer | wallets iguais; sem release | F mantido | — | pass2 |
| CATÁLOGO × checkout | baixar preço após selo | seller → buyer | checkout ~2165 cêntimos | K mantido | — | pass3 |
| TIPS | self / seller errado / 1 € | buyer JWT | rejeitado / débito correcto | nenhum abuso | — | pass3 |
| CHAT / STORAGE | inject/list alheio | helper JWT | bloqueado | nenhum | — | pass2–3 |
| PS pairing | pairing em live alheia | helper fresco | `not_allowed` | nenhum | — | pass3 |
| RPC email | `batata_find_user_id_by_email` | helper fresco | UUID do seller | enumeração | **P3** | pass2 |
| WEBHOOK | sem assinatura; e2e JWT | anon / buyer | 400 / 401 | nenhum | — | pass1 |
| MUX | criar live | buyer JWT | 403 | nenhum | — | pass1 |

## Tabela de findings

| ID | SEVERIDADE | TÍTULO | ACTOR | PRÉ-CONDIÇÕES | REPRODUÇÃO | IMPACTO | ESTADO |
|----|------------|--------|-------|---------------|------------|---------|--------|
| RTI1606-P2-01 | P2 | Sessões Checkout paralelas na mesma order | buyer JWT | order `reserva_pendente` | 2× `create-payment-intent` em paralelo; pagar ambas TEST | 2.ª PI reembolsada no settle; não é 2.ª venda líquida | OPEN |
| RTI1606-P3-01 | P3 | Oracle email→UUID | helper JWT | email registado | `batata_find_user_id_by_email` | enumeração de contas | OPEN |
| RTI1606-P3-02 | P3 | PATCH financeiro 200 sem persistir | buyer/seller JWT | order visível | PATCH campos de captura | confusão de cliente | OPEN |
