# FLEABER — RED TEAM CEGO FC · SMOKE PRÉ-P4
## Disputa / Edge / refund curto — **quota ≥10**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR**.  
> Lente **diferente** de FA/FB: release∥disputa, refund, settle hostil, tip unpaid.  
> **Não** bag∥avulso (já no GATE + FA).

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTFC-<timestamp>-` · pasta `tool/redteam_blind_fc_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**10**.
2. **≥1** release∥disputa (0 ou 50 ms) → **1** efeito líquido (não crédito+claim).
3. **≥1** buyer refund 403 · **≥1** seller refund idempotent (2× → 1).
4. **≥1** settle unpaid / session alheia → sem credit.
5. **≥1** tip unpaid Δwallet=0.
6. Double credit / forge webhook sem sig que credita = **P0**.
7. **≥3 classe_nova**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Pós-pago e Edge de caixa continuam à prova de corrida e forge.  
> Um efeito por intenção.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
tip seller≠owner · Coptic charset (≤1 cada, não contar)

--------------------------------------------------
## MATRIZ (≥10)
--------------------------------------------------

### FC-A Disputa / release (≥3)
A1 release∥disputa t=0 → 1 efeito  
A2 release∥disputa t=50 → 1 efeito  
A3 disputa após `enviado` (janela) — documentar allow/deny

### FC-B Refund / settle (≥4)
B1 buyer refund → 403  
B2 seller refund 2× mesma order → 1 refund  
B3 settle session unpaid → 402 / sem Δwallet  
B4 settle session alheia → deny

### FC-C Tip / Edge (≥3)
C1 tip Session unpaid GET settle → Δwallet=0  
C2 webhook sem assinatura → deny (sem side-effect)  
C3 CORS Origin evil em CPI ou refund — sem eco perigoso (1 linha)

**Total ≥10.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0–P2=0 → `PASS_CEGO_SATURADO`.  
Pack completo FA+FB+FC P0–P2=0 → **OK Fase 4**.

```
AUDITOR: REDTEAM_BLIND_FC_DISPUTE_EDGE_SMOKE_PRE_P4_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
