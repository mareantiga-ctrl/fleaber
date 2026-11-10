# FROZEN_REPORT — RED TEAM CEGO G (TEMPO / RACE / REPLAY / ESTADO VELHO)

```
AUDITOR: REDTEAM_BLIND_G_TEMPO_v1
FROZEN_AT: 2026-08-31T12:15:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [G1, G2, G3, G4, G5, G6, G7, G8, G9]
VEREDICTO: FAIL_P1
prefixo_fixtures: RTG-20260831T1253-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas em `tool/redteam_blind_g_20260831T1253/pass{1,2,3,4,5}.json`.

---

## Veredicto

O sistema **aguenta** a maior parte das corridas de dinheiro clássicas (duas Sessions em paralelo no mesmo hold, último stock qty=1, refund Stripe idempotente, webhook sem assinatura, GET settle de Session fake, requote quando o POST da order chega *depois* da mudança de preço).

Falham duas superfícies de **tempo / estado JWT** com o mesmo gatilho `order_wallet_release_flag_immutable`:

1. **Hold de marketplace não se cancela** (vendedor nem comprador) — stock fica preso e o checkout do hold antigo continua a honrar o preço selado.
2. **Review humana 5★ após `concluido` é recusada** — a libertação da carteira só acontece pelo cron `batata_generate_auto_feedback` (service_role). O caminho humano fica morto.

Não é a classe saturada (dual Session / offer amount / tip sem live / invite enum).

---

## Contabilidade (Stripe TEST)

| Momento | Wallet buyer | Wallet seller |
|---------|--------------|---------------|
| Início pass2 | 22.75 € | 234.60 € |
| Após pass4 (cron auto-feedback libertou ~5.90 €) | 22.75 € | 239.60 € |

PI TEST usados: `pi_3UATzXH7FWYUN3jh074Ti0wz`, `pi_3UATziH7FWYUN3jh1thv0kp7`, `pi_3UAU1cH7FWYUN3jh0uz3Nwso`, `pi_3UAU34H7FWYUN3jh1MUViesL` (590¢). Refunds: **1 por PI**, `already_refunded` / `idempotent` no 2.º POST.

---

## Findings

### RTG-G6-006 · G6 · P1

**Título:** JWT não consegue cancelar `reserva_pendente` (`order_wallet_release_flag_immutable`).

**Actor:** seller JWT e buyer JWT (o mesmo 403).

**Passos**
1. Comprador cria hold `reserva_pendente` em SKU listed (sem captura, `wallet_release_processed_at` = null).
2. Vendedor `PATCH orders status=cancelado`.
3. Comprador tenta o mesmo.

**Esperado:** hold passa a `cancelado`; stock libertado.

**Obtido:** HTTP 403 `order_wallet_release_flag_immutable` nos dois actores. Linha permanece `reserva_pendente`. Flag continua `null` (o UPDATE aborta).

**Prova**
- Order `b7654d46-04c2-4f05-a58a-01f783d83ca4` · product `8e5f505a-1845-4ffa-a3e0-f62b8452fb2f`
- pass3.json `p3.g6.cancel_hold`
- Mesmo 403 no pass1 ao cancelar `5c513bab-f308-47d8-8047-93b1356cd386` (ficou `reserva_pendente`)

**Porquê P1:** hold sem TTL observável + sem cancel JWT = stock/capacidade presa. Combina com checkout do hold antigo (G9 abaixo).

---

### RTG-G8-004 · G8 · P1

**Título:** Review humana 5★ bloqueada — só o cron (service_role) liberta a carteira.

**Actor:** buyer JWT vs cron `batata_generate_auto_feedback`.

**Passos**
1. Fixture Stripe TEST `setup_paid_order` → `pago` (590¢).
2. Seller `enviado` → buyer `concluido` (mão). `wallet_release_processed_at` ainda null.
3. Sem cron: `POST reviews` stars=5, `author_role=comprador`.
4. Em paralelo noutro order: o mesmo POST humano ∥ cron com `completed_at` −49h.

**Esperado:** 201 review; trigger liberta carteira do vendedor.

**Obtido**
- Isolado: 403 `order_wallet_release_flag_immutable`. Order `208a072a-35ed-46d3-b3f9-4ff3835bbb28` continua `concluido`, release=null.
- Com cron: humano 403; cron HTTP 200 cria **2** reviews automáticas (comprador+vendedor) e `wallet_release_processed_at` preenchido. Seller wallet 234.60 → 239.60.

**Prova:** pass5.json `p5.human_review`; pass4.json `order_after_review` + `wallets_after_review`.

**Porquê P1:** o caminho humano de feedback/release está morto; só o job de 48h escreve. Não é roubo — é **negação de libertação + feedback real**. Mesma família de trigger que G6-006.

---

### RTG-G9-003 · G9 (G6∘G6-006) · P1

**Título:** Depois de subir o preço, o vendedor não retrai o hold; o checkout cobra o contrato velho.

**Actor:** seller PATCH price ∥ buyer checkout na order já criada.

**Passos**
1. Order selada a 8,50 € (`price_total=8.5`).
2. Seller `PATCH products.price=99`.
3. Buyer `POST create-payment-intent` na **mesma** order.
4. Cancel do hold (G6-006) falha.

**Esperado:** recusa, requote a 99 €, ou cancel do hold pelo vendedor.

**Obtido:** Session 200, `server_amount_cents=958` (8,50 + seguro ~1,08 €). Catálogo já está a 99 €. Insert **novo** com 8,50 **depois** do catálogo a 99 **requota** para 10460¢ — a Edge não é ingénua no POST fresco; o problema é o hold antigo + impossibilidade de cancelar.

**Prova:** pass2.json `RTG-G6-003` · checkoutUrl `cs_test_a1Pbwax8VWHcgSaVnGLzccp3UdciXHegJFdkQRr0u6mS8B8TNufcex0Ykq` · 958¢. Contraste pass3 `p3.g6.stale_insert_pay` cents=10460.

---

### RTG-G2-003 · G2 · P2

**Título:** Hold criado em corrida com `is_sold`+unlist do último SKU; checkout posterior bloqueia.

**Actor:** buyer POST orders ∥ seller PATCH sold+unlist (`Future.wait`).

**Esperado:** um dos dois perde (hold recusado **ou** produto não sold com hold).

**Obtido:** os dois ganham. Order `3390f39c-9c9f-43c6-9c8e-8b55850b56b7` `reserva_pendente`; product `2f081282-f2cf-45c3-ba24-a1c4b9234643` `is_sold=true`, `list_on_marketplace=false`. Checkout a seguir: 400 `Checkout blocked: product is marked sold.` Cancel do hold: G6-006.

**Prova:** pass2.json finding + pass3 `p3.g2.ghost_checkout`.

**P2:** estado fantasma, **sem captura**. Loot de dinheiro não comprovado. Combina com G6-006 (ninguém limpa o hold).

---

### RTG-G7-001 · G7 · P2

**Título:** Access token continua a escrever depois de `POST /auth/v1/logout`.

**Actor:** buyer JWT.

**Passos:** logout 204 → `POST orders` com o mesmo Bearer → 201 order `ce172017-2199-4b53-8862-0035da53c097`.

**Esperado:** 401 se o produto pretender revogar access tokens.

**Obtido:** sessão de access_token intacta (comportamento típico Supabase: logout invalida refresh, não o JWT até `exp`).

**P2:** higiene de sessão, sem loot extra além do que o token já permitia.

---

## Ataques que **não** passaram (defesa / não-finding)

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| G1 | 2× `create-payment-intent` paralelo no mesmo hold | 1 URL Session, 958¢ nos dois (idempotente) |
| G1 | 2× `refund-order` paralelo em order paga TEST | mesmo `refund_id`, `already_refunded`/`idempotent` |
| G1 | `batata_wallet_payout_debit` JWT | 403 permission denied |
| G2 | 2 buyers qty=1 | 1 hold + `order_hold_exceeds_stock` |
| G2 | checkout ∥ unlist | 400 `product is not listed` |
| G2 | accept offer ∥ expire cron | status final `expired` |
| G2 | enviado ∥ refund | shipping frozen; refund idempotente |
| G3 | webhook sem `stripe-signature` | 400 `missing_signature` |
| G3 | GET settle `cs_test_rtg_unpaid` | 400 «ainda não confirmado» |
| G3 | JWT INSERT `stripe_checkout_events` | 403 |
| G4 | refund hold sem PI | 422 |
| G4 | buyer `concluido` sem captura | HTTP 200 mas status **não** ficou `concluido` |
| G5 | accept offer `expires_at` passado | 400 `offer_expired` |
| G5 | claim pairing após expire | 400 `invalid_or_expired_code` |
| G5 | JWT chama `batata_expire_product_offers` / `batata_generate_auto_feedback` | 403 |
| G6 | POST order 8,50 € em SKU já a 99 € | checkout **10460¢** (requote) |
| G6 | PATCH `amount_paid_cents` / release flag | 403 `order_money_fields_immutable` |
| G6 | buyer2 PATCH order alheia | 200 `[]` (0 rows) |
| G7 | seller JWT checkout da order do buyer | 400 `Invalid checkout user` |
| G7 | buyer2 `refund-order` alheia | 403 Sem permissão |
| G8 | JWT acelera auto-feedback com `p_now` +30d | 403 |

### Falso positivo retirado

**RTG-G5-002:** accept de reserva live após PATCH `expires_at` para o passado. O GET *depois* do accept mostra `expires_at=2026-09-05` (futuro). O PATCH de TTL **não ficou provado**. Convert JWT: 403 `permission denied for function batata_live_reservation_stripe_convert`. **Não congelado como finding.**

**RTG-G8-003:** 2 reviews no race humano∥cron = par automático comprador+vendedor do cron, não duplicado humano.

---

## Tácticas obrigatórias — cobertura

1. **≥3 races reais (`Future.wait`):** checkout dual; last-unit 2 buyers; hold∥sold+unlist; checkout∥unlist; accept∥expire; 2× refund; enviado∥refund; review∥cron.
2. **≥1 replay:** webhook sem sig; GET settle fake; 2× GET/refund na order paga; e2e `settle_get_replay` (fixture 500 `session missing payment_intent` — Session aberta/unpaid, sem double-credit).
3. **≥1 Stripe TEST pago:** `setup_paid_order` (pm_card_visa / 4242 equivalente na Edge de fixture) + refund + concluido. Fixture = service_role; ataques seguintes = JWT.
4. **Contabilidade:** wallets + PI 590¢ + 1 refund.
5. **Dois buyers / buyer+seller no mesmo objecto:** last-unit; foreign refund; foreign PATCH; hold∥unlist.
6. **Flutter ≠ fronteira:** REST / RPC / Edge.
7. **Não partir de propósito:** `enviado` tentado em order paga; confirmação mão só após enviado.

---

## Saturação G

Último ciclo (pass5) acrescentou **G8-004** (classe nova relativamente a dual-Session). G5 live-TTL ficou **inconclusivo**. Não declarar PASS global da app.

**ATROFIA_ABORT:** não. Findings P1 ≠ dual Session / offer amount / tip sem live / invite enum / OCR kick.

---

## IDs úteis (staging)

- Buyer `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96`
- Seller `980f4fa1-0004-42f9-abca-69f1a9c29588`
- Buyer2 `af9c7e0f-9767-4107-b5fc-2d85806325d9`
- Pasta: `tool/redteam_blind_g_20260831T1253/`
