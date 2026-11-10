# Pack cego POS_BLBQ — o que correr agora

**Não uses** BL→BQ (`*_POS_BFBK_*`): essa ronda já foi auditada e fechada (P0–P3).  
**BL** (marketplace POS_BFBK) **não chegou ao disco** — este pack **volta a cobrir marketplace** (BR) com variantes novas.

**Usa estes 6:**

| # | Ficheiro | Superfície |
|---|----------|------------|
| 1 | `tool/prompts/REDTEAM_BLIND_BR_MARKETPLACE_POS_BLBQ_v1.md` | Marketplace / checkout / saco |
| 2 | `tool/prompts/REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1.md` | Chat / provas / inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1.md` | Live / staff / FOMO |
| 4 | `tool/prompts/REDTEAM_BLIND_BU_HUB_EDGE_POS_BLBQ_v1.md` | Hub / Edge / Mux / tip |
| 5 | `tool/prompts/REDTEAM_BLIND_BV_PAYOUT_POS_BLBQ_v1.md` | Payout / wallet / refund |
| 6 | `tool/prompts/REDTEAM_BLIND_BW_DISPUTA_POS_BLBQ_v1.md` | Disputa / envio / devolução |

Pasta por auditor: `tool/redteam_blind_<br|bs|…>_<timestamp>/FROZEN_REPORT.md`

**Obrigatório no topo do report:** `## CONTAGEM` + `TOTAL P0–P3 abertos: N` + checklist 1–8 com **números**.  
→ `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md` (sem TOTAL = inválido).

Baseline fechada (anti-atrofia — **não** contar exactos):
- BLBQ: Clearpay/Shop Pay/Strike/Zelle notes+inbox; `proof_url` canónico sem `../`; card `meta` extra; FOMO claimed/snap up; buyer sem `accept_broadcast`; hitch `logical_item_id` conta no stock; `lives` anon sem colunas Mux VOD; Hub items anon 200; `resolve_handle` unpublished sem live → not_found; payout NFKC/ZWJ → 1 Transfer; `web_return` IP decimal **cru** (2130706433); replies disputa path-only + host storage + sem `../` + sem `fleaber.pt`
- BFBK: NFC/NFD 1 Transfer; `is_hand` allowlist; seller sem `pedido_devolucao`; Affirm/Cash App; FOMO levou/sold; discovery sem VOD prematuro; bag overlap expire
- ATBE residual: Hub VOD só ended; «comprou» via broadcast; tip settle sem oráculo Stripe

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · produção proibida · Fase 4 não · **não corrigir**.
