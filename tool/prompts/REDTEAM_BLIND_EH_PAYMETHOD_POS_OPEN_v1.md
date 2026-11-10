# FLEABER — RED TEAM CEGO EH · DEEP · POS_OPEN_MVP
## Métodos de pagamento / off-platform / App — **quota ≥16**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Sellers reais usam MB WAY, Multibanco, transferência, mão. Stripe **só** «na App». Provar denylist + App feliz.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEH-<timestamp>-` · pasta `tool/redteam_blind_eh_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥4 classe_nova** (não só `mb way x`).
3. **≥1** CPI feliz «Pagamento na App» / card → `cs_` + **1 pago 4242**.
4. Off-platform → **400** sem `cs_` (RPC + CPI).
5. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Multibanco, Ifthenpay, COD, SIBS, MB WAY wraps → sem Session.  
> Pagamento na App / card / applepay → Session OK.  
> JSON/`notes` hostis não abrem Stripe.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1)
--------------------------------------------------
`mb way` exact · `mb way x` · unicode mbωay (1 linha cada máx)

--------------------------------------------------
## MATRIZ (≥16)
--------------------------------------------------

### EH-A Off deve bloquear (≥7)
A1 `multibanco`  
A2 `ifthenpay` + JSON `{"psp":"ifthenpay"}`  
A3 `contra reembolso` / `contra_reembolso` / COD  
A4 `sibs` / referência  
A5 MB WAY wrap **novo** (não só `x`/`via`)  
A6 transferência wrap novo  
A7 método array / notes+method mismatch

### EH-B App deve abrir (≥4)
B1 Pagamento na App → `cs_`  
B2 card → `cs_`  
B3 applepay/googlepay label se suportado  
B4 **pago 4242** App

### EH-C Forge / edge (≥5)
C1 PATCH method off **após** `cs_` open  
C2 buyer2 CPI order off alheia  
C3 RPC `batata_is_off_platform_payment` vs CPI alinhados  
C4 empty / null method  
C5 Paysafe / lixo ASCII

**Total ≥16.**

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
P0–P2=0 + quota → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EH_PAYMETHOD_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
