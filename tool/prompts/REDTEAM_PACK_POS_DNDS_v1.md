# Pack cego POS_DNDS — DEEP completo (DT→DY)

**Porquê:** vários auditores recentes saíram a 0 findings. Este pack **não é stub**: matrizes longas, races, pago Stripe, **≥4 classe_nova** por auditor, anti-atrofia dura.  
Se ≥40% residual clássico → `ATROFIA_ABORT` (não celebrar saturação).

**Já fechado em staging (HOLD ≤1 linha — não contar):**  
saco 4∥2 / 5∥3 / bag∥single se ≤1 `cs_` ou contention · wraps `mb way x` · Hub live-hold · rifa drawn selado · revoke registry · FOMO allowlist · buyer refund 403 · unicode mbway

## Objectivo

1. Retestar fechos DNDS com **ângulos ainda mais tortos**.  
2. Empurrar wallet / Edge / storage / composição onde ainda pode haver buraco.  
3. Distinguir **saturação real** de **auditor frouxo**.

## Regra de saturação (obrigatória)

`PASS_CEGO_SATURADO` **só** se:
- quota cumprida  
- ≥1 Stripe TEST pago (onde a matriz pede)  
- ≥4 races (DT/DY) ou ≥3 (outros)  
- **≥4 probes `classe_nova=SIM`** documentadas  
- P0=0 P1=0 P2=0  

Zero findings **sem** 4 classes novas → `ATROFIA_ABORT`.

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN (INVÁLIDO sem números)

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

No fim: `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

## Os 6 (completos)

| # | Ficheiro | Superfície | Quota |
|---|----------|------------|-------|
| 1 | `tool/prompts/REDTEAM_BLIND_DT_BAG_MUTEX_POS_DNDS_v1.md` | Saco / mutex / corridas | ≥20 |
| 2 | `tool/prompts/REDTEAM_BLIND_DU_RAFFLE_HUB_POS_DNDS_v1.md` | Rifa / Hub / stock | ≥16 |
| 3 | `tool/prompts/REDTEAM_BLIND_DV_STORAGE_POS_DNDS_v1.md` | Storage / disputa / label | ≥16 |
| 4 | `tool/prompts/REDTEAM_BLIND_DW_WALLET_POS_DNDS_v1.md` | Wallet / release / payout | ≥16 |
| 5 | `tool/prompts/REDTEAM_BLIND_DX_EDGE_POS_DNDS_v1.md` | Edge settle / tip / webhook | ≥16 |
| 6 | `tool/prompts/REDTEAM_BLIND_DY_COMPOSICAO_POS_DNDS_v1.md` | Multi-superfície | ≥18 |

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
