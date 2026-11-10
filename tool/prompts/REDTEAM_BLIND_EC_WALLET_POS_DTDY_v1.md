# FLEABER — RED TEAM CEGO EC · DEEP · PÓS-DTDY
## Wallet / release / disputa / payout / Connect — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DTDY: mesmo advisory lock release∥disputa + clawback se release já processou. **Provar** sem crédito+disputa aberta; inventar forge/races novas.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEC-<timestamp>-` · pasta `tool/redteam_blind_ec_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** order paga Stripe TEST + Δ wallet observado (antes/depois).
3. **≥3 races** (release∥refund, payout∥payout, release∥disputa **obrigatória**, credit∥debit).
4. **≥4 classe_nova**.
5. Actores: buyer · seller · seller2 · anon · service só fixture.
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> `Future.wait` release∥disputa: **não** (wallet credit **e** disputa open).  
> Um dos dois ganha; se release já creditou, disputa negada **ou** clawback.  
> Buyer nunca mint/force release/payout.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
buyer `refund-order` 403 · Coptic payout key · charset 400 · release∥disputa clássico se só 1 efeito (1 linha reteste)

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### EC-A Forge wallet (≥5)
A1 JWT insert `wallet_transactions` credit/debit  
A2 RPC adjust / credit hostil  
A3 PATCH profiles/wallet balance fields  
A4 tip unpaid → Δwallet 0  
A5 reorder / negative / type typo forge

### EC-B Release / retenção / disputa (≥5) — classe_nova
B1 release cedo (sem receção)  
B2 release∥refund mesma order  
B3 **release∥disputa** paralelo 0ms + 50ms (reteste DW — oráculo wallet+disputa)  
B4 seller2 release/disputa order alheia  
B5 double release (2× paralelo + sequencial)

### EC-C Payout / Connect (≥3)
C1 payout overbalance / dest alheio  
C2 payout∥payout idempotency  
C3 Connect account hostil / seller2

### EC-D Caixa (≥3)
D1 **pago 4242** + release legítimo Δwallet  
D2 após B3: estado final coerente (sem double credit)  
D3 refund após release (clawback / deny)

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
EC1 forge · EC2 release · EC3 disputa race · EC4 payout · EC5 clawback · EC6 actor · EC7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · ≥3 races · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EC_WALLET_POS_DTDY_v1
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
