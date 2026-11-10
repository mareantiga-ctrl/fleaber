# FROZEN REPORT — RED TEAM CEGO AE
## Auditor independente · PÓS-FECHO ABACAD · MARKETPLACE / CHECKOUT · v1

## CONTAGEM

```
P0 aberto: SIM          → quantos: 1
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AE_MARKETPLACE_POS_ABACAD_v1
FROZEN_AT: 2026-09-01T18:32:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AE1, AE2, AE3, AE4, AE5, AE6, AE7, AE8]
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Sessions criadas; captura PI sem `sk_test_` local) · actors JWT B1/S1/B2/S2 · `service_role` só fixture (`setup_paid_order`), observação e cleanup. Prefix `RTAE-20260901T1915-`.

Poço: os fechos ABACAD (EUR-only, reuse com moeda+montante, saco sem Session barata, stock sem inflate 1→9) **não** tapam pagar menos via `live_item` ended.

Anti-atrofia: 0/3 achados finais = lista exacta AB/Y. Variantes novas.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — SIM
2. Quantos P0: 1
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — SIM (`live_item_id` no INSERT sela `contract_unit_cents` ao preço do live_item, inclusive ended)
10. Buyer manipula qty autoritativa — NÃO (qty=2 em bundle **accepted** → `bundle_order_quantity_must_be_one`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (2.º refund idempotente)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (sem captura da Session hostil)
16. Stock=1 duas vendas válidas — NÃO (2.º INSERT `order_hold_exceeds_stock`; corrida serializada)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (holds + checkout_available)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`order_buyer_attribution_denied`)
23. Reviews forjadas — NÃO (fora do poço marketplace/checkout)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO
25. RLS crítico quebrado — NÃO (descontos seller: PATCH 200 com 0 rows)
26. Edge confia total do cliente — NÃO (`body.amount` ignorado; `currency≠eur` recusado)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — NÃO (P0 aberto; captura Stripe da Session hostil sem secret local)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P0 · AE1-STALE-LIVE-ITEM-PRICE
**Lentes:** AE1, AE8  
**Actor:** buyer JWT (o `live_item` barato é histórico do vendedor, não forjado pelo buyer)

**O quê:** No INSERT da order, o selo `contract_unit_cents` usa `live_items.price` se `live_item_id` vier no body. O Edge `create-payment-intent` cobra o contrato, **não** o catálogo `products.price`. Isto vale com o directo **ended** (`is_active=false`, `status=ended`). O buyer escolhe o `live_item` ended mais barato daquele SKU.

**Não é** `currency=jpy/usd/gbp`, reuse USD→EUR, saco barato, nem inflate 1→9.

**Prova (pass1 + pass2 + pass3):**
| SKU catálogo | live_item | live | Session `amount_total` |
|---|---|---|---|
| 40,00 € | 5,00 € | ended | **590** cents (esperado catálogo **4265**) |
| 40,00 € | — | — | 4265 cents (controlo) |
| 40,00 € | 6,00 € (vs outro ended a 25 €) | ended | **695** cents |

Order `7714f95a-608a-4d2f-8da4-681abe110cbc`: `contract_unit_cents=500`, `price_total=5`.  
Session pass1: `cs_test_a1CPJ7RKEUbL7zBMy2ROuMjikFEjqFptdjaYztsAwhp5y5mUEvjalBSGXd`.  
Replay: `cs_test_a1pVKzQ7CUBd3EtACfU5zCr01d4M6GXvJZR2TFIkb47UQho2Nd9iUeYhIt` amount 590.

**Limites:** buyer **não** cria `live_items` no live do seller (RLS). Cross-seller `live_item` → `order_live_item_product_mismatch`. PATCH `live_item_id` depois do selo **não** rebaixa (contrato 4000 cents mantém-se). Live **activa** também cobra o preço do item (pode ser o caminho live intencional); o P0 é o ended / histórico.

**Caixa:** sem `STRIPE_SECRET_KEY` `sk_test_` no ambiente local; GET settle da Session → 402 (ainda não paga). O instrumento Stripe TEST existe no montante errado (checkout URL). Captura líquida + Δwallet = **NÃO COMPROVADO** neste harness.

**Repro:**
1. SKU marketplace 40 €, listed.
2. Seller cria live + `live_items` `marketplace_product` price=5, depois `status=ended`.
3. Buyer `POST orders` com `product_id` + `live_item_id` + `live_id`.
4. `POST create-payment-intent` → Session 5,90 €.

---

### P1 · AE2-BAG-SAME-AMOUNT-DIFFERENT-LINES
**Lente:** AE2  
**Actor:** buyer JWT

**O quê:** Reuse do saco compara só `currency` + `amount_total`. Duas composições com o mesmo total (A+B vs A+C, três SKUs a 10 €) devolvem a **mesma** Session (`reused_session: true`). O settle GET usa metadata da Session original (A+B), não A+C.

**Não é** o overlap barato AB3 (montante diferente). Aqui o montante **coincide**.

**Prova:**  
A+B sid `cs_test_a10w2Yvwy8dJEJPTJT78bZaqqj2zYnmvJrzlnBwRAHQ7yDfuge90SAfAHk` amount 2165.  
A+C mesmo sid, `reused_session: true`.  
Singles cross-order (A vs B) **não** reutilizam (bloqueado).

**Impacto:** pagar a Session liquida o saco original, não o pedido A+C. Mesmo dinheiro, artigos potencialmente errados. Sem `sk_test_` não se confirmou o settle.

---

### P2 · AE2-BAG-THEN-SINGLE-ORPHAN-SESSION
**Lente:** AE2  
**Actor:** buyer JWT

Saco A+B grava a mesma Session nas duas lines (3215 cents). Checkout single de A, montante diferente → nova Session barata em A (1640); B fica com a Session do saco. Dois instrumentos Stripe abertos no mesmo contrato. Hygiene; dual-pay não encadeado (sem secret).

Orders: o4 sid `cs_test_a1hmMlZUlRnDRmY8YSvz7MigCXGHLItkFkgiTEM3KlelRFQjNEp1VCec7h` · o5 sid `cs_test_a11j0fVqbhcWPcD7Oi0KEPVcNq4SZxyz3a9k5qmumgMdRiOIfUkCCPjm4l`.

--------------------------------------------------
## FALSOS POSITIVOS (retraídos)
--------------------------------------------------

| ID pass1 | Motivo |
|---|---|
| AE3-BUYER-PATCH-BUNDLE-DISCOUNT (P0) | PATCH HTTP 200 com **0 rows**; `tier_2_pct` intacto (10). PostgREST vazio ≠ write. |
| AE3-BUNDLE-QTY2 / AE3-BUNDLE-QTY2-CHECKOUT (P1) | INSERT `status=accepted` é reescrito para **pending**. qty=2 só passou em pending. Bundle **accepted** real (seller PATCH) → `bundle_order_quantity_must_be_one`. |

--------------------------------------------------
## FECHOS ABACAD QUE AGUENTARAM (variantes novas)
--------------------------------------------------

- **AE1 moeda:** krw/inr/brl/chf/clp/vnd/xxx/euro/978/eu/vazio/cirílico/ZWSP/fullwidth/nullbyte/bool/número → `only EUR is supported`. Omitir currency → default eur OK (1325 cents num 12 €).
- **AE1 amount:** 0, 0.5, 1, 50, 500, −12, 12.00, 1e6 → Session continua 1325.
- **AE4:** hops `aguarda_pagamento` / `reservado` / `reserva_pendente` / … em order paga → status permanece `pago`. Checkout → `cannot start payment`. Seller limpar PI → `order_money_fields_immutable`.
- **AE5:** qty 2→3 com hold → `product_quantity_increase_blocked_active_order`. Dois buyers stock=1 → 2.º `order_hold_exceeds_stock`. Buyer PATCH product qty → 200 [] sem write. `is_sold` bloqueia checkout.
- **AE6:** Future.wait 2 INSERT stock=1 → 1 OK + 1 hold. 2 checkout mesma order → 1 Session (claim).
- **AE7:** B2 checkout/saco order B1 recusado. anon `Invalid checkout user`. Seller-as-buyer recusado. S2/buyer `refund-order` → Sem permissão. MB WAY sem Stripe. `prize_shipping` fake recusado. Seller INSERT order do buyer → `order_buyer_attribution_denied`.
- **AE8:** 2× refund seller → 2.º idempotente; checkout pós-refund `cancelado`.
- **AE3 conjunto accepted:** saco 8+30 com discount_pct=10 → 3656 cents (34,20 € + protecção), não o catálogo 4055. Buyer não forja `total_eur=1` (reescrito 38 € pending).

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Resultado |
|---|---|
| AE1 | **P0** live_item ended / histórico mais barato |
| AE2 | **P1** reuse saco mesmo montante linhas diferentes; **P2** Session órfã split |
| AE3 | saturado no poço (qty=2 accepted bloqueado; total forjado reescrito) |
| AE4 | capturado não reabre |
| AE5 | inflate/holds aguentam variantes ≠ 1→9 |
| AE6 | corridas serializadas |
| AE7 | B2/S2/anon/off-platform fechados |
| AE8 | refund idempotente; captura Session hostil NÃO COMPROVADO |

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ae_20260901T1915/pass1.dart` … `pass3b.dart`
- `pass1_findings.json` · `pass2_findings.json` · `pass3_findings.json` · `pass3b_findings.json`
- Cleanup holds `RTAE-20260901T1915` via `cleanup.dart` (service_role)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
