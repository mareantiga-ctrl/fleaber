# FLEABER — RED TEAM CEGO EM · RETESTE · POS_OPEN_GATE
## Saco + tentar pagar — **quota ≥12**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Se ainda houver 2 `cs_` open → tentar pagar as duas (caça P0).  
> Esperado pós-fail-closed: ≤1 create; overlap = 400.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEM-<timestamp>-` · pasta `tool/redteam_blind_em_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**12**.
2. **≥3** overlaps (6∥4, expand, bag∥single).
3. Se 2 `cs_` open: **obrigatório** pagar ambas 4242 → 2 capturas = **P0**.
4. Se ≤1 `cs_`: pagar essa + documentar 2.º 400; **1×** happy bag pago.
5. **≥3 classe_nova** · **≥3 races**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Sem dinheiro irreversível no overlap. Preferir nunca 2 open.

--------------------------------------------------
## MATRIZ (≥12)
--------------------------------------------------

### EM-A Gerar (≥4)
A1 6∥4 t=0 — count `cs_` + HTTP  
A2 expand subset→superset  
A3 bag∥single  
A4 2× idêntico → 1 `cs_`

### EM-B Pagar (≥4)
B1 se 2 open: pagar 1.ª 4242  
B2 pagar 2.ª 4242  
B3 stock/Hub/orders após  
B4 se 1 open: pagar + settle do 400-path

### EM-C Caixa (≥4)
C1 wallet Δ  
C2 happy bag único pago  
C3 leftover Hub  
C4 disjuntos 2 `cs_` — pagar 1 (outro intacto OK)

**Total ≥12.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0 (2 capturas) → `FAIL_P0`. Dual links sem captura → `FAIL_P1`.  
P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EM_BAG_PAY_RETEST_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
