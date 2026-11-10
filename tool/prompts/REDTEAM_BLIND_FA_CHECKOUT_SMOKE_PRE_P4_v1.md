# FLEABER — RED TEAM CEGO FA · SMOKE PRÉ-P4
## Checkout regressão — **quota ≥10**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> GATE bag∥avulso já PASS. Aqui: **1×** bag∥avulso a frio + cadeados adjacentes + 1 pago.  
> **Não** repetir matriz A1–A6 completa.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

Prefixo `RTFA-<timestamp>-` · pasta `tool/redteam_blind_fa_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**10**.
2. **Exactamente 1** race bag ABCDE ∥ single C t=0 (buyer fresco) — esperado ≤1 `cs_` / 400 overlapping.
3. Dual 2×200 + 2 `cs_` `reused=false` = **P1** → pack falha.
4. **≥1** 6∥4 · **≥1** expand · **≥1** 2× bag idêntico.
5. **≥1** pago 4242 (saco ou avulso) coerente.
6. **≥3 classe_nova** (não residual puro).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Fail-closed do saco **não** partiu checkout feliz nem overlap.  
> Um tiro bag∥avulso basta para regressão.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
bizum · multibanco · 4∥2 clássico (não contar)

--------------------------------------------------
## MATRIZ (≥10)
--------------------------------------------------

### FA-A Cadeado (≥4)
A1 bag ABCDE ∥ single C **t=0** fresco → ≤1 / 400  
A2 6∥4 t=0 → 400+200 · 1 `cs_`  
A3 expand subset→50ms→superset → 400 no 2.º  
A4 2× bag idêntico → mesmo `cs_` reused

### FA-B Happy (≥3)
B1 CPI saco happy amount catálogo  
B2 pago 4242 (e2e ou alojado) → `pago` / qty↓  
B3 shrink após open → 400 overlapping (não 2 creates)

### FA-C Caixa (≥3)
C1 underpay body → amount servidor  
C2 disjuntos 2 bags → 2 `cs_` OK  
C3 Hub n após B2 (1 sítio)

**Total ≥10.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0–P2=0 + A1 sem dual → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
