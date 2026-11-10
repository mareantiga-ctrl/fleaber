# FLEABER — RED TEAM CEGO L
## Auditor independente · CRON / AUTO-ESTADOS / RELEASE / TTL · v1

> Terceira onda: o que corre **sem o utilizador** (jobs, auto-feedback, expire, release).  
> Indep/F/G/H/I/J já batidos — tu vais a **tempo automático**.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não.  
Prefixo: `RTL-<timestamp>-`.  
`service_role` só fixture / observação / cleanup (cron legítimo pode ser service — o atacante é JWT/anon).

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Jobs e estados automáticos ainda me dão dinheiro, stock, feedback forjado ou libertação indevida?**

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR
--------------------------------------------------
Não ler HARDENING / freezes anteriores como roteiro.  
Não alterar código. Finding = provar → documentar → continuar.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Não Pass 1 em: dual Session, bag unlist, plain→JSON (J), mint pós-payout (I), cancel hold, Hub paused, pairing ended, offer morto, helper escalate.  
≥50% = essas → `ATROFIA_ABORT`.

--------------------------------------------------
LENTES L (≥4)
--------------------------------------------------
| # | Lente |
|---|--------|
| L1 | JWT chama cron (`auto_feedback`, `expire_offers`, expire hold) |
| L2 | Auto-feedback 48h: disparo cedo / duplo / sem `concluido` |
| L3 | Release wallet via cron vs review humana (após HIJ) |
| L4 | Hold TTL / offer TTL: expirar e ainda aceitar / pagar |
| L5 | Race humano ∥ cron (review, cancel, refund) |
| L6 | Soft-delete / completed_at / flags auto_feedback JWT |
| L7 | Composição L*→Δwallet ou stock |

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. ≥1 order Stripe TEST até `concluido` (mão OK).  
2. Tentar RPCs de job com JWT.  
3. ≥1 race `Future.wait` humano∥cron.  
4. Contabilidade wallets.  
5. Não partir confirmação mão legítima.

--------------------------------------------------
ENTREGA
--------------------------------------------------
`tool/redteam_blind_l_<timestamp>/FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_L_CRON_AUTO_v1
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos · esperado vs obtido · prova · severidade.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
