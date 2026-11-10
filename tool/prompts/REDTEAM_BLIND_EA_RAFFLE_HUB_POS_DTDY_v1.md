# FLEABER — RED TEAM CEGO EA · DEEP · PÓS-DTDY
## Rifa / Hub / stock / convert / hitch / live_item — **quota ≥16 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DTDY: seal ao `drawn` + `live_item` **não** reabre `available` via recompute. Provar Hub/CPI/live_item; atacar multi-winner e live_only.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO` · `REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTEA-<timestamp>-` · pasta `tool/redteam_blind_ea_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**16**.
2. Oráculo multi-sítio: Hub + products + **live_item.status** + orders (± CPI).
3. **≥1** draw real com bilhetes + **≥1** pago Stripe noutro fio.
4. **≥4 classe_nova**.
5. **≥3 races** (draw∥CPI, award∥unlist, convert∥accept).
6. Residual ≥40% → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Após `drawn`: Hub 0 / hold; **live_item ≠ available** (sold/reserved/inactive).  
> live_only sem product_id também selado.  
> Atacar: winner_count>1, qty>1, draw 2×, forge winner, partilhar sem rifa, recompute após hitch.

--------------------------------------------------
## ANTI-ATROFIA (HOLD — não contar)
--------------------------------------------------
Hub hide live accepted clássico · FOMO deny · drawn seal qty=1 Hub 0 + live_item sold (1 linha reteste) · welcome OK

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥16)
--------------------------------------------------

### EA-A Draw / seal (≥5)
A1 draw qty=1 marketplace hitch → Hub 0 + live_item ≠ available (reteste DU)  
A2 draw **winner_count=2** stock=2 → Hub qty / 2.º insert  
A3 draw **live_only** (sem product_id) → live_item + leak Hub  
A4 draw 2× idempotente  
A5 JWT buyer `batata_draw_live_raffle_winners`

### EA-B Stock cross (≥4)
B1 award + draw∥CPI marketplace paralelo  
B2 after drawn: CPI / insert order nova  
B3 leftover stock=3 winners=1 → Hub lista? qty  
B4 refund/cancel premio_rifa vs Hub restore

### EA-C Convert / hitch / social (≥4)
C1 convert pending sem pago → deny  
C2 accept hitch + rifa mesmo SKU  
C3 partilhar **sem** rifa → sem bilhetes  
C4 partilhar **com** rifa + forge entry alheia

### EA-D Caixa (≥3)
D1 **pago 4242** SKU não-prémio + Hub leftover  
D2 prize_orders[] vs seal.ok  
D3 **forçar** `batata_recompute_live_item_status` (se exposto) / refresh após draw — status não volta `available`

**Total = 16.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
EA1 draw · EA2 Hub · EA3 hold · EA4 live_item · EA5 multi-winner · EA6 forge · EA7 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥16 · ≥4 classe_nova · ≥3 races · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_EA_RAFFLE_HUB_POS_DTDY_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
