# FLEABER — RED TEAM CEGO · GATE ÚNICO bag∥avulso (Fase 4)

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> **Um só prompt** (ER+ES+ET eram a mesma corrida).  
> Fix 2026-09-07b: causa real = saco **expirava** Session open do avulso e criava 2.ª.  
> Agora: Session open numa line do saco → reuse ou `400 overlapping` — **nunca** expire+create.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

Prefixo `RTGATE-<timestamp>-` · pasta `tool/redteam_blind_gate_<timestamp>/`.

--------------------------------------------------
## PORQUE SÓ 1 PROMPT
--------------------------------------------------
ER / ES / ET mediam **o mesmo P1**: saco ∥ artigo avulso → 2 `cs_`.  
ES = pagar as duas; ET = Hub. Sem dual create, ES/ET são saturação — **não** repetir enquanto dual existir.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**12**.
2. **≥5** races bag∥single (t=0, 50 ms, single-first, bag∥single∥bag, saco 3 e 5).
3. **Nunca** 2× HTTP 200 com 2 `cs_` distintas e `reused=false`.
4. Esperado: ≤1 `cs_` útil (200+400 / reused mesmo sid / 400+200).
5. Se ainda dual: **tentar pagar a 2.ª** (caça P0) — 1 linha.
6. **≥1** regressão 6∥4 e **≥1** expand (ainda 400/≤1).
7. **≥1** pago 4242 happy (saco ou avulso).
8. **≥1** Hub leftover após pago.

--------------------------------------------------
## MATRIZ (≥12)
--------------------------------------------------

### G-A Bag∥single (gate) ≥6
A1 bag ABCDE ∥ single C **t=0** (buyer fresco)  
A2 bag first →50ms→ single C (fresco)  
A3 single first →50ms→ bag (fresco)  
A4 bag ABC ∥ single B t=0 (fresco)  
A5 bag∥single∥bag @200 ms  
A6 bag de 2 first →200ms→ single

### G-B Regressão ≥3
B1 6∥4 → ≤1 / 400  
B2 expand → 400 no 2.º  
B3 2× bag idêntico → 1 `cs_` reused

### G-C Caixa ≥3
C1 pago 4242 do link útil + Hub  
C2 se dual: pagar 2.ª (P0?)  
C3 2 buyers qty=1 sem oversell

**Total ≥12.**

--------------------------------------------------
## GATE FASE 4
--------------------------------------------------
P0–P2=0 + A1–A4 sem dual create → `PASS_CEGO_SATURADO` → **OK falar Fase 4**.  
Qualquer dual → `FAIL_P1` (**ainda não**).

```
AUDITOR: REDTEAM_BLIND_GATE_BAG_SINGLE_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
