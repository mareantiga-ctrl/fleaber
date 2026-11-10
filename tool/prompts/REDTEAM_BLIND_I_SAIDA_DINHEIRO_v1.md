# FLEABER — RED TEAM CEGO I
## Auditor independente · DINHEIRO A SAIR / CONNECT / PAYOUT · v1

> **Terceira onda** — caixa de entrada já muito batida; tu vais ao **saída de dinheiro**.  
> Connect, Transfer, payout, wallet debit, clawback, refund residual.  
> Mesmas regras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, não corrigir.

--------------------------------------------------
AMBIENTE
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Session + pagar 4242 quando preciso).  
Produção proibida · Fase 4 não.  
Prefixo: `RTI-<timestamp>-` (não confundir com Indep RTI4).  
`service_role` só fixture / observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **O dinheiro que já está (ou parece estar) na carteira / Connect — consigo tirá-lo duas vezes, para a conta errada, ou sem direito?**

Não re-provar: dual Session hold, offer amount, tip mint sem seller, invite enum, Hub discovery.

Prioridade: **Δwallet líquido · Transfer · payout · clawback · refund após release**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 em: dual Session, bag unlist, cancel hold, review 5★ release (já fechados).  
≥50% = essas classes → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES I (≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| I1 | Payout / `wallet_payout_debit` JWT ou Edge hostil |
| I2 | Connect return_url / onboarding hijack → conta errada |
| I3 | Release + refund + clawback = dinheiro líquido |
| I4 | Transfer duplicado / replay webhook payout |
| I5 | Seller refund após já ter release |
| I6 | Buyer força reembolso alheio / parcial residual |
| I7 | Composição I* até Stripe net ou wallet Δ |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 fluxo Stripe TEST **pago** + caminho até release ou refund.  
2. Contabilidade fechada: buyer wallet · seller wallet · Stripe.  
3. Tentar JWT em RPCs de payout / Transfer.  
4. Flutter ≠ fronteira.

--------------------------------------------------
ENTREGA
--------------------------------------------------
`tool/redteam_blind_i_<timestamp>/FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_I_SAIDA_DINHEIRO_v1
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
production_touched: false
fase4: false
corrections_applied: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
