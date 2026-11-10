# FROZEN_REPORT — RED TEAM CEGO DJ

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0

```
1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1
FROZEN_AT: 2026-09-06T15:16:40Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DJ1, DJ2, DJ3, DJ4, DJ5, DJ6, DJ7, DJ8]
probes_na_tabela: 16
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDJ-20260906T1609
staging: fxdknzrqjenzqcvnwqqq
```

Exactos residual **não contados** (HOLD): welcome · `voou tudo` deny · follow unpublished · tip mid-live unpaid.  
A1 welcome **OK**. A2 «directo a começar» **OK**. Stock / hitch / convert / rifa **sem oversell**.

---

## Missão

Stock live **não** oversell. Convert **só** com PI pago próprio. Rifa/follow tickets só published. Welcome allowlist OK; FOMO free-text deny.

**Resposta:** Allowlist DBDG: welcome e «O directo está a começar» visíveis no Hub (buyer + anónimo). `voou tudo` → `purchase_announce_via_broadcast_only`. Duas reservas na mesma unidade qty=1: 1 `accepted`, 2º `qty_exceeds_stock`. Qty pedida 5 clamp a 1. Hitch marketplace+live_only: 2º `qty_exceeds_stock`. Insert após `ended` → `live_ended`. Convert sem PI / PI alheio / pós-unpublish → `convert_requires_paid_order` (RPC stripe_convert revoke). Follow unpublished RLS 403, 0 tickets; follow published 201 + 1 ticket. Playback unpublished 403 table lives. Tip mid-live Session TEST `pending`, Δ wallet 0.

---

## Findings abertos

Nenhum. `findings: []`.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| DJ1 | A1 `Bem-vindos ao directo!` | `ok:true` + Hub buyer/anon visível |
| DJ1 | A2 `O directo está a começar` | `ok:true` + Hub buyer/anon visível |
| DJ2 | A3 `voou tudo` | `purchase_announce_via_broadcast_only` |
| DJ3/DJ7 | B1 2 buyers mesma unidade accept∥accept | r1 accepted; r2 pending; 400 `qty_exceeds_stock`; n_accepted=1 |
| DJ4 | B2 qty=5 em item qty=1 | clamp `requested_qty=1`; accept OK qty=1 |
| DJ7 | B3 accept∥reject | estado único `accepted`; ≠converted |
| DJ7 | B4 end_live ∥ accept | accept ganhou; live `ended`; status≠converted |
| DJ4 | B5 reserve após ended | POST 403 `live_ended` |
| DJ3 | B6 hitch mkt+live_only qty=1 | 2º 400 `qty_exceeds_stock` |
| DJ5 | C1 convert sem PI | RPC 403 function denied; PATCH 403 `convert_requires_paid_order`; status=accepted |
| DJ5 | C2 reconcile PI liveA/B1 → res liveB/B2 | 403 `convert_requires_paid_order` |
| DJ5 | C3 PATCH converted após unpublish+end | 403 `convert_requires_paid_order` |
| DJ6 | C4 follow unpublished + rifa | RLS 403; tickets=0 |
| DJ6 | C4 follow published + rifa | 201; tickets=1 |
| DJ8 | C5 GET lives playback unpublished | 403 table lives |
| DJ5 | C6 tip mid-live residual | `cs_test` pending; dWallet=0 |

---

## TABELA DE PROVAS

| # | probe_id | poço | payload | RPC/HTTP | stock/BD | HOLD\|FAIL\|SKIP |
|---|----------|------|---------|----------|----------|------------------|
| 1 | A1.welcome | DJ-A | `Bem-vindos ao directo!` | 200 `ok:true` | Hub buyer+anon VISIBLE | HOLD |
| 2 | A2.directo.comecar | DJ-A | `O directo está a começar` | 200 `ok:true` | Hub buyer+anon VISIBLE | HOLD |
| 3 | A3.voou_tudo | DJ-A | `voou tudo` | 200 `purchase_announce_via_broadcast_only` | n/a | HOLD |
| 4 | B1.two_buyers.same_unit | DJ-B | 2 buyers hitch unidade qty=1 accept∥accept | 200 accepted \| 400 `qty_exceeds_stock` | n_accepted=1; r2 pending | HOLD |
| 5 | B2.hitch.qty_gt_avail | DJ-B | requested_qty=5 item qty=1 | 200 accepted qty=1 | clamp 5→1 | HOLD |
| 6 | B3.accept_reject.parallel | DJ-B | accept ∥ reject | 200 \| 200 | status=accepted | HOLD |
| 7 | B4.end_live.parallel_accept | DJ-B | end_live ∥ PATCH accepted | 200 \| 200 ended | res accepted; live ended; ≠converted | HOLD |
| 8 | B5.reserve.after.ended | DJ-B | POST reservation após ended | 403 `live_ended` | insert_id=null | HOLD |
| 9 | B6.hitch.mkt_live_only | DJ-B | hitch marketplace+live_only SKU qty=1 | 400 `qty_exceeds_stock` | m accepted; l pending | HOLD |
| 10 | C1.convert.nopi | DJ-C | RPC stripe_convert + PATCH converted sem PI | 403 function denied \| 403 `convert_requires_paid_order` | status=accepted | HOLD |
| 11 | C2.convert.pi_alheio | DJ-C | reconcile PI liveA B1 → res liveB B2 | 403 `convert_requires_paid_order` | dst accepted | HOLD |
| 12 | C3.convert.after.unpublish | DJ-C | PATCH converted após hub unpublish + live ended | 403 `convert_requires_paid_order` | status=accepted | HOLD |
| 13 | C4.raffle.follow.unpublished | DJ-C | B2 follow S2 unpublished + rifa active | 403 RLS follows | tickets=0 | HOLD |
| 14 | C4.raffle.follow.published | DJ-C | B2 follow S1 published + rifa active | 201 | tickets=1 | HOLD |
| 15 | C5.buyer.playback.unpublished | DJ-C | GET lives playback/mux/livekit unpublished | 403 table lives | n/a | HOLD |
| 16 | C6.tip.mid_live | DJ-C | create-live-tip-checkout mid-live €2 sem pay | 200 `cs_test` checkoutUrl | tip pending; dWallet=0 | HOLD |

`probes_na_tabela: 16`. Residual HOLD não contados: A1 welcome · A3 `voou tudo` · C4 unpublished · C6 tip unpaid = 4 / 16 = 25%. A1 welcome OK. ≥1 race hitch/accept/end: B1 + B3 + B4.

---

## Lentes (≥6/8)

| ID | Resultado |
|----|-----------|
| DJ1 welcome | HOLD — A1+A2 visíveis no Hub |
| DJ2 FOMO deny | HOLD — `voou tudo` deny |
| DJ3 hitch | HOLD — B1 + B6 2º `qty_exceeds_stock` |
| DJ4 stock | HOLD — clamp qty; insert pós-end `live_ended` |
| DJ5 convert | HOLD — sem PI / PI alheio / pós-unpublish |
| DJ6 rifa | HOLD — unpublished 0 tickets; published 1 ticket |
| DJ7 race | HOLD — accept∥accept, accept∥reject, end∥accept sem caixa |
| DJ8 Mux | HOLD — REST 403 table lives |

---

## Anti-atrofia

Residual HOLD (welcome + `voou tudo` + follow unpublished + tip unpaid) = 4 / 16 = 25% (< 50%). **Não** `ATROFIA_ABORT`.  
Matriz stock/hitch/convert/rifa **não** é chase FOMO. Sem exactos DB→DG como FAIL.

---

## Saturação

Tabela ≥14 · sem oversell · convert locked · P0–P2=0 → **PASS_CEGO_SATURADO**.

```
AUDITOR: REDTEAM_BLIND_DJ_LIVE_STOCK_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 16
VEREDICTO: PASS_CEGO_SATURADO
```

**NÃO CORRIGIR.**
