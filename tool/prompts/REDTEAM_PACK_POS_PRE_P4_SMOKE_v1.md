# Pack cego POS_PRE_P4 — smoke confirmação → Fase 4

**Meta:** após GATE bag∥avulso `PASS_CEGO_SATURADO` (20260907T0856), **confirmar** que o fail-closed não partiu o resto.  
**Não** é redescobrir bag∥single (já fechado).  
Se os **3** saírem `P0–P2=0` → **OK avançar Fase 4 / abertura** com confiança.  
Qualquer P0/P1 novo → **ainda não** Fase 4.

**Já fechado (HOLD ≤1 — não contar como finding novo):**  
bag∥avulso dual · 6∥4 / expand / shrink · bizum/multibanco · EO/EP/EQ maratonas longas (regressão residual só)

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0 dinheiro irreversível? SIM|NÃO
2. Quantos P0: N
3. P1 caminho explorável? SIM|NÃO
4. Quantos P1: N
5. P2 hygiene? SIM|NÃO
6. Quantos P2: N
7. P3 baixo risco? SIM|NÃO
8. Quantos P3: N
```

`RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`  
`tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

## Os 3 (lentes **diferentes**)

| # | Ficheiro | Foco |
|---|----------|------|
| 1 | `tool/prompts/REDTEAM_BLIND_FA_CHECKOUT_SMOKE_PRE_P4_v1.md` | checkout: 1× bag∥avulso + 6∥4 + expand + happy pago |
| 2 | `tool/prompts/REDTEAM_BLIND_FB_STOCK_MONEY_SMOKE_PRE_P4_v1.md` | stock 2 buyers · Hub · underpay · wallet Δ |
| 3 | `tool/prompts/REDTEAM_BLIND_FC_DISPUTE_EDGE_SMOKE_PRE_P4_v1.md` | release∥disputa · refund · settle hostil · tip unpaid |

**Ordem:** FA → FB → FC.  
**Tempo:** curto (smoke, não maratona).  
Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir**.

```
PACK: REDTEAM_PACK_POS_PRE_P4_SMOKE_v1
GATE_PRE: PASS_CEGO_SATURADO (bag∥avulso 20260907T0856)
VEREDICTO_PACK: FAIL_P*|PASS_CEGO_SATURADO → OK_FASE_4
```
