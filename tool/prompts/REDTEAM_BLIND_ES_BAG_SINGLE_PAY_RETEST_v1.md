# FLEABER — RED TEAM CEGO ES · RETESTE · GATE FASE 4
## Bag∥single + tentar pagar 2× — **quota ≥10**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> Se ainda 2 `cs_` → pagar ambas (caça P0). Esperado: ≤1 create.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTES-<timestamp>-` · pasta `tool/redteam_blind_es_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**10**.
2. **≥3** bag∥single races.
3. Se 2 open: pagar **ambas** 4242 → 2 capturas = **P0**.
4. Se ≤1: pagar a útil + documentar 2.º 400/reused.
5. **≥1** happy bag pago · **≥3 classe_nova**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Sem dinheiro irreversível. Preferir nunca 2 links.

--------------------------------------------------
## MATRIZ (≥10)
--------------------------------------------------

### ES-A Gerar (≥4)
A1 bag∥single t=0  
A2 single→bag stagger  
A3 bag∥single∥bag  
A4 6∥4 regressão ≤1

### ES-B Pagar (≥3)
B1 se 2 `cs_`: pagar 1.ª  
B2 pagar 2.ª  
B3 stock/Hub/orders (2 pagos? oversell?)

### ES-C Caixa (≥3)
C1 wallet Δ  
C2 happy bag pago  
C3 leftover Hub

**Total ≥10.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0 → `FAIL_P0` (**não Fase 4**). Dual sem captura → `FAIL_P1`.  
P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_ES_BAG_SINGLE_PAY_RETEST_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
