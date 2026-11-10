# Pack cego POS_OPEN_GATE — 3 reteste saco + 3 DEEP longos

**Contexto:** fail-closed no expand/overlap (sem 2.ª Session) + bizum na denylist.  
**Objectivo:** (A) provar o cadeado do saco; (B) caçar buracos novos com auditorias longas.

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN (obrigatório)

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

No fim: `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`  
`tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

## Os 6

| # | Tipo | Ficheiro | Quota |
|---|------|----------|-------|
| 1 | **Reteste** | `tool/prompts/REDTEAM_BLIND_EL_BAG_RETEST_POS_OPEN_v1.md` | ≥18 |
| 2 | **Reteste** | `tool/prompts/REDTEAM_BLIND_EM_BAG_PAY_RETEST_POS_OPEN_v1.md` | ≥12 |
| 3 | **Reteste** | `tool/prompts/REDTEAM_BLIND_EN_BAG_COMPOSICAO_RETEST_POS_OPEN_v1.md` | ≥14 |
| 4 | **DEEP longo** | `tool/prompts/REDTEAM_BLIND_EO_MONEY_MARATHON_POS_OPEN_v1.md` | ≥28 |
| 5 | **DEEP longo** | `tool/prompts/REDTEAM_BLIND_EP_MULTI_BUYER_STRESS_POS_OPEN_v1.md` | ≥24 |
| 6 | **DEEP longo** | `tool/prompts/REDTEAM_BLIND_EQ_DISPUTE_SHIP_MARATHON_POS_OPEN_v1.md` | ≥24 |

**Gate abertura:** EL+EM+EN com P0–P2=0 no saco. EO/EP/EQ não podem trazer P0/P1 novos.

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
