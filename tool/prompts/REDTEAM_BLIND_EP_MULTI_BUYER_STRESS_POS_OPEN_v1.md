# FLEABER — RED TEAM CEGO EP · DEEP LONGO · POS_OPEN_GATE
## Stress multi-comprador / Hub / live / stock — **quota ≥24**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Simula **abertura**: 3+ buyers, holds, rifas, bags, Hub. Oversell = P0/P1.  
> Tempo esperado: **alto** (muitos SKUs, lives, races).

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTEP-<timestamp>-` · pasta `tool/redteam_blind_ep_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**24**.
2. Actores: **≥3 buyers** + 2 sellers no fio.
3. **≥8 races** `Future.wait`.
4. **≥1 pago 4242** + **≥1** draw rifa real.
5. **≥8 classe_nova**.
6. 2 donos qty=1 = **P0/P1**. Dual bag create = reportar (P1) mesmo se EL saturou.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Sob stress: hold/stock/Hub/live coerentes. Sem oversell. Sem double claim.  
> Rifa + marketplace + bag no mesmo SKU sem 2 donos.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Hub hide sold clássico (1) · FOMO deny · 4∥2 se só residual

--------------------------------------------------
## MATRIZ (≥24)
--------------------------------------------------

### EP-A Multi-buyer hold (≥7)
A1 3 buyers insert qty=1 (só 1 wins)  
A2 2 buyers CPI∥CPI qty=1  
A3 B1 bag ∥ B2 single ∥ B3 insert mesmo SKU  
A4 favorite+hold+2.º+3.º  
A5 cancel hold → Hub restore → 2.º claim  
A6 qty hostil 99 body + JWT PATCH  
A7 cross-seller bag

### EP-B Hub / montra (≥5)
B1 sold+listed vs Hub vs insert  
B2 leftover 3→2→1 cadeia de pagos  
B3 unpublish mid-CPI + mid-tip  
B4 Hub anon vs buyer vs sellable RPC  
B5 sold Hub 0 após rifa + após pago

### EP-C Live / rifa / hitch (≥6)
C1 draw qty=1 + live_item ≠ available  
C2 winner_count=2 stock=2  
C3 draw∥CPI∥insert  
C4 hitch accept ∥ bag outro SKU  
C5 end_live∥bag∥Hub refresh  
C6 partilhar sem/com rifa + forge entry

### EP-D Bag sob stress (≥3)
D1 6∥4 (esperado fail-closed / ≤1)  
D2 expand (esperado 400)  
D3 bag pago + Hub leftover

### EP-E Caixa (≥3)
E1 pago 4242 + 2.º deny  
E2 refund∥nova compra leftover  
E3 chat card amount vs order após pago

**Total ≥24.**

--------------------------------------------------
## LENTES
--------------------------------------------------
EP1 multi-buyer · EP2 Hub · EP3 rifa · EP4 bag · EP5 race · EP6 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥24 · ≥8 classe_nova · ≥8 races · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Oversell → `FAIL_P0`.

```
AUDITOR: REDTEAM_BLIND_EP_MULTI_BUYER_STRESS_POS_OPEN_v1
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.** Demorado de propósito.
