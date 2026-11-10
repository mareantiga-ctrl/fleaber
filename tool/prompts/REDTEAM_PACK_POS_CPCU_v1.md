# Pack cego POS_CPCU — revalidar fechos + atacar residual

**Não uses** CP→CU (`*_POS_ALLOW_v1`): fechados em `sec_cpcu_20260906_batata` + CPI deploy.  
**Não uses** CJ→CO / CDCI / BXCC exactos residual.

## ⚠️ CONTAGEM — a 1.ª coisa do FROZEN (números obrigatórios)

O agente de fecho **só** fecha se vir isto no **topo**. Sem isto = relatório **INVÁLIDO** (reenviar).  
Cópia exacta: `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

**Tem de aparecer assim (com N = 0,1,2… — nunca «vários»):**

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

TOTAL = P0+P1+P2+P3. Cada finding aberto = ID `P1-1`, `P2-1`…  
Se P0–P2 = 0 após quotas → podes `PASS_CEGO_SATURADO`.

## Missão do pack

1. **Regressão dos 5 fechos CPCU** (se exacto HOLD → **não** contar como finding novo; 1 linha controlo).
2. **Buracos novos** na mesma superfície (encoding / subset / path / published) — não chase sinónimos de rails/FOMO.
3. Inclui **Hub/CS** (faltou na ronda anterior).

| # | Ficheiro | Foco |
|---|----------|------|
| 1 | `tool/prompts/REDTEAM_BLIND_CV_MARKETPLACE_POS_CPCU_v1.md` | Bag 4∥2 + off-platform encode + claim |
| 2 | `tool/prompts/REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1.md` | Notes allowlist estrita + inbox |
| 3 | `tool/prompts/REDTEAM_BLIND_CX_LIVE_POS_CPCU_v1.md` | FOMO stems + welcome OK |
| 4 | `tool/prompts/REDTEAM_BLIND_CY_HUB_EDGE_POS_CPCU_v1.md` | Follow/favorite published; tip/Mux (**ex-CS**) |
| 5 | `tool/prompts/REDTEAM_BLIND_CZ_PAYOUT_POS_CPCU_v1.md` | Charset key + Transfer |
| 6 | `tool/prompts/REDTEAM_BLIND_DA_DISPUTA_POS_CPCU_v1.md` | Path exacto; sem 54000; FSM |

**Anti-atrofia HOLD (não contar):** PaysafeCash · PicPay · esaurito · Coptic · follow unpublished · `12,00` bare notes · `já foi` FOMO · `mbway`+ZWSP · `%252f%255c` disputa — se HOLD = fecho OK.  
≥50% só residual → `ATROFIA_ABORT`.

**Saturação:** quotas OK + P0–P2 = 0 → `PASS_CEGO_SATURADO`.  
Staging · TEST · **não corrigir** · Fase 4 **não**.
