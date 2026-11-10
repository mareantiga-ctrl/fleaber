# Pack cego POS_BFBK — o que correr agora

**Não uses** BF→BK (`*_POS_ATBE_*`): essa ronda já foi auditada e fechada (incl. P0 NFC/NFD).

**Usa estes 6:**

| # | Ficheiro | Superfície |
|---|----------|------------|
| 1 | `tool/prompts/REDTEAM_BLIND_BL_MARKETPLACE_POS_BFBK_v1.md` | Marketplace / checkout / saco |
| 2 | `tool/prompts/REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1.md` | Chat / provas / inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_BN_LIVE_POS_BFBK_v1.md` | Live / staff / FOMO |
| 4 | `tool/prompts/REDTEAM_BLIND_BO_HUB_EDGE_POS_BFBK_v1.md` | Hub / Edge / Mux / tip |
| 5 | `tool/prompts/REDTEAM_BLIND_BP_PAYOUT_POS_BFBK_v1.md` | Payout / wallet / refund |
| 6 | `tool/prompts/REDTEAM_BLIND_BQ_DISPUTA_POS_BFBK_v1.md` | Disputa / envio / devolução |

Pasta por auditor: `tool/redteam_blind_<bl|bm|…>_<timestamp>/FROZEN_REPORT.md`

**Obrigatório no topo:** `## CONTAGEM` + `TOTAL P0–P3 abertos: N`  
→ `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md` (sem TOTAL = inválido).

Baseline fechada (anti-atrofia — **não** contar exactos):
- BFBK: NFC/NFD idempotency → 1 Transfer; `is_hand` allowlist exacta; seller sem `pedido_devolucao`; Affirm/Cash App denylist; proof needle só no path; FOMO «levou/sold/🛒»; discovery Hub sem VOD prematuro; web_return IP decimal; bag overlap expire; hyphen∥compact dedupe; stock marketplace qty NULL OK na vitrine; reconcile exige captura; `total_qty` gated; anon sem `batata_live_is_broadcasting`
- ATBE residual: Hub VOD só ended; «comprou» via broadcast; tip settle sem oráculo Stripe

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não · **não corrigir**.
