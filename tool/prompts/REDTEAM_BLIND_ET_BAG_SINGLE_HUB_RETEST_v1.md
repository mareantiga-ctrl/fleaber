# FLEABER — RED TEAM CEGO ET · RETESTE · GATE FASE 4
## Bag∥single + Hub / composição — **quota ≥12**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> Último portão composição: bag∥avulso com Hub leftover. Sem dual Session. Sem oversell.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTET-<timestamp>-` · pasta `tool/redteam_blind_et_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**12**.
2. Oráculo ≥2 sítios (Hub + orders ± CPI).
3. **≥4** bag∥single / regressão races.
4. **≥1 pago** · **≥4 classe_nova**.
5. Dual create = **P1** → **não Fase 4**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Bag∥avulso coerente com Hub. Happy bag pago → Hub/order/chat.

--------------------------------------------------
## MATRIZ (≥12)
--------------------------------------------------

### ET-A Bag∥single + Hub (≥5)
A1 bag ABC ∥ single B + Hub  
A2 bag∥single t=50 + Hub leftover pós-pago  
A3 single first → bag + Hub  
A4 bag∥single∥bag + Hub  
A5 6∥4 + Hub (regressão ≤1)

### ET-B Stock / live (≥3)
B1 2 buyers qty=1 + Hub  
B2 expand 400 + Hub  
B3 2× idêntico 1 `cs_` + Hub

### ET-C Caixa (≥4)
C1 bag pago 4 sítios  
C2 leftover qty 2→1  
C3 oferta underpay selo  
C4 release∥disputa 1 efeito (1 linha)

**Total ≥12.**

--------------------------------------------------
## GATE FASE 4
--------------------------------------------------
P0–P2=0 nos 3 (ER+ES+ET) → **OK avançar para Fase 4 / abertura**.  
Qualquer P1 dual → **ainda não**.

```
AUDITOR: REDTEAM_BLIND_ET_BAG_SINGLE_HUB_RETEST_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
