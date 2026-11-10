# FLEABER — RED TEAM CEGO EN · RETESTE · POS_OPEN_GATE
## Saco + Hub + composição — **quota ≥14**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Reteste EK: 6∥4 / expand / bag∥single **com** Hub leftover. Fail-closed esperado.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEN-<timestamp>-` · pasta `tool/redteam_blind_en_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. Oráculo ≥2 sítios (Hub + orders ± CPI).
3. **≥4 races** bag · **≥1 pago** · **≥4 classe_nova**.
4. Dual create no bag = **P1**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Bag overlap coerente com Hub (sem oversell, ≤1 Session útil).  
> Happy path: bag pago → Hub/order/chat.

--------------------------------------------------
## MATRIZ (≥14)
--------------------------------------------------

### EN-A Bag gate (≥5)
A1 6∥4 + Hub leftover pós-pago  
A2 expand + Hub  
A3 bag∥single + Hub  
A4 shrink + Hub  
A5 2× idêntico + Hub

### EN-B Stock / live (≥4)
B1 2 buyers qty=1 + Hub  
B2 rifa drawn + Hub + live_item  
B3 hitch A + bag B  
B4 unlist∥CPI

### EN-C Caixa composição (≥5)
C1 bag pago único 4 sítios  
C2 oferta underpay selo  
C3 release∥disputa clawback (1 efeito)  
C4 leftover qty 2→1  
C5 bizum sem `cs_` (1 linha)

**Total ≥14.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0–P2=0 → `PASS_CEGO_SATURADO`. Dual bag → `FAIL_P1`.

```
AUDITOR: REDTEAM_BLIND_EN_BAG_COMPOSICAO_RETEST_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
