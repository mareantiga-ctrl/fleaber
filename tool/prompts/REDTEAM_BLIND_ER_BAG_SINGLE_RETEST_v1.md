# FLEABER — RED TEAM CEGO ER · RETESTE · GATE FASE 4
## Bag ∥ artigo avulso — **quota ≥14**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> Fix: write avulso respeita claim; reuse Session de saco que inclui a line; sem overwrite.  
> **Esperado:** ≤1 `cs_` útil (200+400 / 400+200 / reused mesmo sid). **Nunca** 2 creates `reused=false`.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

Prefixo `RTER-<timestamp>-` · pasta `tool/redteam_blind_er_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. **≥5** races bag∥single (timings 0 / 50 / 200 ms; single first; bag first).
3. Dual create 2×200 + 2 `cs_` distintas = **P1** → **bloqueia Fase 4**.
4. **≥1** regressão: 6∥4 e expand ainda 400/≤1 (1 linha cada).
5. **≥1** pago 4242 happy.
6. **≥4 classe_nova**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Saco e avulso da mesma line **não** geram 2 Sessions.  
> Idênticos / 6∥4 / expand continuam fechados.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
4∥2 · bizum · multibanco (não contar)

--------------------------------------------------
## MATRIZ (≥14)
--------------------------------------------------

### ER-A Bag∥single hard (≥6)
A1 bag ABCDE ∥ single C **t=0**  
A2 bag ∥ single C **t=50** (bag first)  
A3 single C first →50ms→ bag ABCDE  
A4 bag∥single∥bag (3 corrotinas)  
A5 bag ABC ∥ single B (meio)  
A6 bag de 2 ∥ single de 1 linha do saco

### ER-B Regressão cadeado (≥4)
B1 6∥4 → ≤1 / 400 overlapping  
B2 expand → 400 no 2.º  
B3 2× bag idêntico → 1 `cs_` reused  
B4 shrink → reuse maior

### ER-C Caixa (≥4)
C1 underpay selo  
C2 2 buyers qty=1  
C3 pago 4242 single OU bag  
C4 disjuntos 2 bags → 2 `cs_` OK

**Total ≥14.**

--------------------------------------------------
## GATE FASE 4
--------------------------------------------------
P0–P2=0 + A1–A6 sem dual create → `PASS_CEGO_SATURADO`.  
Dual → `FAIL_P1` (**não Fase 4**).

```
AUDITOR: REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
