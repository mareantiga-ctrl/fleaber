# Pack cego POS_DTDY — DEEP completo (DZ→EE)

**Porquê:** DT–DY achou **6** abertos (DT bag dual-Session, DU live_item pós-rifa, DV revoke/proof, DW release∥disputa). Fechos em staging; este pack **retesta torto** + empurra saturação.  
Se ≥40% residual clássico → `ATROFIA_ABORT`.

**Já fechado em staging (HOLD ≤1 linha — não contar):**  
TTL claim 120s + wait 40×200ms · expand→expire **+ re-claim create** (nunca create sem mutex) · rifa seal `sold`/não reabre `available` · revoke sem GRANT JWT · `proof_ok` lê registry · release∥disputa mesmo lock + clawback · DX/DY saturados clássicos

## Objectivo

1. Retestar fechos DTDY com **ângulos novos** (não só 4∥2 / Hub 0 clássico).  
2. Empurrar bag timings, multi-winner rifa, storage pós-revoke, wallet races, Edge, composição.  
3. Distinguir **saturação real** de **auditor frouxo**.

## Regra de saturação (obrigatória)

`PASS_CEGO_SATURADO` **só** se:
- quota cumprida  
- ≥1 Stripe TEST pago (onde a matriz pede)  
- ≥4 races (DZ/EE) ou ≥3 (outros)  
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
| 1 | `tool/prompts/REDTEAM_BLIND_DZ_BAG_MUTEX_POS_DTDY_v1.md` | Saco / expand / mutex | ≥20 |
| 2 | `tool/prompts/REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1.md` | Rifa / Hub / live_item | ≥16 |
| 3 | `tool/prompts/REDTEAM_BLIND_EB_STORAGE_POS_DTDY_v1.md` | Storage / revoke / disputa | ≥16 |
| 4 | `tool/prompts/REDTEAM_BLIND_EC_WALLET_POS_DTDY_v1.md` | Wallet / release∥disputa | ≥16 |
| 5 | `tool/prompts/REDTEAM_BLIND_ED_EDGE_POS_DTDY_v1.md` | Edge settle / tip / webhook | ≥16 |
| 6 | `tool/prompts/REDTEAM_BLIND_EE_COMPOSICAO_POS_DTDY_v1.md` | Multi-superfície | ≥18 |

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **não corrigir** · Fase 4 **não**.
