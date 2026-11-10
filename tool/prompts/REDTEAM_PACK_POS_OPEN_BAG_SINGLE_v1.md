# Pack cego POS_OPEN_BAG_SINGLE — 3 reteste · gate → Fase 4

**Meta:** P0=0 P1=0 P2=0 no **bag∥single** (único residual OPEN).  
Se os 3 passarem saturados → candidato a **Fase 4 / abrir**.  
Se algum P1 dual `cs_` → ainda **não** Fase 4.

**Já fechado (HOLD ≤1 — não contar):**  
6∥4 / expand / shrink / triângulo / idênticos · bizum · EO/EP/EQ maratonas · write claim avulso + reuse saco

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

## Os 3

| # | Ficheiro | Foco |
|---|----------|------|
| 1 | `tool/prompts/REDTEAM_BLIND_ER_BAG_SINGLE_RETEST_v1.md` | bag∥avulso races |
| 2 | `tool/prompts/REDTEAM_BLIND_ES_BAG_SINGLE_PAY_RETEST_v1.md` | dual + tentar pagar |
| 3 | `tool/prompts/REDTEAM_BLIND_ET_BAG_SINGLE_HUB_RETEST_v1.md` | bag∥avulso + Hub |

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **só se P0–P2=0 nos 3**.
