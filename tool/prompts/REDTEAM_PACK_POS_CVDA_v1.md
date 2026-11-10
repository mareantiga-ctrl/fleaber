# Pack cego POS_CVDA — regressão fechos + residual fino

**Não uses** CV→DA (`*_POS_CPCU_v1`): fechados em `sec_cvda_20260906_batata` + CPI/Mux deploy.  
**Não uses** CP→CU / CJ→CO exactos residual.

## ⚠️ CONTAGEM — a 1.ª coisa do FROZEN (números obrigatórios)

**SEM ESTE BLOCO O RELATÓRIO É INVÁLIDO.**  
Tens de escrever **números** (0, 1, 2…) — nunca «vários».  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

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

TOTAL = P0+P1+P2+P3. Cada finding = ID `P1-1`…  
Se P0–P2 = 0 após quotas → `PASS_CEGO_SATURADO`.

## Missão do pack

1. **Regressão dos 6 fechos CVDA** (exacto HOLD = não contar; 1 linha controlo).
2. **Ângulo novo** na mesma superfície (não chase sinónimos rails/FOMO).
3. Happy path: follow published · disputa+foto · welcome live · MB WAY exact.

| # | Ficheiro | Foco |
|---|----------|------|
| 1 | `tool/prompts/REDTEAM_BLIND_DB_MARKETPLACE_POS_CVDA_v1.md` | Bag 4∥2 lock + off-platform fold |
| 2 | `tool/prompts/REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1.md` | Notes allowlist (já saturado CW — bypass residual) |
| 3 | `tool/prompts/REDTEAM_BLIND_DD_LIVE_POS_CVDA_v1.md` | FOMO + welcome + morph |
| 4 | `tool/prompts/REDTEAM_BLIND_DE_HUB_EDGE_POS_CVDA_v1.md` | Follow/favorite published + CORS |
| 5 | `tool/prompts/REDTEAM_BLIND_DF_PAYOUT_POS_CVDA_v1.md` | Charset payout (já saturado CZ) |
| 6 | `tool/prompts/REDTEAM_BLIND_DG_DISPUTA_POS_CVDA_v1.md` | Prova signed OK; path concat deny |

**Anti-atrofia HOLD (não contar):**  
4∥2 exacto se ≤1 cs_ · μbway/small-caps/NFD · `sumiu tudo`/`🔥🔥🔥`/`es0aurito` · follow published 201 · CORS chrome-extension→fleaber.pt · prova `https://` signed 201 · `%252f%255c` deny · PaysafeCash · PicPay · Coptic · `12,00` notes  

≥50% só residual → `ATROFIA_ABORT`.

Staging · TEST · **não corrigir** · Fase 4 **não**.
