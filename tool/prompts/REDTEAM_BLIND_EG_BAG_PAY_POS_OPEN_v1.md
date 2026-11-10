# FLEABER — RED TEAM CEGO EG · DEEP · POS_OPEN_MVP
## Saco + **tentar pagar duas Sessions** — **quota ≥14** · **GATE P0**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> EF prova ≤1 link útil. EG tenta **P0**: se ainda houver 2 `cs_`, pagar as duas (4242) e ver stock/caixa.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEG-<timestamp>-` · pasta `tool/redteam_blind_eg_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. **≥3** tentativas de dual-checkout overlap que produzam 2 `cs_` **ou** documentem ≤1.
3. Se 2 `cs_` open: **obrigatório** tentar pagar **ambas** (Stripe TEST 4242 / e2e).  
   - 2 capturas + stock inconsistente = **P0**.  
   - 2.ª paga falha / 1.ª expired / refund auto = documentar (pode ser P1 residual se links duplos).
4. **≥4 classe_nova**.
5. **≥3 races**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Dinheiro irreversível **não** acontece no saco overlap.  
> Preferir: nunca 2 open. Se 2 open por bug: 2.ª captura **deve** falhar sem oversell.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
settle unpaid 402 clássico (1 linha) · buyer refund 403 não contar

--------------------------------------------------
## MATRIZ (≥14)
--------------------------------------------------

### EG-A Gerar overlap (≥5)
A1 6∥4 t=0 → listar `cs_` + open?  
A2 expand subset→superset → open count  
A3 bag∥single meio  
A4 stagger 50ms full→subset  
A5 2× bag idêntico (deve 1 `cs_`)

### EG-B Pagar (≥5) — classe_nova
B1 se 2 open: pagar **primeira** 4242  
B2 pagar **segunda** 4242 (mesmo overlap)  
B3 oráculo stock Hub + products + orders (2 pagos?)  
B4 se só 1 open: pagar essa + tentar settle da órfã  
B5 bag disjunto 2 `cs_`: pagar 1 — outro intacto (OK)

### EG-C Caixa / cleanup (≥4)
C1 wallet Δ após B1/B2  
C2 refund se double capture  
C3 Hub leftover coerente  
C4 **1×** happy bag pago único (regressão funcional)

**Total ≥14.**

--------------------------------------------------
## GATE
--------------------------------------------------
P0 (2 capturas / oversell) → `FAIL_P0` **bloqueia abertura**.  
P1 só links sem 2.ª captura → ainda **não abrir** até EF limpar.  
P0–P2=0 + quota → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EG_BAG_PAY_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
