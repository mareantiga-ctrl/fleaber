# FLEABER — RED TEAM CEGO R
## Auditor independente · CONNECT / PAYOUT / SAÍDA REAL · v1

> **Poço:** dinheiro que **sai** da plataforma — Connect, levantamento, clawback, refund residual, taxas.  
> Não re-auditar checkout Session clássico nem disputa O (salvo composição R→caixa).  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** — usar 4242, Connect test accounts, Transfer e Payout quando o finding exigir.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º seller · conluio.  
`service_role` **só** fixture / observação — **nunca** actor do exploit.

Prefixo fixtures: `RTR-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Consigo levantar, manter, ou duplicar dinheiro na carteira / Connect depois de venda, refund, disputa ou cancelamento?**

Prioridade: **payout race · clawback incompleto · refund Stripe vs wallet · release duplo · seller drain**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `PRODUCTION_GATE*`  
relatórios I/H/G/F · “o que já foi corrigido”.

**Podes estudar:** código · SQL · Edge `refund-order` · `payout-*` · wallet RPCs · schema LIVE.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar código. Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido parar só em:
wallet INSERT anon · preço Session body · oversell última unidade ·  
mint `devolvida` sem stripe (I-P0 clássico) · tip seller mismatch ·  
review 5★ release (sem variante).

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES R (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| R1 | Release → payout | Levantar tudo e ainda receber refund buyer? |
| R2 | Refund-order pós-release | Clawback completo? Seller net negativo impossível? |
| R3 | Partial dispute wallet | <100% deixa seller com mais do que devia? |
| R4 | Cancel ∥ release | Race cancelamento e libertação carteira |
| R5 | Connect onboarding | Open redirect / account takeover test mode |
| R6 | Payout idempotency | Duplo pedido de levantamento |
| R7 | MB WAY vs Seguro | Off-platform não contamina wallet plataforma |
| R8 | Composição R*→caixa | Venda → release → payout → disputa → refund |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥1 venda Stripe TEST até **release** (ou tentativa payout).  
2. Ledger fechado: buyer · seller · `wallet_transactions` · PI · refund.  
3. ≥1 race (`Future.wait`) envolvendo payout/refund/release.  
4. Tentar drenar seller **depois** de clawback conhecido.  
5. Não partir: refund-order legítimo pós-venda; payout com saldo real.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_r_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_R_CONNECT_PAYOUT_v1
VEREDICTO: FAIL_P0 | FAIL_P1 | … | PASS_CEGO_SATURADO | ATROFIA_ABORT
production_touched: false
fase4: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
