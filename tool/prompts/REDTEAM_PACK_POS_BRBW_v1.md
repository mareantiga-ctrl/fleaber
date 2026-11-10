# Pack cego POS_BRBW — o que correr agora

**Não uses** BR→BW (`*_POS_BLBQ_*`): essa ronda já foi auditada e fechada.

**Usa estes 6:**

| # | Ficheiro | Superfície |
|---|----------|------------|
| 1 | `tool/prompts/REDTEAM_BLIND_BX_MARKETPLACE_POS_BRBW_v1.md` | Marketplace / checkout / saco |
| 2 | `tool/prompts/REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1.md` | Chat / provas / inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1.md` | Live / staff / FOMO |
| 4 | `tool/prompts/REDTEAM_BLIND_CA_HUB_EDGE_POS_BRBW_v1.md` | Hub / Edge / Mux / tip |
| 5 | `tool/prompts/REDTEAM_BLIND_CB_PAYOUT_POS_BRBW_v1.md` | Payout / wallet / refund |
| 6 | `tool/prompts/REDTEAM_BLIND_CC_DISPUTA_POS_BRBW_v1.md` | Disputa / envio / devolução |

Pasta: `tool/redteam_blind_<bx|by|…>_<timestamp>/FROZEN_REPORT.md`

## CONTAGEM — OBRIGATÓRIO no topo de CADA FROZEN_REPORT

Sem isto o relatório é **INVÁLIDO**. Números inteiros (0,1,2…) — nunca «vários».

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N

1. P0? SIM|NÃO   2. Quantos P0: N
3. P1? SIM|NÃO   4. Quantos P1: N
5. P2? SIM|NÃO   6. Quantos P2: N
7. P3? SIM|NÃO   8. Quantos P3: N
```

→ `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`

Baseline fechada (anti-atrofia — **não** contar exactos):
- BRBW: `batata_bag_checkout_claim` atómico; Payoneer/WU/Interac/BTC/USDT/Paytm/Mercado Pago; strip U+180E/Hangul/U+2063; proof `．．`/`%c0%ae`/`／`; FOMO esgotado/gone/mine/out of stock; paused não vende; Mux VOD/asset revoke auth; discovery+resolve-mux `hub_published`; FOMO inactive not_public; payout cirílico+NBSP
- BLBQ/BFBK/ATBE: ver packs anteriores

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não · **não corrigir**.
