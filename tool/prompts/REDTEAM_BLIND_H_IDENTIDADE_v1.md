# FLEABER — RED TEAM CEGO H
## Auditor independente · IDENTIDADE / STAFF / MULTI-CONTA · v1

> **Terceira onda** depois de Indep v4, F, G, E, D (já frescos / saturados).  
> **Poço:** quem age em nome de quem — helper, device, JWT velho, 2ª conta, hijack suave.  
> Mesmas regras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, não corrigir.

--------------------------------------------------
AMBIENTE
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não.  
Actors: anon · buyer · seller · 2.º buyer · 2.º seller · helper · conluio.  
`service_role` só fixture / evidência / cleanup.  
Prefixo fixtures: `RTH-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Consigo actuar como outra pessoa (ou como staff com permissão a mais) e disso tirar dinheiro, stock, autoridade ou dados?**

Não re-provar: dual Session, bag unlist, tip seller mismatch, invite enum, cancel hold, review release, Hub paused, pairing ended, offer morto (fechados).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Se ≥50% findings = classes fechadas acima → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES H (≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| H1 | Helper escalate / perm mínima implica Y |
| H2 | Device token / pairing após kick ou troca de seller |
| H3 | 2.ª conta (buyer2) hijack order/chat/review/dispute |
| H4 | JWT de conta A após switch loja / logout parcial |
| H5 | Staff cria live/rifa/refund na loja alheia |
| H6 | Edge confia `buyer_id` / `seller_id` do body |
| H7 | Composição H*→caixa (hold, Session, refund) |

--------------------------------------------------
ENTREGA
--------------------------------------------------
`tool/redteam_blind_h_<timestamp>/FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_H_IDENTIDADE_v1
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
production_touched: false
fase4: false
corrections_applied: false
```

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
