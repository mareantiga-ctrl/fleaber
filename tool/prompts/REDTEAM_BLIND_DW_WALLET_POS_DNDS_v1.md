# FLEABER — RED TEAM CEGO DW · DEEP · PÓS-DNDS
## Wallet / release / payout / Connect — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Dinheiro **depois** do pago. DP saturado uma vez — **não repetir só buyer refund 403**; inventar forge e races novas.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTDW-<timestamp>-` · pasta `tool/redteam_blind_dw_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** order paga Stripe TEST + Δ wallet observado (antes/depois).
3. **≥3 races** (release∥refund, payout∥payout, credit∥debit, release∥disputa).
4. **≥4 classe_nova**.
5. Actores: buyer · seller · seller2 · anon · service só fixture.
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Buyer nunca mint/force release/payout. Seller só no próprio.  
> Release+refund sem double credit. Payout: overbalance, dest alheio, idempotency, Connect hostil.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
buyer `refund-order` 403 · Coptic payout key · charset 400

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### DW-A Forge wallet (≥5)
A1 JWT insert `wallet_transactions` credit/debit  
A2 RPC adjust / credit hostil (nomear RPC tentadas)  
A3 PATCH profiles/wallet balance fields  
A4 tip unpaid → Δwallet 0  
A5 reorder / negative amount / type typo (`reembolso` forge)

### DW-B Release / retenção (≥4)
B1 release cedo (sem receção / fora regra)  
B2 release∥refund mesma order  
B3 seller2 release order alheia  
B4 double release (2× paralelo + sequencial)

### DW-C Payout / Connect (≥5)
C1 payout > available  
C2 dest Connect account alheio / metadata swap  
C3 2× payout paralelo mesma idempotency key  
C4 idempotency key **diferente** 2× (double pay?)  
C5 Connect onboarding / account link token reuse

### DW-D Caixa (≥2)
D1 **pago 4242** → status + Δwallet regra actual  
D2 seller refund 1× → stock + wallet coerente

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DW1 forge · DW2 release · DW3 race · DW4 payout · DW5 actor · DW6 idempotency · DW7 Δledger

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · 1 pago · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DW_WALLET_POS_DNDS_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
