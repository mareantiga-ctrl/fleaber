# Pack cego POS_DBDG — DEEP · saturar mais superfícies

**Não uses** DB→DG (`*_POS_CVDA_v1`): fechados em `sec_dbdg_20260906_batata` + CPI.  
**Não uses** CV→DA / CP→CU / CDCI exactos residual.

## Objectivo

Empurrar **mais áreas para OK/saturado**. Quotas altas. Ataques de **arquitectura / corrida / composição** — não chase de sinónimos FOMO/rails.

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN (INVÁLIDO sem números)

**SEM ESTE BLOCO O RELATÓRIO É INVÁLIDO.**  
O agente de fecho **cola isto no chat primeiro**. Se faltar um número → rejeitar.

`quantos` = inteiro **0, 1, 2…** (nunca «vários»).  
`TOTAL P0–P3 abertos` = P0+P1+P2+P3 **exacto**.  
Ver também `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

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

**Exemplo válido (copiar estrutura):**
```
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 3
```

Cada finding aberto = ID (`P0-1`, `P1-1`…). Soma dos IDs = `quantos`.  
P0–P2 = 0 após quotas → `PASS_CEGO_SATURADO`.

## Os 6 (trabalhar a fundo)

| # | Ficheiro | Superfície | Quota mín. |
|---|----------|------------|------------|
| 1 | `tool/prompts/REDTEAM_BLIND_DH_MARKETPLACE_POS_DBDG_v1.md` | Saco/mutex/preço/stock | ≥16 |
| 2 | `tool/prompts/REDTEAM_BLIND_DI_OFERTAS_CHAT_POS_DBDG_v1.md` | Ofertas/bundles/chat dinheiro | ≥14 |
| 3 | `tool/prompts/REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1.md` | Live hitch/convert/rifa/stock | ≥14 |
| 4 | `tool/prompts/REDTEAM_BLIND_DK_RLS_STORAGE_FSM_POS_DBDG_v1.md` | RLS/storage/FSM encomenda | ≥14 |
| 5 | `tool/prompts/REDTEAM_BLIND_DL_EDGE_SETTLE_POS_DBDG_v1.md` | Edge settle/tip/refund/webhook | ≥12 |
| 6 | `tool/prompts/REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1.md` | Composição multi-superfície | ≥12 |

## Anti-atrofia (HOLD = 1 linha, **não** contar)

Mutex 4∥2 se ≤1 cs_ · `mbωay`/math/copta off · FOMO allowlist deny · welcome OK · label `%252f` deny · follow published · PaysafeCash · PicPay · Coptic · `12,00` notes  

≥50% só residual → `ATROFIA_ABORT`.

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
