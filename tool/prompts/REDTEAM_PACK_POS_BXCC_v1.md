# Pack cego POS_BXCC — DEEP (uma corrida densa, não 6 skim)

**Não uses** BX→CC (`*_POS_BRBW_*`): essa ronda já foi auditada e fechada.

**Usa estes 6 (versão DEEP — substituem os skim v1):**

| # | Ficheiro | Superfície | Profundidade mínima |
|---|----------|------------|---------------------|
| 1 | `tool/prompts/REDTEAM_BLIND_CD_MARKETPLACE_POS_BXCC_v1.md` | Marketplace / checkout / saco | ≥4 poços + ≥2 races + 1 composição até caixa |
| 2 | `tool/prompts/REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1.md` | Chat / provas / inbox | ≥4 poços + matriz rails+encoding + storage |
| 3 | `tool/prompts/REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1.md` | Live / staff / FOMO / Mux | ≥4 poços + FOMO matriz + race end∥accept |
| 4 | `tool/prompts/REDTEAM_BLIND_CG_HUB_EDGE_POS_BXCC_v1.md` | Hub / Edge / Mux / tip | ≥4 poços + discovery+Edge+tip+storage |
| 5 | `tool/prompts/REDTEAM_BLIND_CH_PAYOUT_POS_BXCC_v1.md` | Payout / wallet / refund | ≥4 poços + idempotency matriz + Transfer real TEST |
| 6 | `tool/prompts/REDTEAM_BLIND_CI_DISPUTA_POS_BXCC_v1.md` | Disputa / envio / devolução | ≥4 poços + path matriz + 2.ª disputa + stock |

Pasta: `tool/redteam_blind_<cd|ce|…>_<timestamp>/FROZEN_REPORT.md`

## Porque DEEP (ler antes de lançar)

Nas rondas finas (BX–CC) cada auditor trazia 1–2 «novas» e a corrida seguinte encontrava a variante seguinte.  
**Agora:** cada prompt obriga a **esgotar uma matriz de variantes no mesmo freeze** — encoding, races, 2.º actor, composição até Δwallet/stock/Stripe.  
Objectivo: **menos packs**, findings mais densos por FROZEN_REPORT, sem skim.

`PASS_CEGO_SATURADO` **só** se cumprires a secção **SATURAÇÃO** do prompt (poços + tácticas mínimas). Sem isso → `INCONCLUSIVO`, não PASS.

## CONTAGEM — OBRIGATÓRIO no topo de CADA FROZEN_REPORT

Sem isto = **INVÁLIDO**. Só números (0,1,2…).

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

## Baseline fechada (anti-atrofia — **não** contar exactos)

- **BXCC:** bag∥single mesmo `batata_bag_checkout_claim`; Skrill/Neteller/Paysafecard/MoneyGram/GCash/Perfect Money/enviado MB; strip U+206A/CGJ/Hangul halfwidth; proof `%252e`; FOMO last one/já não há/sem stock; Mux playback revoke auth; resolve+discovery só `hub_published`; Greek α/ο/ρ fold; path bidi/`%252e`/unicode slash disputa
- **BRBW/BLBQ/BFBK/ATBE:** packs anteriores (claim multi-saco, Clearpay ASCII, FOMO PT/EN clássico, etc.)

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 **não** · **não corrigir**.
