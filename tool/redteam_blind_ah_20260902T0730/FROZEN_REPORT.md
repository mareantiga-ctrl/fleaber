# FROZEN_REPORT — RED TEAM CEGO AH
## Marketplace / checkout · PÓS-FECHO AEAFAG · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 2
P2 aberto: NÃO          → quantos: 0
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito)
```

```
AUDITOR: REDTEAM_BLIND_AH_MARKETPLACE_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T07:45:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AH1, AH2, AH3, AH4, AH5, AH6, AH7, AH8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`cs_test_`) · actors JWT B1/S1/B2/S2 · `service_role` só fixture, observação e cleanup. Prefixo `RTAH-20260902T0730-`. Sem `sk_test_` no ambiente local — captura PI não clicada; prova P1 = Session emitida + SPA Checkout viva + BD incoerente + GET settle 402 (não pago).

**Não é ATROFIA_ABORT:** 0/2 achados = lista exacta AE1-STALE-ENDED / AE2-BAG-SAME-AMOUNT (reuse) / AE2-BAG-THEN-SINGLE / AB3 currency / AB5 qty 1→9 / Y2 bundle qty>1. Variantes novas: bag→bag montantes diferentes; single→bag (inverso); race bag dual `cs_`.

NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — NÃO (o dual-`cs_` está classificado P1 porque o URL de pagamento continua vivo)
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (contrato selado; PATCH `contract_unit_cents` 42501)
10. Buyer manipula qty autoritativa — NÃO (PATCH qty 42501)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (não se capturou)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito desta ronda)
16. Stock=1 duas vendas válidas — NÃO (2.ª order B2 recusada no INSERT; inflate seller 42501)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO (B2 checkout order B1 400)
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (seller checkout 400; S2 refund 403)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO nesta ronda
25. RLS crítico quebrado — NÃO (`product_offers` INSERT buyer 403)
26. Edge confia total do cliente — NÃO (`body.amount` ignorado; quote da order)
27. Regressão funcional (happy path partido) — NÃO (bag permutado reutiliza; conjunto accepted full quote 2522¢ = 23,40€+protecção)
28. Saturação atingida — NÃO (P1 Session aberto)

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P1-1 · AH2 · `AH2-BAG-RECOMPOSE-ORPHAN` + `AH2-SINGLE-THEN-BAG-ORPHAN`

**Lente:** AH2 Session / saco (também AH8: Sessions incoerentes).

**Buraco:** no POST `create-payment-intent`, o ramo **saco** quando a Session anterior não faz match (currency / `amount_total` / `bag_order_ids`) faz `continue` **sem** `stripe.checkout.sessions.expire`. O ramo **single** chama `expireSharedBagCheckoutSession`, que **return imediato se não for bag**. Resultado: Session antiga fica `open` e pagável.

Isto **não** é o exacto AE2-BAG-THEN-SINGLE (saco→single) nem AE2-BAG-SAME-AMOUNT (reuse pelo montante). O reuse por `bag_order_ids` ordenados **funciona** (A,B vs B,A → `reused_session=true`, mesmo `cs_`). O que falta é **expirar** a Session que já não serve.

**Repro A — saco A+B depois A+C, montantes diferentes (novo):**
1. Buyer JWT: 3 orders marketplace mesmo seller (12€, 13€, 21€, mão).
2. `bag_checkout` A+B → `cs_test_a1mMqkh3eWr0dNRkNq7aDeqtQ7jT7pRIAdlG1olC8yu1rjmv2a85wJ56T7` · `amount_total=2690`.
3. `bag_checkout` A+C → `cs_test_a1vDCqYfpR11GL4ZUUX2GFcoCYPvnzPmmUK3Va264aIQA04ME3FJOjXcWQ` · `amount_total=3530` · `reused_session=false`.
4. BD (service GET): A e C → S2; **B continua S1**.
5. GET `https://checkout.stripe.com/c/pay/{S1}` e `{S2}`: HTTP 200, SPA `App--classic`, 552 890 bytes, `live_spa=true` (não página tiny expired).
6. GET Edge `checkout_return=success&session_id=S1` → **402** «Pagamento ainda não confirmado» (Session existe, não paga).

**Repro B — single depois saco (inverso do fecho bag→single):**
1. Checkout single D → `cs_test_a1ucgqkwJTrhjmaQodiAJXfYNSEahkYAh2R9ckMLmRwYkawDz0NfJtjk0R`.
2. `bag_checkout` D+E → `cs_test_a1xTwas3BU22CkL3OLhSmAZcnnvrTT8LMbSzSxx0viwpXJN89oNwnov4Rr`.
3. BD: D e E apontam para S2; SPA de S1 continua `live_spa=true`.

**Impacto:** duas (ou mais) Checkout Sessions Stripe TEST abertas para conjuntos diferentes ou para single+saco. Quem pagar o URL antigo liquida o **saco/order da metadata S1**, não o pedido actual na app. Sem `sk_test_` local não se confirmou settle `pago` nem Δwallet — por isso **P1 caminho**, não P0 captura.

**Pass1 extra (mesma raiz):** A+B vs A+C **mesmo** montante 2165¢ → dois `cs_` distintos, `reused=false` (fecho AE2-SAME-AMOUNT no reuse **ok**; expire continua em falta).

---

### P1-2 · AH6 · `AH6-BAG-RACE-TWO-OPEN`

**Lente:** AH6 Race (+ AH2).

**Buraco:** saco chama `batata_claim_checkout_session_slot` em cada linha mas **ignora** `action=reuse|wait` e cria sempre `checkout.sessions.create` se o loop de reuse fez `continue`. Em POST paralelo, duas criações passam.

**Repro:**
1. `Future.wait` 2× `bag_checkout` nas mesmas 2 orders.
2. Single paralelo na mesma order → **1** `cs_` (claim single ok).
3. Bag paralelo → 2 ids:
   - `cs_test_a1lpfOLQBeyrf8SiGGooIUEig9en38YwceR5pAmX4d7AGNok3xL4HY8tmH`
   - `cs_test_a1lWIVUm1AhW4mYpzvEIkxi948yDmrjUFtpgJu2B0XZqTf2dqq7jkYCUyh`
4. Ambos SPA `live_spa=true`. GET settle num deles → 402.

**Impacto:** duas Sessions pagáveis do **mesmo** saco. Caminho de dupla captura se ambos forem pagos antes do settle liquidar; defesa pós-captura (`refundOrphanDuplicatePaymentIntent`) existe no código mas **não foi exercida** (sem PI succeeded). P1, não P0.

--------------------------------------------------
## LENTES — o que fechou nesta ronda
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| AH1 Preço | **Fechado para variantes novas.** Live ainda activa: PATCH `live_items.price` 18→1, checkout 1955¢ = selo 1800+protecção. Catálogo 25→1 → 2690¢ selo 2500. JWT PATCH contract/qty → `order_money_fields_immutable`. INSERT `contract_unit_cents=50` → selo 3000. PATCH `live_item_id` hi→lo não baixa quote. PATCH JWT shipping carrier→mão **não persiste** (BD continua transportadora; checkout 2008¢ carrier). Oferta JWT buyer INSERT 403 RLS. |
| AH2 | **P1 aberto** (acima). Permutação A,B / B,A **reutiliza**. |
| AH3 | **Fechado** quando o conjunto está mesmo `accepted`. Pass1 «parcial» era falso: JWT buyer INSERT força `pending`. Seller cria pending + PATCH `accepted` (total 23,40€) → bag 1/2 SKUs **400** `bag must include all items`. Bag completo **2522¢**. B2 no bundle B1 **400**. PATCH `total_eur=1` não baixa (26,00 / selo catálogo). Mix 2 `bundle_id` não retestado após 502; insert service 2 bundles não chegou a finding. |
| AH4 | **Fechado.** Order fixture `pago`+PI → 400 `cannot start payment`. |
| AH5 | **Fechado nas variantes novas.** Seller qty 1→9 com hold → `product_quantity_increase_blocked_active_order`. 2.ª order B2 em stock=1 → INSERT falhou. Qty=5 com stock=5 é contrato válido (3740¢), não inflate. |
| AH6 | **P1 aberto** bag paralelo. Single paralelo **1** Session. |
| AH7 | **Fechado.** B2/anon/seller checkout bloqueados. Buyer e S2 `refund-order` 403. |
| AH8 | Observação: wallets B1 61,10 / S1 17,97. Sem captura nesta ronda → Δ não aplicável. GET settle 402 confirma Sessions não pagas. |

--------------------------------------------------
## O QUE NÃO SE PROVOU (lacuna honesta)
--------------------------------------------------

- Pagar S1 órfã com cartão TEST até `orders.status=pago` + stock + Δwallet (sem `sk_test_` local).
- Dois PI succeeded no race bag (dupla captura líquida vs refund órfão).
- `bag_orders_json` legado vs compact keys no settle (metadata é escrita pela Edge, não pelo JWT).

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ah_20260902T0730/_rtah.dart`
- `tool/redteam_blind_ah_20260902T0730/pass1.dart` + `findings.json`
- `tool/redteam_blind_ah_20260902T0730/pass2.dart` + `pass2_findings.json`
- `tool/redteam_blind_ah_20260902T0730/pass3.dart` + `pass3_findings.json`
- `tool/redteam_blind_ah_20260902T0730/settle_probe.dart` + `pass3_settle.json`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
