# Pack cego POS_CDCI — DEEP v2 (quotas iguais nos 6)

**Não uses** CD→CI (`*_POS_BXCC_*`): fechados.

## Os 6 ficheiros (lançar estes)

| # | Ficheiro | Superfície | Quota mínima (senão INCONCLUSIVO) |
|---|----------|------------|-----------------------------------|
| 1 | `tool/prompts/REDTEAM_BLIND_CJ_MARKETPLACE_POS_CDCI_v1.md` | Marketplace / checkout / saco | ≥20 probes LIVE + ≥3 races + 1 Stripe pago |
| 2 | `tool/prompts/REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1.md` | Chat / provas / inbox | ≥24 rails/strings + ≥8 paths + inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_CL_LIVE_POS_CDCI_v1.md` | Live / staff / FOMO | ≥24 FOMO + staff + hitch race + Mux/realtime |
| 4 | `tool/prompts/REDTEAM_BLIND_CM_HUB_EDGE_POS_CDCI_v1.md` | Hub / Edge / Mux / tip | ≥16 discovery/follow + tip mid-unpub + Edge/CORS |
| 5 | `tool/prompts/REDTEAM_BLIND_CN_PAYOUT_POS_CDCI_v1.md` | Payout / wallet / refund | ≥16 idempotency keys + Transfer TEST + release∥refund |
| 6 | `tool/prompts/REDTEAM_BLIND_CO_DISPUTA_POS_CDCI_v1.md` | Disputa / envio / devolução | ≥16 paths + label + carrier + FSM stock |

Pasta: `tool/redteam_blind_<cj|ck|…>_<timestamp>/FROZEN_REPORT.md`

## Porquê v2 (ler antes de lançar)

Na ronda CD–CI o chat (CE) trouxe **muitos** findings porque tinha **lista obrigatória de strings**.  
Marketplace/live/hub/payout/disputa trouxeram **poucos** — o auditor podia marcar HOLD após 3–4 tentativas.

**Regra nova (todos os 6 iguais):**
1. No FROZEN_REPORT, secção **`## TABELA DE PROVAS`** com **uma linha por probe** (ID, payload, HTTP/BD, HOLD|FAIL).
2. Contagem de linhas da tabela **≥ quota** do prompt.
3. Sem tabela completa ou abaixo da quota → **`INCONCLUSIVO`** (não `PASS_CEGO_SATURADO`, não “saturado”).
4. Parar após 2–3 HOLDs = **inválido**.
5. Classes iguais = **1 finding** (não inflacionar); mas a **matriz tem de ser corrida toda**.

## CONTAGEM — OBRIGATÓRIO no topo

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

Baseline fechada (não contar exactos): ver cada prompt + CDCI/BXCC packs.

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 **não** · **não corrigir**.
