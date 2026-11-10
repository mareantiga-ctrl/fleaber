# Pack cego POS_DHDM — DEEP (não stubs)

**Porquê este pack:** o índice anterior tinha prompts **curtos demais** (só “foco” + CONTAGEM). Isso **não** prova saturação — prova prompts fracos.  
Este pack é **igual de duro** a DH/DM: matriz obrigatória, races, pago Stripe, anti-atrofia.

**Já em staging (HOLD 1 linha, não contar):**  
`mb way x` / `xxmbway` / wraps · Hub hide live-hold · saco 4∥2 / bag∥single ≤1 cs_ ou contention · unicode mbway · FOMO allowlist · buyer refund 403

## Objectivo

1. **Reteste hostil** do fecho DHDM com ângulos **novos** (não só repetir B1).  
2. Empurrar wallet / disputa / tip-rifa / composição onde ainda pode haver buraco.  
3. Se ≥40% da tabela for residual clássico → **`ATROFIA_ABORT`** (auditor fraco, não saturação).

## Regra de saturação (dura)

`PASS_CEGO_SATURADO` **só** se:
- quota cumprida + ≥1 Stripe TEST pago (onde aplicável) + ≥3 races (DN/DS)  
- **≥3 ataques “classe nova”** tentadas e documentadas (payload diferente dos HOLD)  
- P0=0 P1=0 P2=0  

Zero findings **sem** classes novas → `ATROFIA_ABORT`, não saturação.

## ⚠️ CONTAGEM — 1.º bloco de CADA FROZEN

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
No fim: `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

## Os 6 (DEEP)

| # | Ficheiro | Superfície | Quota |
|---|----------|------------|-------|
| 1 | `tool/prompts/REDTEAM_BLIND_DN_BAG_MUTEX_POS_DHDM_v1.md` | Saco / mutex / claim / preço | ≥18 |
| 2 | `tool/prompts/REDTEAM_BLIND_DO_PAYMETHOD_HUB_POS_DHDM_v1.md` | Off-platform + Hub + listagem | ≥16 |
| 3 | `tool/prompts/REDTEAM_BLIND_DP_WALLET_PAYOUT_POS_DHDM_v1.md` | Wallet / release / payout | ≥14 |
| 4 | `tool/prompts/REDTEAM_BLIND_DQ_SHIP_DISPUTE_POS_DHDM_v1.md` | Envio / disputa / storage | ≥14 |
| 5 | `tool/prompts/REDTEAM_BLIND_DR_TIP_RAFFLE_POS_DHDM_v1.md` | Tip / rifa / convert / Edge | ≥14 |
| 6 | `tool/prompts/REDTEAM_BLIND_DS_COMPOSICAO_POS_DHDM_v1.md` | Composição multi-superfície | ≥16 |

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
