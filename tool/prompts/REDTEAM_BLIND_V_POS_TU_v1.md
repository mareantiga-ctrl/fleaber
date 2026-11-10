# FLEABER — RED TEAM CEGO V
## Auditor independente · PÓS-FECHO T0850 / U0855 · REFUTAR · v1

> Acabámos de fechar: **não reabrir `pago`**, **oferta qty=1**, **saco de conjunto completo**, Hub qty>0, stock floor.  
> **Poço:** provar que estes fechos **não** seguram — ou saturar.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTV-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Depois dos fechos T0850/U0855, ainda consigo dinheiro (carteira ou Stripe), stock, ou pagar menos no marketplace / disputa?**

Prioridade: variantes **novas** (não o PATCH `entregue→pago` exacto sem twist).

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `PRODUCTION_GATE*` · relatórios Q/T/U/R/S.

**Podes estudar:** código · SQL · RLS · Edge · schema LIVE.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a parar só em:
`entregue→pago` exact · `offer_quantity_must_be_one` exact sem variante ·  
bag incompleto exact · Hub qty=0 exact · dual Session single · bag unlist ·  
spoof `seller_id` · live_item mismatch exact · devolvida sem stripe · parcial 100% exact.

Se ≥50% = lista acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES V (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| V1 | FSM regressão | Outro caminho para `pago` pós-envio? `concluido`→`pago`? aliases? |
| V2 | Disputa×refund | Wallet + Stripe residual; race partial∥refund; clawback |
| V3 | Oferta qty | Bundle+oferta; 2 orders na mesma oferta; qty via UPDATE |
| V4 | Conjunto | Subset por outro `bundle_id`; total_eur vs lines; 2 conjuntos |
| V5 | Stock | Inflate live_only; decrease; restore devolvida |
| V6 | Race | `Future.wait` verbos ≠ T/U |
| V7 | 2.º actor | B2/S2 no mesmo order/bundle |
| V8 | Composição → caixa | Encadear até Δwallet / Stripe net / stock |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 Stripe TEST pago + disputa **ou** checkout marketplace.  
2. Contabilidade: wallets · PI · `stripe_refund_id` · stock.  
3. ≥1 race real.  
4. REST/RPC/Edge ≠ Flutter.  
5. Não partir: compra single; envio; `refund-order` em `pago` **antes** de enviar; MB WAY seller `pago`.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
Pasta: `tool/redteam_blind_v_<timestamp>/` · **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_V_POS_TU_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [V1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
