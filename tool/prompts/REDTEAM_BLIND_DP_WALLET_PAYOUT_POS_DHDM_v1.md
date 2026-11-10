# FLEABER — RED TEAM CEGO DP · DEEP · PÓS-DHDM
## Wallet / release / payout / Connect — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Dinheiro **depois** do pago: saldo, retenção, release, payout. Atacar autoridade JWT.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO` · `REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTDP-<timestamp>-` · pasta `tool/redteam_blind_dp_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. **≥1** order paga Stripe TEST no fio + Δ wallet observado.
3. **≥2 races** (release∥refund, payout∥payout, credit∥debit).
4. **≥3 classe_nova** (não só “buyer refund 403”).
5. Actor: buyer JWT · seller JWT · seller2 · anon · service só fixture.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Buyer **nunca** mint saldo / força release / payout.  
> Seller só no próprio. Release + refund **sem** double credit.  
> Payout: dest Connect / IBAN / key hostil; idempotency; overbalance.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
buyer `refund-order` 403 · Coptic payout key · charset 400 residual

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DP-A Wallet forge (≥4)
A1 JWT insert `wallet_transactions` credit  
A2 RPC credit / adjust hostil  
A3 PATCH balance / available  
A4 tip unpaid → Δwallet 0

### DP-B Release / retenção (≥4)
B1 release antes de janela / sem receção  
B2 release∥refund mesma order  
B3 seller2 release order alheia  
B4 double release idempotência

### DP-C Payout / Connect (≥4)
C1 payout amount > available  
C2 dest account alheio / metadata hostil  
C3 2× payout paralelo idempotency  
C4 Connect onboarding token reuse

### DP-D Caixa feliz (≥2)
D1 **pago 4242** → status + Δwallet esperado (0 até release ou regra actual)  
D2 seller refund 1× → stock + wallet coerente

**Total = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DP1 forge · DP2 release · DP3 race · DP4 payout · DP5 actor · DP6 idempotency · DP7 Δledger

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥14 · ≥3 classe_nova · 1 pago · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DP_WALLET_PAYOUT_POS_DHDM_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
