# FLEABER — RED TEAM CEGO EJ · DEEP · POS_OPEN_MVP
## Wallet + Edge pós-pago (abertura) — **quota ≥16**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Sellers reais = release, disputa, refund, tip, payout. Sem mint JWT. Sem double credit.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEJ-<timestamp>-` · pasta `tool/redteam_blind_ej_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥1** order paga + Δ wallet observado.
3. **≥3 races** (release∥disputa, refund∥release, payout∥payout).
4. **≥4 classe_nova**.
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Após pago: release∥disputa sem crédito líquido+claim; refund seller-only; tip unpaid=0; settle não confia amount cliente.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
buyer refund 403 · release∥disputa 1 efeito (1 linha) · tip seller≠owner

--------------------------------------------------
## MATRIZ (≥16)
--------------------------------------------------

### EJ-A Forge (≥4)
A1 JWT wallet_transactions  
A2 RPC credit/debit/clawback  
A3 PATCH balance/dest  
A4 tip unpaid Δ=0

### EJ-B Release / disputa / refund (≥6)
B1 release cedo  
B2 release∥disputa 0ms+50ms  
B3 release∥refund  
B4 double release  
B5 seller2 alheio  
B6 buyer refund 403 (1 residual máx na mesma linha seller OK)

### EJ-C Edge / tip / payout (≥3)
C1 settle amount hostil  
C2 tip∥unpublish  
C3 payout over/dest/idempotency

### EJ-D Caixa (≥3)
D1 pago+release Δ  
D2 clawback se disputa após release  
D3 Transfer count

**Total ≥16.**

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EJ_WALLET_EDGE_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
