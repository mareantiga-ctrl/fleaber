# Pack cego POS_ALLOWLIST — validar arquitectura (não chase de sinónimos)

**Não uses** CJ→CO (`*_POS_CDCI_*`): fechados + allowlist aplicada.

## ⚠️ CONTAGEM — ler primeiro (obrigatório no FROZEN)

Cada auditor **tem** de pôr no **topo** do `FROZEN_REPORT.md` números claros.
Sem isto o relatório é **INVÁLIDO** (rejeitar / reenviar). Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```

`quantos` = inteiro (0,1,2…). TOTAL = P0+P1+P2+P3. Cada finding aberto = ID (P1-1…).

## Mudança de estratégia

Deixámos de pedir «mais 50 rails/FOMO/scripts».  
Este pack **ataca a allowlist** e o dinheiro/stock residual.

| # | Ficheiro | Foco |
|---|----------|------|
| 1 | `tool/prompts/REDTEAM_BLIND_CP_MARKETPLACE_POS_ALLOW_v1.md` | Claim/overlap/cs_ morta + preço + off-platform encode |
| 2 | `tool/prompts/REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1.md` | Bypass allowlist notes/label/inbox (não lista de rails) |
| 3 | `tool/prompts/REDTEAM_BLIND_CR_LIVE_POS_ALLOW_v1.md` | Bypass stems FOMO; system msg legítima ainda OK |
| 4 | `tool/prompts/REDTEAM_BLIND_CS_HUB_EDGE_POS_ALLOW_v1.md` | Follow/favorite published; tip/Mux residual |
| 5 | `tool/prompts/REDTEAM_BLIND_CT_PAYOUT_POS_ALLOW_v1.md` | Charset allowlist key; I/i; Transfer |
| 6 | `tool/prompts/REDTEAM_BLIND_CU_DISPUTA_POS_ALLOW_v1.md` | Canonical OK (sem 54000); FSM/stock; path concat |

**Anti-atrofia:** não contar exactos PaysafeCash/PicPay/esaurito/Coptic/follow unpublished se HOLD.  
**Saturação:** se 0 P0–P2 após quotas → `PASS_CEGO_SATURADO` (famílias allowlist).  
Staging · TEST · **não corrigir** · Fase 4 **não**.
