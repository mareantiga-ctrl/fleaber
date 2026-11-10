# FROZEN_REPORT — RED TEAM CEGO V (pós T0850 / U0855)

```
AUDITOR: REDTEAM_BLIND_V_POS_TU_v1
FROZEN_AT: 2026-09-01T13:17:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [V1, V2, V3, V4, V5, V6, V7, V8]
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT (anon / B1 / S1 / B2 / S2) · `service_role` só fixture (`setup_paid_order`) / observação / cleanup. **Não se corrigiu nada.**

Pasta: `tool/redteam_blind_v_20260901T1302/`  
Evidência: `probe.json` · `pass2.json`

--------------------------------------------------
VEREDICTO
--------------------------------------------------

O fecho **«não reabrir `pago`»** segura o PATCH **directo** `enviado→pago` (`order_cannot_reopen_pago`). **Não segura o FSM.**

Comprador ou vendedor JWT, depois de `enviado` ou `entregue`, põem o pedido em `reserva_pendente` / `pendente` e, no passo seguinte, outra vez em `pago`. O `refund-order` vê `pago` (ou pré-pago) e **reembolsa o PaymentIntent Stripe TEST** (5,90 €) **depois do envio real**. `stripe_refund_id` estava **null** antes do refund; depois `re_3UAqbsH7FWYUN3jh1txirNLU`, estado `cancelado`, `amount_cents=590`.

Isto **refuta** o fecho T0850 no sentido do dinheiro: o guard é um predicado na transição `*→pago`, não uma selagem pós-envio.

Oferta qty=1, saco incompleto de conjunto, Hub produtos qty=0, oneshot de oferta e 2.º actor no pedido **aguentam** (provas em `blocked`). Não é saturação: há P0 de dinheiro + P0 de pagar menos no conjunto.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Findings **não** são a lista exacta proibida (`entregue→pago` exact, `offer_quantity_must_be_one` exact, bag incompleto exact, Hub qty=0 exact, dual Session, unlist, spoof seller, live_item mismatch exact, devolvida sem stripe, parcial 100% exact).

Controlos exactos **fechados** (não contam como finding):

| Controlo | Resultado |
|----------|-----------|
| `enviado→pago` directo | 403 `order_cannot_reopen_pago` |
| INSERT oferta qty=2 | 400 `offer_quantity_must_be_one` |
| PATCH qty após oferta | 403 `order_money_fields_immutable` |
| 2.ª order mesma oferta | 400 `offer_already_consumed` |
| Saco 2/3 do conjunto aceite | 400 bag must include all items |
| `hub_products_public` qty=0 | vazio |
| Corrida 2× INSERT oferta | 1 consumida |
| B2 PATCH/disputa/checkout pedido B1 | RLS / `order does not belong to buyer` |
| `batata_credit_wallet_once` JWT | 403 |
| INSERT `wallet_transactions` | 403 |

**ATROFIA_ABORT: não.**

--------------------------------------------------
P0 — DINHEIRO (Stripe)
--------------------------------------------------

### RTV-V1-unship + RTV-V8-refund-after-clean-hop-pago

**Lentes:** V1 + V8  
**Actor:** seller JWT (hop) · seller Edge `refund-order`  
**Pedido:** `75c2ce98-a2b6-4ef3-b39e-dcbb3303f34c`  
**PI:** `pi_3UAqbsH7FWYUN3jh1UGqe9tB` · 590 cêntimos capturados · `stripe_refund_id` **null** após o hop

**Repro**
1. Fixture Stripe TEST `setup_paid_order` → `status=pago`.
2. Seller `PATCH status=enviado` → `enviado`.
3. Seller `PATCH status=reserva_pendente` → **200**, estado `reserva_pendente`.
4. Seller `PATCH status=pago` → **200**, estado `pago`, refund_id ainda null.
5. Seller `POST refund-order` → **200**, `refund_id=re_3UAqbsH7FWYUN3jh1txirNLU`, `status=cancelado`, `amount_cents=590`.

O `already_refunded:true` na resposta do Edge é o selo de finalize/idempotência **nesta** chamada: o id de refund **não existia** no passo 4.

**Impacto:** anular Stripe **depois de enviar**. O gate `batata_order_allows_seller_stripe_refund` só olha para o status actual (`pago` / `reserva_pendente`), não para «já foi enviado».

Réplicas (mesmo root cause):

- `48c41f06-…` enviado→RP→refund `re_3UAqYtH7FWYUN3jh0dKocr87`
- `7a55d1da-…` enviado→**entregue** (buyer)→RP (seller)→refund `re_3UAqZ6H7FWYUN3jh1IWVmeiy`

Carteiras B/S **não** mexeram (61,10 / 18,97): o dinheiro sai no **cartão** Stripe TEST, não na wallet.

### RTV-V1-buyer-unship-from-enviado

**Actor:** buyer JWT  
**Pedido:** `3baa82ae-3ed2-48e1-adff-88e549113647`  
`enviado` → buyer `PATCH reserva_pendente` → **200**, `after=reserva_pendente`, PI ainda capturado (`stripe_refund_id` null). O comprador não chama `refund-order` (seller-only), mas **desfaz o selo de envio** sozinho. Conluio B+S: buyer unship + seller refund.

### RTV-V1-hop-rp-then-pago-no-refund

Dois PATCH JWT. O trigger `trg_batata_orders_guard_no_reopen_pago` só dispara quando `NEW.status='pago'` **e** `OLD.status ∈ {enviado, entregue, concluido, …}`. Com `OLD=reserva_pendente` deixa passar.

### RTV-V1-alias-unship-pendente

Seller `enviado→pendente` também 200. `pendente` não está na lista do guard nem no gate de refund.

### RTV-V1-cancelado-to-pago (P1 adjacente)

Refund **legítimo** em `pago` **antes** de enviar (fluxo que não se parte) → `cancelado`. Seller `PATCH pago` → **200**, estado `pago` **com** `stripe_refund_id` preenchido. `cancelado` não está em `order_cannot_reopen_pago`. Não se provou mint de carteira em cima (RPC parcial exige disputa + oferta; INSERT disputa em `pago` = RLS 403). Fica P1 FSM: pedido reembolsado parece outra vez `pago`.

--------------------------------------------------
P0 — PAGAR MENOS (conjunto)
--------------------------------------------------

### RTV-V4-extra-line-same-sku

**Lente:** V4  
**Actor:** buyer JWT · Edge `create-payment-intent`  
Conjunto aceite 3 SKUs, `total_eur=18,00` (40% off de 30 €). Saco **completo** + **segunda order do mesmo P1** (4 linhas, 4 unidades, catálogo 40 €).

Edge usa `Set` de `product_id`: `{P1,P2,P3}` tamanho = bundle → trata como completo → cobra **`total_eur` do conjunto de 3**.

| | Cêntimos |
|--|--|
| Catálogo 4×10 € | 4000 |
| Bundle 3 SKUs | 1800 |
| Session (`server_amount_cents`) | **1955** (1800 + portes/proteção) |

A 4.ª unidade entra quase ao preço da protecção (~1,55 €), não a 10 €.

**Não** é o fecho «saco incompleto»: o saco tem todos os ids do conjunto **mais** um duplicado.

--------------------------------------------------
P1
--------------------------------------------------

### RTV-V4-two-bundle-ids-skip-complete

Dois `bundle_id` no mesmo bag → `bundleIds.size !== 1` → **não** corre o gate de conjunto completo. Checkout **200**, `amount_cents=2165` (catálogo 2×10 € + taxas). Comprador **escolhe 2 de 3** de um conjunto aceite de 3. Paga catálogo dos 2, não o pack; fura o «tens de levar o conjunto».

### RTV-V5-live-only-inflate

Seller JWT `PATCH live_items.quantity` 1→**99** (item sem `product_id`). O tecto `live_item_qty_exceeds_product` não aplica. Reserva buyer `requested_qty=40` criada (`c7dc8fab-…`). Stock de directo inflável; não se encadeou até captura Stripe nesta ronda (P1, não P0 dinheiro).

--------------------------------------------------
P2
--------------------------------------------------

### RTV-V5-hub-live-item-qty0

`hub_products_public` esconde qty=0 (fecho U). `hub_live_items_public` **não** filtra `quantity`. Item qty=0 continua `is_active=true` / `available` no Hub de directo.

REST `products` anon neste projecto: 401 `permission denied` (não é a policy antiga).

--------------------------------------------------
LENTES (cobertura)
--------------------------------------------------

| Lente | O que se fez | Resultado |
|-------|----------------|-----------|
| V1 FSM | hop RP/pendente, buyer unship, cancelado→pago, directo `→pago` | **P0** hop; directo fechado |
| V2 disputa×refund | INSERT disputa em `pago` RLS 403; parcial `dispute_refund_offer_required`; race partial∥refund sem mint wallet | Sem double wallet+Stripe no pré-envio; P0 é o refund **pós-envio** via V1 |
| V3 oferta qty | INSERT>1, UPDATE qty, 2.ª order, checkout oferta 12 € → **1325** cêntimos | Fechado; checkout ≥ oferta |
| V4 conjunto | incompleto fechado; extra SKU; 2 bundle_id; buyer `total_eur` congelado | **P0** extra linha; P1 dois ids |
| V5 stock | Hub produtos qty=0 ok; live_only inflate; Hub live qty=0; qty→0 sem hold pago | P1 inflate; P2 Hub live |
| V6 race | 2× POST oferta; partial∥refund-order | Oferta oneshot ok; race sem Δwallet |
| V7 2.º actor | B2/S2 no pedido B1 | Fechado |
| V8 composição | unship → (pago) → `refund-order` | **P0 Stripe 5,90 €** |

Táctica Stripe TEST pago: sim (vários PI `pm_card_visa`). Contabilidade wallets + `stripe_refund_id` + stock_units. Race real: sim. REST/RPC/Edge ≠ Flutter: sim (`PATCH orders`, `refund-order`, `create-payment-intent`).

Não se partiu: compra single; envio; `refund-order` em `pago` **antes** de enviar (ainda 200); MB WAY seller `pago` não exercitado.

--------------------------------------------------
NÃO PROVADO / LIMITES
--------------------------------------------------

- Disputa aberta em `entregue` sem hop: INSERT disputa em `pago` falha RLS; não se reabriu o mint parcial pós-envio **sem** unship.
- `already_refunded:true` no JSON do Edge não nega o refund: `stripe_refund_id` passou de null → `re_…`.
- Finding `RTV-V1-buyer-unship` do `probe.json` (pedido já em `pendente`) fica **substituído** por `RTV-V1-buyer-unship-from-enviado` no pass2.
- Live `73873f9f-…` foi `ended` no `finally` do probe.

--------------------------------------------------
NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.
--------------------------------------------------
