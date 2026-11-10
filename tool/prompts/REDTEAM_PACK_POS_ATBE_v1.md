# Pack cego POS_ATBE — o que correr agora

**Não uses** os prompts AT→BE (`*_POS_ANAS_*`): essa ronda já foi auditada e fechada.

**Usa estes 6** (um por superfície), em paralelo ou pela ordem:

| # | Ficheiro | Superfície |
|---|----------|------------|
| 1 | `tool/prompts/REDTEAM_BLIND_BF_MARKETPLACE_POS_ATBE_v1.md` | Marketplace / checkout / saco |
| 2 | `tool/prompts/REDTEAM_BLIND_BG_CHAT_POS_ATBE_v1.md` | Chat / provas / inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_BH_LIVE_POS_ATBE_v1.md` | Live / staff / broadcast |
| 4 | `tool/prompts/REDTEAM_BLIND_BI_HUB_EDGE_POS_ATBE_v1.md` | Hub / Edge / Mux / tip |
| 5 | `tool/prompts/REDTEAM_BLIND_BJ_PAYOUT_POS_ATBE_v1.md` | Payout / wallet / refund Edge |
| 6 | `tool/prompts/REDTEAM_BLIND_BK_DISPUTA_POS_ATBE_v1.md` | Disputa / envio / devolução |

Cada auditor grava em `tool/redteam_blind_<bf|bg|…>_<timestamp>/FROZEN_REPORT.md`.

**Obrigatório no topo do report:** bloco `## CONTAGEM` + `TOTAL P0–P3 abertos: N`  
→ ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md` (sem TOTAL = relatório inválido).

Baseline fechada (anti-atrofia — **não** contar exactos):
- ATBE: bag UUID normalize, `product_offer_id` imutável, FSM devolução, proof_url bound, Klarna/iDEAL denylist, payout POST-only + amount estrito, shipped_at now, pós-refund sem enviado, total_qty anon revoke, refund status real
- Residual Hub: VOD só `ended`, draft fora da grelha, stock JWT gated, «comprou» só via `purchase_broadcast`, tip settle sem oráculo Stripe

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não iniciar · **não corrigir**.
