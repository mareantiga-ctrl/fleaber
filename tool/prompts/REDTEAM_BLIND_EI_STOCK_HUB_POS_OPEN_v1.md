# FLEABER — RED TEAM CEGO EI · DEEP · POS_OPEN_MVP
## Stock / Hub / hold sob stress de abertura — **quota ≥16**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Abrir a todos = muitos compradores ao mesmo tempo. Oversell = morte do MVP.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEI-<timestamp>-` · pasta `tool/redteam_blind_ei_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. **≥4 races** (2 buyers, bag∥Hub, unlist∥CPI, rifa∥CPI).
3. **≥1 pago 4242** + leftover Hub coerente.
4. **≥4 classe_nova**.
5. Oversell (2 donos qty=1) = **P0/P1**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> qty=1 → ≤1 hold/venda válida. Hub reflecte. Bag overlap não cria 2 stock claims.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Hub hide sold clássico (1 linha) · FOMO deny

--------------------------------------------------
## MATRIZ (≥16)
--------------------------------------------------

### EI-A Hold / 2 buyers (≥5)
A1 2 buyers insert qty=1 paralelo  
A2 2 buyers CPI paralelo  
A3 bag buyer1 ∥ single buyer2 mesmo SKU  
A4 favorite+hold+2.º  
A5 cancel/refund → Hub restore

### EI-B Hub / live (≥5)
B1 sold+listed vs Hub  
B2 leftover qty 2→1 após pago  
B3 rifa drawn ∥ CPI  
B4 unlist∥CPI  
B5 end_live∥bag

### EI-C Bag stock (≥3)
C1 6∥4 overlap — stock holds coerentes (≤1 dono efectivo)  
C2 cross-seller bag deny  
C3 qty hostil body

### EI-D Caixa (≥3)
D1 pago 4242 + Hub  
D2 2.º insert após pago  
D3 Hub public vs products qty

**Total ≥16.**

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
P0–P2=0 → `PASS_CEGO_SATURADO`. Oversell → `FAIL_P0`/`FAIL_P1`.

```
AUDITOR: REDTEAM_BLIND_EI_STOCK_HUB_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
