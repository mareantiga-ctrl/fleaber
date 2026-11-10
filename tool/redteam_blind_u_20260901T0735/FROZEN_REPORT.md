# FROZEN_REPORT — RED TEAM CEGO U

```
AUDITOR: REDTEAM_BLIND_U_MARKETPLACE_CHECKOUT_v1
FROZEN_AT: 2026-09-01T06:45:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [U1, U2, U3, U4, U5, U6, U7, U8]
VEREDICTO: FAIL_P1
```

**Poço:** marketplace (anúncio, saco, oferta, conjunto, checkout Stripe TEST, MB WAY, stock). Sem live bag, sem payout, sem identidade. Staging `fxdknzrqjenzqcvnwqqq`. Sem produção. Sem Fase 4. Sem correcções.

**Prefixo fixtures:** `RTU-20260901T0735-` / títulos `RTU-20260901T0735 *`.

**Provas:** `tool/redteam_blind_u_20260901T0735/probe.json` · `pass2.json` · este ficheiro.

--------------------------------------------------
MISSÃO
--------------------------------------------------

No marketplace, o servidor cobra o catálogo (e os escalões da loja), não o `total_eur` do conjunto aceite; o saco abre duas Checkout Sessions sem claim; o desconto de conjunto corta outra vez um contrato já selado por oferta. Não se provou pagar menos via `body.amount`, oversell da última unidade, mint de carteira MB WAY, nem refund pelo comprador.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------

| Obrigatório | Resultado |
|---|---|
| ≥1 Stripe TEST **pago** marketplace | `setup_paid_order` → `0513b88e-…` status `enviado`, PI `pi_3UAlPBH7FWYUN3jh0KCzleGl`, `amount_paid_cents=590` |
| Contabilidade por order | stock 3→2, `stock_units_applied=1`, wallets Δ=0 até receção (esperado); saco pago `setup_paid_bag` PI `pi_3UAlPGH7FWYUN3jh1v50Hx1N` 1115 cêntimos, refund linha A não derruba B |
| ≥1 race `Future.wait` | qty=2∥qty=2 stock=3 (serializou); checkout∥unlist (Session recusada); accept conjunto∥unlist; 2× bag POST |
| ≥1 MB WAY / mão | seller marca `pago` sem prova; stock 2→1; `amount_paid_cents` nulo; Δwallet=0; buyer `concluido` em mão após pago |
| Compra legítima single | pago→mão→enviado **não partido** |

--------------------------------------------------
FINDINGS (provados)
--------------------------------------------------

### RTU-U2-bundle-total-ignored — P1 — U2 / U3 / U8

**O quê:** o checkout Stripe do saco **ignora** `product_bundles.total_eur` do conjunto aceite. Cobra catálogo + protecção, mesmo com 50% gravado no conjunto.

**Actor:** buyer JWT `create-payment-intent` `bag_checkout=true`.  
**Pré:** `seller_bundle_discounts.enabled=false`; vendedor PATCH `discount_pct=50` + `status=accepted`. Bundle `0998a6f8-…`: `subtotal_eur=40`, `total_eur=20`. Orders seladas a `contract_unit_cents=2000` (catálogo), `price_total=20` cada (selo JWT, não o rateio do conjunto).

**Repro:**
1. Dois SKUs 20€ listados.
2. Buyer INSERT `product_bundles` (trigger zera `discount_pct` no INSERT do buyer).
3. Seller PATCH `discount_pct=50`, `status=accepted` → `total_eur=20`.
4. Buyer INSERT 2 orders `bundle_id` + `bag_checkout`.

**Esperado:** Session ≈ 20€ itens + protecção (2165 cêntimos).  
**Obtido:** `server_amount_cents=4265` (40€ + 2,65€ protecção). Session `cs_test_a12JaVWg81mksPP15ZAzdvpFCMVvwZFsFJVJV4inPmfmnBJHofQhsxvntC`.

**Impacto:** comprador paga o dobro do conjunto aceite se a loja tiver escalões desligados (ou diferentes). O Edge usa só `seller_bundle_discounts`, não o contrato do conjunto. Flutter `payAcceptedBundle` manda `amount=sum(price_total)` mas o servidor ignora o body — e `price_total` já foi selado ao catálogo no INSERT.

**Não é** «preço no body da Session»: o body 2000 cêntimos também foi ignorado; o buraco é a fonte de verdade (tabela de escalões vs `product_bundles`).

---

### RTU-U2-offer-bundle-stack — P1 — U2 / U8

**O quê:** com ofertas aceites a 10€ (catálogo 20€) **e** `seller_bundle_discounts` 50% no par, o saco cobra **10€ itens + protecção**, não os 20€ da oferta nem os 20€ de 50% sobre catálogo.

**Obtido:** `server_amount_cents=1115` (= 10,00€ + 1,15€ protecção). Sem stack seria 2165.

**Impacto:** segundo corte sobre contrato já negociado. Conluio seller+buyer consegue ~25% do catálogo; também acontece se o vendedor usa ofertas **e** escalões ao mesmo tempo sem o Edge os isolar.

---

### RTU-U3-bag-dual-session — P1 — U3 / U1 / U8

**O quê:** `batata_claim_checkout_session_slot` corre só no checkout **single** (`if (!isBagCheckout)`). Dois POST `bag_checkout` no mesmo par de orders criam **duas** Checkout Sessions abertas.

**Obtido:**
- `cs_test_a12JaVWg81mksPP15ZAzdvpFCMVvwZFsFJVJV4inPmfmnBJHofQhsxvntC`
- `cs_test_a1RYBmJAvarVyYujybOriIc1t5mAYDQLmu7a1FQkBFXyKsENMBOYQajMjy`

Pass 2: as orders do conjunto `0998a6f8-…` ficam `reserva_pendente` com `stripe_checkout_session_id=null` (o saco não grava o `cs_` na row). Não há reuse via BD.

**Impacto:** duas URLs Stripe vivas para o mesmo saco. Captura dupla não foi fechada com 4242 nas duas Sessions (só quote). Residual: se as duas forem pagas, o settle `forSettle` pode marcar pago duas vezes / segundo PI órfão. **Não** é o dual-Session clássico de uma order single (esse tem claim).

---

### RTU-U2-bundle-accept-unlist-race — P2 — U2

**O quê:** `Future.wait` accept conjunto ∥ unlist de um membro → bundle `a73c7113-…` fica `accepted` (`total_eur=25.2`) com SKU `22860323-…` `list_on_marketplace=false`.

**Pass 2:** hold do SKU unlistado → `order_hold_product_not_listed`. O outro membro ainda lista e segura hold. Sem Session no par morto.

**Impacto:** estado aceite mentiroso (conjunto «fechado» com artigo morto). Não se comprou stock unlistado. P2 de máquina de estados, não de caixa.

---

### RTU-U7-hub-qty0-ghost — P2 — U7

**O quê:** `hub_products_public` não tem `quantity`. SKU `1b7cba91-…` `quantity=0`, `is_sold=false`, `list_on_marketplace=true` aparece no Hub (JWT e anon). Hold JWT → `order_hold_exceeds_stock`.

**Impacto:** vitrine mentirosa (Início/Hub vs stock efectivo). Sem compra. A view declara «sem stock interno» — o anúncio continua público.

--------------------------------------------------
RETRAÍDO (falso positivo pass 1)
--------------------------------------------------

**RTU-U1-unlist-alheio:** PATCH buyer `list_on_marketplace=false` → HTTP 200 `[]`. Pass 2: SKU `e519379d-…` continua `list_on_marketplace=true`. No-op RLS, não unlist.

--------------------------------------------------
BLOQUEADO (amostra — não atrofia)
--------------------------------------------------

| ID | Lente | Resultado |
|---|---|---|
| qty=99 / qty=0 | U1 | `order_hold_exceeds_stock` / `invalid_order_quantity` |
| race B1 qty=2 ∥ B2 qty=2 stock=3 | U1 / U4 | 1 hold; 2.º 23514 (variante last-unit, serializou) |
| PATCH quantity | U1 | `order_money_fields_immutable` |
| bag 2 sellers | U1 | `bag lines must share one seller` |
| B2 paga order B1 | U1 | `order does not belong to buyer` |
| 2 holds mesmo SKU stock=1 | U1 | 2.º recusado |
| self-accept oferta | U2 | `offer_accept_not_authorized` |
| accept após unlist | U2 | `offer_product_not_listed` |
| accept `expires_at` passado | U2 | `offer_expired` |
| 2.ª order mesma oferta | U2 | `offer_already_consumed` |
| oferta 0,01€ checkout | U2 | `item without price` (<50 cêntimos); hold **cancelável** |
| `body.amount=50` | U3 | quote 1325 (12€+prot) |
| JWT `contract_unit_cents=1` | U3 | selo 1200 |
| `prize_shipping` marketplace | U3 | `not a raffle prize` |
| checkout ∥ unlist | U3 | Session recusada `product is not listed` |
| custom_tiers pct=99 | U8 | Edge `Math.min(50,pct)` → 2165 |
| B marca pago / concluido cedo | U5 | 200 mas status **não** muda (trigger) |
| S marca MB WAY pago | U5 | **permitido**; stock desce; wallet 0; `amount_paid_cents` null |
| 2 holds MB WAY stock=1 | U5 | 2.º recusado |
| cancel pós-pago | U6 | status permanece `pago` |
| refund-order buyer / S2 | U6 | 403 Sem permissão |
| refund linha A saco | U6 | B continua `pago`; stock B intacto; 2.º refund idempotente |
| envio vendedor pós-pago | U8 | `enviado` OK |

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Lista proibida (dual Session **single**, bag unlist exact, preço body Session, last-unit exact sem variante, wallet INSERT, cancel hold, review 5★): **0 findings**. Findings = conjunto≠checkout, stack oferta+escalão, dual Session **saco** (sem claim), Hub qty=0, race accept+unlist (P2).

`ATROFIA_ABORT`: não.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Coberta | Caixa |
|---|---|---|
| U1 saco/qty | sim | holds/qty/cross-seller/steal bloqueados; dual Session no saco → U3 |
| U2 oferta/bundle | sim | **P1** total_eur ignorado; **P1** stack; P2 accept+unlist |
| U3 Stripe quote | sim | body/contrato/prize bloqueados; **P1** dual bag Session |
| U4 oversell v2 | sim | variante qty=2 stock=3 serializou; live_item no SKU held falhou NOT NULL (ended live) |
| U5 MB WAY | sim | pago seller sem prova = negócio; sem mint; stock desce |
| U6 cancel/refund | sim | pós-pago/JWT alheio/linha saco OK |
| U7 cross-superfície | sim | **P2** Hub qty=0; preço Hub segue catálogo após PATCH 1€ |
| U8 composição | sim | Δwallet 0 no MB WAY e no Stripe até receção; stack 1115 cêntimos |

--------------------------------------------------
NÃO FECHADO
--------------------------------------------------

- Captura 4242 nas **duas** Sessions do saco (duplo settle).
- Oversell live+marketplace no mesmo SKU com live **activa** (só lives `ended` no seller de teste; INSERT `live_items` 23502).
- Stripe Session JWT paga com cartão 4242 (pago via e2e PI TEST, equivalente caixa).

--------------------------------------------------
VEREDICTO
--------------------------------------------------

**FAIL_P1** — o conjunto aceite não é a fonte de verdade do Stripe; o saco não reclama Session; ofertas e escalões acumulam. Sem P0 de oversell/wallet/unlist alheio neste poço.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
