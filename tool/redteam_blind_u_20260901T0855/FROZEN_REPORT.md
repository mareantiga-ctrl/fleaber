AUDITOR: REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1
FROZEN_AT: 2026-09-01T09:10:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [U1, U2, U3, U4, U5, U6, U7, U8]
VEREDICTO: FAIL_P0

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTU-20260901T0855-`
Actors: anon (negativo) · buyer JWT · seller JWT · buyer2 · seller2
service_role: só fixture/observação (setup_paid_order, setup_paid_bag, SELECT)
Pasta: `tool/redteam_blind_u_20260901T0855/`

--------------------------------------------------
MISSÃO
--------------------------------------------------
No marketplace (anúncio, saco, oferta, conjunto, checkout), o comprador consegue
pagar menos do que o catálogo / conjunto completo, ou o vendedor confirma MB WAY
sem prova e o stock some.

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### RTU-U2-bundle-partial-bag · P0 · U2/U8

**Título:** Checkout do conjunto cobra `product_bundles.total_eur` sem exigir todos os artigos no saco.

**Actor:** buyer JWT

**Pré:** conjunto aceite com 3 SKUs (20 € + 1 € + 1 €), `discount_pct=50` → `total_eur=11`. Uma única encomenda do artigo de 20 € com `bundle_id` desse conjunto.

**Repro:**
1. Buyer INSERT `product_bundles` com os 3 `product_ids`.
2. Seller PATCH `status=accepted`, `discount_pct=50`.
3. Buyer INSERT `orders` só no SKU de 20 € com `bundle_id`.
4. POST `create-payment-intent` `bag_checkout=true` com essa única linha.

**Esperado:** cobrar o catálogo da(s) linha(s) no saco (20 € + protecção) **ou** recusar saco incompleto.

**Obtido:** Session Stripe TEST `cs_test_a1sQnlfCdPmNbx4tEtqWyTTkv9wr7nXEZKCvjn39ccaMC5Ogi69vCJZsDS`
- `server_amount_cents` = **1220** (11,00 € itens + 1,20 € protecção)
- catálogo do artigo no saco = **2000** cêntimos
- order `09d1ae07-641b-4c97-bf50-de9b0f38ee60`: `contract_unit_cents=2000` (selo correcto) mas o bag **ignora o contrato** e redistribui `total_eur=11`
- bundle `5b5df00d-6fb3-45a3-8930-e9168486663c` status=accepted, 3 product_ids

**Impacto:** pagar o preço de um conjunto com desconto levando só o artigo caro. Os dois baratos ficam no anúncio. Δ ≈ 8 € neste fixture; escala com o desconto e o artigo omitido.

**Não capturado** (Session criada, 4242 não liquidado) — o montante da Session é o que o Stripe cobraria.

---

### RTU-U8-offer-qty-checkout · P0 · U2/U8

**Título:** Oferta aceite de 1 unidade aplica-se a `quantity=N` no contrato e na Session.

**Actor:** buyer JWT (seller só aceita a oferta a 6 €)

**Pré:** SKU 25 €, stock 4. Oferta buyer 6 € aceite. `offer_quantity_must_be_one` **não** está na função `batata_orders_seal_contract` actual (última rewrite 20260830160000).

**Repro:**
1. POST `product_offers` amount=6, offered_by=buyer.
2. Seller PATCH `accepted`.
3. POST `orders` `quantity=3` `product_offer_id=<id>`.
4. POST `create-payment-intent`.

**Esperado:** recusar qty>1 na oferta **ou** selar 25 € × 3.

**Obtido:** order `ba60d4f8-8424-499f-aee0-be254676b40b`
- `contract_unit_cents=600`, `contract_qty=3`, `quantity=3`
- `price_total=19.55`
- Session `cs_test_a14RoqrBOnYJODZoUcMojUgtMA75ped5XgzNJMyQQsnp41VYLAn7RhICYS` **1955** cêntimos
- catálogo 3×25 € = **7500** cêntimos
- produto continua `price=25`, `quantity=4` (hold de 3)

**Impacto:** 19,55 € em vez de 75 € + protecção. Cadeia completa até Session Stripe (não liquidada).

---

### RTU-U5-mbway-seller-pago-stock · P2 · U5

**Título:** Vendedor marca MB WAY `pago` sem `proof_url`; stock decrementa; `completed_at` preenchido.

**Actor:** seller JWT

**Pré:** order `274ac914-4019-45f0-8d47-dfb79e3553b5` `reserva_pendente`, `payment_method=MB WAY`, sem Stripe.

**Repro:** PATCH `orders.status=pago` (seller).

**Esperado (lente):** recusar sem prova, ou não aplicar stock de plataforma.

**Obtido:** `status=pago`, `amount_paid_cents=null`, `proof_url=null`, `stock_units_applied=1`, `completed_at` set, produto 2→1 unidades, Δwallet vendedor = 0. Buyer não consegue marcar `pago` nem `concluido`. `refund-order` → `skipped: not_seguro_fleaber`.

**Nota:** fluxo off-platform «o vendedor confirma que recebeu». Não minta carteira. Documentado porque a lente U5 o exige; não é desvio Stripe.

--------------------------------------------------
FALSOS POSITIVOS (retraídos)
--------------------------------------------------
- `RTU-U1-unlist-alheio` e `RTU-U7-buyer-price`: PATCH buyer devolveu **200 []** (0 linhas). RLS não actualizou. Não são findings.

--------------------------------------------------
DEFESAS QUE AGUENTARAM (amostra)
--------------------------------------------------
U1: qty 9999 / 99 vs stock 2 → `order_hold_exceeds_stock`. PATCH quantity → `order_money_fields_immutable`. Bag dois vendedores → recusado.
U2: INSERT oferta `accepted` forçada a pending. Self-accept não passou (índice/pending). Oferta com `expires_at` passado → `offer_expired` no accept. Buyer não altera `total_eur` do conjunto aceite.
U3: body `amount=1` ignorado (quote 1693 = 12 € + 3,50 € + protecção). Portes do selo transportadora prevalecem sobre `shipping_method=mao`. `prize_shipping` marketplace bloqueado. GET session inventada 400. `fase2_e2e_settle` com JWT → 401.
U4: 2 buyers última unidade → 1 hold. hold∥sold → insert recusado `order_hold_product_sold`. checkout∥unlist → Session recusada `product is not listed`.
U5: Stripe em MB WAY bloqueado. Buyer `pago`/`concluido` revertidos.
U6: cancel pós-pago Stripe bloqueado (fica `pago`). `refund-order` buyer → 403. Refund seller idempotente. Wallet INSERT buyer → RLS deny.
U7: compra Stripe TEST: order `c73842ae-b5ca-4772-ac6f-557a74f4efdc` `pago`, PI `pi_3UAmfKH7FWYUN3jh1ydx3Dfw` 590 cêntimos, `stock_units_applied=1`, produto qty 2→1. `setup_paid_bag` ok (PI 1115 cêntimos, linhas proporcionais).

Compra legítima single-item e saco multi-SKU **não** partiram.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Checkout Stripe TEST pago marketplace: sim (`setup_paid_order` + `setup_paid_bag`).
2. Contabilidade fechada: stock · PI · status · wallets na compra legítima e no refund idempotente.
3. Race `Future.wait`: 2 buyers última unidade; hold∥sold; checkout∥unlist.
4. MB WAY: sim (seller pago / buyer bloqueado / refund skipped).
5. Compra legítima e envio correcto: não alterados (refund seller só em fixture U6).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Findings P0 ≠ dual Session, unlist exact, preço no body da Session, oversell última unidade exact, wallet INSERT, cancel hold, review 5★.
0/2 P0 na lista de atrofia.

--------------------------------------------------
NÃO FEITO / LIMITES
--------------------------------------------------
- Sessions hostis **não** liquidadas com 4242 (prova no quote servidor / Session amount).
- Live+marketplace no mesmo SKU: hold marketplace criado; sem live_item activo (fora do poço live bag Q/T).
- Produção não tocada. Fase 4 não iniciada. Código de produto **não** corrigido.

Evidência: `probe.json`, `pass2_observe.json`, este ficheiro.
