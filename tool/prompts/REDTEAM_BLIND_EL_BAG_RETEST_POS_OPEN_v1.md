# FLEABER — RED TEAM CEGO EL · RETESTE · POS_OPEN_GATE
## Saco fail-closed (overlap / expand) — **quota ≥18**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> OPEN: expand/overlap → **400** `overlapping bag session` (nunca expire+criar 2.ª).  
> Sacos **idênticos** → 1 `cs_` + `reused`. Provar.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

Prefixo `RTEL-<timestamp>-` · pasta `tool/redteam_blind_el_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**18**.
2. **≥5 races** overlap (6∥4, expand, bag∥single, shrink, triângulo).
3. Oráculo: 2× HTTP 200 + 2 `cs_` distintas `reused=false` no overlap = **P1 FAIL**.  
   Esperado overlap: **200+400** ou **400+200** ou **1 `cs_` reused** — **nunca** 2 creates.
4. **≥1** pago 4242 happy bag/single.
5. **≥4 classe_nova** (ângulos de timing).
6. bizum → 400 (1 linha reteste P2).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Fail-closed no overlap de conjuntos diferentes. Idênticos = reuse. Disjuntos = 2 `cs_` OK.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 — não contar)
--------------------------------------------------
4∥2 clássico · multibanco exact · bizum exact se só 400 (1 linha OK na matriz como reteste)

--------------------------------------------------
## MATRIZ (≥18)
--------------------------------------------------

### EL-A Idêntico / mutex (≥4)
A1 2× bag idêntico paralelo → 1 `cs_` reused  
A2 3× mesmo bag → 1 `cs_`  
A3 UUID invertido → 1 `cs_`  
A4 timeout 100ms ∥ complete ∥ retry → 1 `cs_`

### EL-B Overlap fail-closed (≥7) — obrigatório
B1 **6∥4** t=0 → ≤1 create (2.º 400 overlapping ou reused)  
B2 **6∥4** t=50  
B3 **expand** subset→50ms→superset → 2.º **400** (não 2.ª `cs_`)  
B4 **shrink** full→50ms→subset → reuse do maior **ou** 400 (não 2 creates)  
B5 bag∥single meio  
B6 bag∥single∥bag  
B7 AB∥BC∥CA

### EL-C Disjuntos / preço (≥4)
C1 2 bags disjuntos → 2 `cs_` OK  
C2 underpay selo  
C3 2 buyers qty=1  
C4 cross-seller deny

### EL-D Caixa / denylist (≥3)
D1 pago 4242  
D2 **bizum** → 400 sem `cs_`  
D3 Pagamento na App → `cs_` OK

**Total ≥18.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0–P2=0 + B1–B6 sem dual create → `PASS_CEGO_SATURADO`.  
Dual create → `FAIL_P1` (**bloqueia abertura**).

```
AUDITOR: REDTEAM_BLIND_EL_BAG_RETEST_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
