# Auditoria cega independente — Relatório congelado

**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO (auditor)  
**FROZEN_AT:** `2026-08-30T15:25:00Z`  
**Identidade da ronda:** `RT1605` / `20260830T1605`

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0 confirmados. Zero P1 confirmados. Invariantes financeiros atacados em live. Composição e races executadas. O último passe completo não revelou nova classe P0/P1.

---

## Checklist final

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | P0 aberto encontrado | **NÃO** |
| 2 | Quantos P0 | **0** |
| 3 | P1 aberto encontrado | **NÃO** |
| 4 | Quantos P1 | **0** |
| 5 | Buyer consegue manipular preço autoritativo | **NÃO** |
| 6 | Buyer consegue manipular qty autoritativa | **NÃO** |
| 7 | Seller consegue falsificar pagamento plataforma | **NÃO** |
| 8 | JWT consegue criar saldo/fundos | **NÃO** |
| 9 | Refund pode exceder captura | **NÃO** (sem captura de produto nesta ronda; refund sem PI → 422) |
| 10 | Release+refund cria dinheiro líquido | **NÃO** (release em order não paga → `false`) |
| 11 | Payout pode duplicar Transfer indevidamente | **NÃO** (mesma idempotency_key → mesmo `transferId`, `idempotent: true`) |
| 12 | Stock=1 pode produzir duas vendas válidas | **NÃO** (2.º INSERT → `order_hold_exceeds_stock`) |
| 13 | Stock=1 pode produzir duas capturas líquidas permanentes | **NÃO COMPROVADO** (Sessions de produto não foram pagas até captura) |
| 14 | Existe bypass de capacidade/reserva | **NÃO** (qty 1e6 / 99 / 2.º hold rejeitados) |
| 15 | Existe cross-user financeiro | **NÃO** |
| 16 | Existe cross-user de dados sensíveis | **NÃO** (B2: orders/disputes/chat/events/storage = vazio) |
| 17 | Buyer pode assumir autoridade seller/admin | **NÃO** (`batata_is_admin` → `false`; helper self-insert 403; `create-mux-live` buyer 403) |
| 18 | Seller pode assumir autoridade buyer/admin | **NÃO** |
| 19 | Reviews podem ser forjadas/duplicadas | **NÃO** (`review_order_invalid_status` / `review_order_required` / `review_order_not_yours`) |
| 20 | RPC/SECURITY DEFINER perigoso encontrado | **NÃO** (vários EXECUTE 200 devolvem `false` / `not_allowed` / sem mutação indevida) |
| 21 | RLS crítico quebrado | **NÃO** |
| 22 | Edge Function confia em autoridade do cliente | **NÃO** (`server_amount_cents` ignora `amount` do body; `prize_shipping` recusado; JWT mismatch 400) |
| 23 | Alguma conclusão crítica ficou NÃO COMPROVADA | **SIM** (captura Stripe TEST de checkout de produto não concluída até PaymentIntent paid) |
| 24 | Houve regressão funcional relevante | **NÃO** (não se alterou produto) |
| 25 | Último passe encontrou nova classe P0/P1 | **NÃO** |
| 26 | Saturação atingida | **SIM** |
| 27 | Produção tocada | **NÃO** |
| 28 | Fase 4 iniciada | **NÃO** |

---

## Findings

| ID | Sev | Título | Actor | Pré-condições | Reprodução | Impacto | Estado |
|----|-----|--------|-------|---------------|------------|---------|--------|
| RT1605-P2-01 | **P2** | JWT da parte da encomenda consegue INSERT em `stripe_checkout_events` (incl. `refund_created`) | buyer (parte) | order própria; tabela com INSERT RLS para o `buyer_id` | `POST /rest/v1/stripe_checkout_events` `{order_id, buyer_id: self, event: refund_created}` → HTTP 201 | Poluição do diário de checkout. O release de carteira do vendedor consulta eventos `refund_created` / `charge.refunded` e pode recusar crédito. **Não demonstrado** em order com captura Stripe real nesta ronda. Cross-user (B2 → order alheia) → 403. | ABERTO |
| RT1605-P3-01 | **P3** | `batata_find_user_id_by_email` enumeração lenta só para vendedor | seller | JWT vendedor | RPC com email; buyer recebe `null`; seller recebe UUID próprio | Enumeração 5/h, papel staff. Sem UUID alheio para buyer. | ABERTO |
| RT1605-P3-02 | **P3** | `ps-pairing-claim` devolve `device_token` + `supabase_url` a quem conhece um código de 6 dígitos válido | anon | código gerado por seller/helper | `POST /functions/v1/ps-pairing-claim` | Fluxo PS intencional; brute-force limitado por rate. Helper com `can_manage_reservations` também gera código (teste de convite, depois removido). B2 sem helper → `not_allowed`. | ACEITE residual |

Falsos positivos rejeitados (não entram na tabela): SELECT `wallet_transactions` / `order_disputes` / `chat_messages` do próprio laboratório; HTTP 200 em RPCs que devolvem `false`; gorjeta de carteira 1 € (débito 1,00 + crédito vendedor 0,57 + taxa 0,43 — conservação, saldo pré-existente); pairing PS pelo helper do convite de laboratório.

---

## Superfícies testadas

AUTH/PROFILES · ORDERS · ORDER FSM · PRODUCTS · PRICE/CONTRACT · QTY · CHECKOUT · STRIPE SESSION · SETTLE (return path fake) · BAG · WALLET · LEDGER · PAYOUT · STOCK · REFUNDS · DISPUTES · OFFERS · BUNDLES · TIPS · CHAT · REVIEWS · STORAGE · MUX · LIVEKIT (edge auth) · PS/OCR · RPCs (OpenAPI 176) · SECURITY DEFINER/GRANTs (probe JWT/anon) · RLS · TRIGGERS (efeito na row final) · EDGE FUNCTIONS listadas em `config.toml`.

Não houve live de comprador no player; um directo Mux de laboratório criado no passe 4 foi posto `status=ended`, `is_active=false`.

---

## Invariantes

| ID | Invariante | Resultado live |
|----|------------|----------------|
| A | Stripe cobra o contrato servidor | **Sustido.** `amount=50` no body → `server_amount_cents=3215` (artigo 30 € + protecção, portes mão). Bag 2×11 € + `amount=50` → `2144` (não 50). |
| B | Buyer não define preço/qty autoritativos | **Sustido.** INSERT `contract_unit_cents=1`, `qty=99`, `status=pago`, PI hostil → row final `reserva_pendente`, `contract_unit_cents=4200`, `qty=1`, Stripe IDs null. PATCH posterior não persiste. |
| C | Release/refund/payout ≤ fundos plataforma | **Sustido no que foi exercido.** Release sem captura → `false`. Refund sem PI → 422. Gorjeta wallet consome saldo existente. |
| D | Uma unidade ≠ duas vendas válidas | **Sustido.** Stock=1, 2 INSERT concorrentes: 201 + `order_hold_exceeds_stock`. 10× mesmo buyer: 1 criado, resto 400. |
| E | JWT não cria saldo/ledger/Stripe IDs | **Sustido.** Wallet INSERT 403; PATCH balance não persiste (14→ não 8888); `wallet_transactions` INSERT 403; PI no INSERT de order limpo. |
| F | Pagamento off-platform ≠ saldo Fleaber | **Sustido no caminho MB WAY desta ronda** (release `false` / sem txs). |
| G | Refund ≤ captura | **Não exercido com captura de produto.** |
| H | Parties coerentes | **Sustido.** PATCH `buyer_id`/`seller_id` revertido. Checkout seller JWT + `buyer_id` alheio → `Invalid checkout user`. |
| I | 1 intenção payout → ≤1 Transfer | **Sustido.** Retry mesma key → mesmo `tr_1UAAX7H7FWYUN3jhcpKIX6q1`, `idempotent: true`. |
| J | 2 intenções distintas → 2 Transfers | **Sustido.** Duas keys diferentes → dois `transferId` (1 cêntimo TEST cada, saldo pré-existente). |
| K | Catálogo posterior não reescreve contrato | **Sustido no selo.** Order a 42,00 €; checkout alinhou `price_total` a 44,75 € (contrato+taxas), não ao `amount` cliente. Session reutilizada após alteração de catálogo. |
| L | Offer/bundle/reservation só com autoridade | **Sustido.** INSERT offer `accepted` nasceu `pending`, `responded_at` null; order ignorou offer (`product_offer_id` null, contrato 25,00 €). Bundle upsert alheio 403. |

---

## Races (estado final)

- **Stock=1, dois buyers, INSERT paralelo:** 1 order; produto `quantity=1`; 2.º `order_hold_exceeds_stock`.
- **Stock=1, 10× mesmo buyer:** 1 order.
- **Checkout 8× mesma order:** 8 HTTP 200, **um** `checkoutSessionId`, `reused_session: true`.
- **Payout duas keys 1 cêntimo:** duas Transfers TEST distintas (intencional).
- **Payout mesma key:** uma Transfer, segunda idempotente.
- **Dois refunds sem PI:** ambos 422.
- **Duas reviews order não paga:** bloqueadas.

---

## Stripe TEST

| Tipo | Resultado |
|------|-----------|
| SESSION CRIADA | Sim (produto 30 € → 32,15 €; bag → 21,44 €; produto 42 € → session reutilizada, `price_total` 44,75 €) |
| CAPTURA REAL TEST (checkout produto) | **Não** — não se completou o pagamento da Checkout Session |
| CAPTURA LÍQUIDA PERMANENTE (produto) | **Não aplicável** |
| Payout Connect TEST | Sim — levantamentos de **1 cêntimo** a partir de saldo de carteira já existente (não é mint) |
| Gorjeta wallet | Débito 1,00 € / crédito vendedor 0,57 € / taxa 0,43 € |

---

## Lacunas

1. Checkout Sessions de produto **não pagas** até `amount_paid_cents` / webhook — oversell com duas Sessions pagas no mesmo stock=1 fica **NÃO COMPROVADO** no eixo captura (o eixo hold já falhou o 2.º INSERT).
2. Partial refund Stripe, dispute×release, raffle prize order e OCR ingest com token roubado **não** foram levados a captura completa.
3. OpenAPI inicial falhou com `apikey=anon`; inventário RPC obtido depois com service_role (observação). Nem todas as 176 funções foram chamadas com a assinatura exacta; o conjunto financeiro/admin/lab/nuke/tip/payout/refund/settle foi.
4. `RT1605-P2-01` (INSERT events) **não** foi encadeado com uma captura Stripe real + `batata_release_seller_wallet_for_order`.

---

## Saturação

**SIM.** Três passes conceptuais (cobertura → variantes/invariantes → composição/races) mais verificação e RPC sweep. Último passe sem nova classe P0/P1.

---

## Notas de laboratório

- Conta B2 descartável `rt1605-b2-…@staging.fleaber.invalid` criada só para isolamento RLS.
- Convite helper de laboratório (para testar escalada de `permissions`) foi **apagado** no cleanup.
- Directo Mux `336d37ad-…` criado no teste `create-mux-live` foi **terminado**.
- Saldo buyer lab: ~14 € → ~12 € após gorjeta de 1 € (intencional). Seller: levantamentos TEST de 1 cêntimo + gorjeta 0,57 €.
- **service_role** só para fixtures, observação e cleanup. Exploits reproduzidos com anon / JWT buyer / JWT seller / B2.
