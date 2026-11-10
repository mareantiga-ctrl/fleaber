# Fleaber — auditoria cega independente (Red Team)

**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO  
**FROZEN_AT:** `2026-08-30T18:08:08+01:00`  
**Prefixo de fixtures:** `RT1752`  
**Identidades:** anon · buyer JWT laboratório · seller JWT laboratório  
**service_role:** só fixtures, observação e evidência — nunca para demonstrar exploit  

**Veredicto:** `D — PASS_CEGO_SATURADO`

---

## Checklist final

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | P0 aberto encontrado | NÃO |
| 2 | Quantos P0 | 0 |
| 3 | P1 aberto encontrado | NÃO |
| 4 | Quantos P1 | 0 |
| 5 | Buyer manipula preço autoritativo | NÃO |
| 6 | Buyer manipula qty autoritativa | NÃO |
| 7 | Seller falsifica pagamento plataforma | NÃO |
| 8 | JWT cria saldo/fundos | NÃO |
| 9 | Refund excede captura | NÃO |
| 10 | Release+refund cria dinheiro líquido | NÃO |
| 11 | Payout duplica Transfer indevidamente | NÃO |
| 12 | Stock=1 → duas vendas válidas | NÃO |
| 13 | Stock=1 → duas capturas líquidas permanentes | NÃO COMPROVADO (não se obtiveram duas Sessions; 10 POSTs paralelos → 1 `cs_`) |
| 14 | Bypass de capacidade/reserva | NÃO |
| 15 | Cross-user financeiro | NÃO |
| 16 | Cross-user dados sensíveis | NÃO |
| 17 | Buyer assume seller/admin | NÃO |
| 18 | Seller assume buyer/admin | NÃO |
| 19 | Reviews forjadas/duplicadas | NÃO |
| 20 | RPC/SECURITY DEFINER perigoso | NÃO |
| 21 | RLS crítico quebrado | NÃO |
| 22 | Edge confia em autoridade do cliente | NÃO |
| 23 | Conclusão crítica NÃO COMPROVADA | SIM (ver lacunas) |
| 24 | Regressão funcional relevante | NÃO |
| 25 | Último passe encontrou nova classe P0/P1 | NÃO |
| 26 | Saturação atingida | SIM |
| 27 | Produção tocada | NÃO |
| 28 | Fase 4 iniciada | NÃO |

---

## Findings

**P0:** nenhum  
**P1:** nenhum  

### P3 (higiene / defesa em profundidade)

| ID | Título | Actor | Impacto | Estado |
|----|---------|-------|---------|--------|
| RT1752-P3-01 | Seller resolve email→UUID (`batata_find_user_id_by_email`) | seller JWT | enumeração de contas, rate 5/h | ABERTO (higiene) |
| RT1752-P3-02 | Anon invoca `batata_admin_resolve_dispute` (DEFINER) | anon | falha fechada (`Apenas administradores`); GRANT excessivo | ABERTO (higiene) |

**Falso positivo descartado:** PATCH `orders.seller_id` devolveu HTTP 200 mas a row final manteve o seller original. O corpo ecoava `buyer_id` do comprador — não houve troca de parte.

---

## Superfícies atacadas

AUTH/PROFILES · ORDERS + FSM · PRODUCTS/CATALOG · PRICE/CONTRACT · QTY · CHECKOUT · STRIPE SESSION · SETTLE (GET fake + webhook forjado) · BAG · WALLET/LEDGER · PAYOUT · STOCK · REFUNDS · DISPUTES · LIVE/LIVE ITEMS/RESERVAS · OFFERS · RAFFLES · TIPS · CHAT · REVIEWS · STORAGE · MUX · LIVEKIT · OCR/PS · RPCs (178 no OpenAPI live) · SECURITY DEFINER · GRANTs · RLS · EDGE FUNCTIONS listadas no repo.

---

## Invariantes financeiros (tentativa de refutação)

| ID | Invariante | Resultado live |
|----|----------|----------------|
| A | Stripe cobra o contrato servidor | **Não refutado.** `amount=1` no body → `server_amount_cents=1955` (catálogo 18,00 € + protecção; portes mão 0). Catálogo 12,34 € → `price_total` alinhado 13,61 €. |
| B | Cliente não define preço/qty | **Não refutado.** INSERT `contract_unit_cents=1` selou **1990** / **1234**. `quantity=99` → `order_hold_exceeds_stock`. PATCH money → `order_money_fields_immutable`. |
| C | Release/refund/payout ≤ fundos | **Não refutado.** Fixture Stripe TEST paga (590 cêntimos) + refund concorrente: 1× Stripe refund, retries `already_refunded` / idempotency in-progress. Saldos wallet **inalterados** (buyer 16,90 → 16,90; seller 37,96 → 37,96). Flags `wallet_release` e `wallet_refund` ambas preenchidas **sem** crédito. |
| D | Uma unidade ≠ duas vendas | **Não refutado.** 10 INSERT paralelos com stock=1 → `ok=0/10`. Qty do produto permaneceu 1. |
| E | JWT não cria saldo / PI / payout interno | **Não refutado.** PATCH wallet `200 []` (0 rows). INSERT `wallet_transactions` RLS. `batata_wallet_payout_debit` / `finalize_stripe_order_refund` / `credit` / `nuke` → 403/404. INSERT order `status=pago` + PI falso → row final `reserva_pendente`, `amount_paid_cents=null`, PI null. |
| F | Pagamento off-platform ≠ saldo | **Não refutado.** INSERT MB WAY `pago` foi rebaixado. `release` sobre pendente → `false`. |
| G | Refund ≤ captura | **Não refutado.** Refund seller da order TEST = 590 cêntimos (= captura). Body `amount_cents` ignorado (Edge não aceita montante cliente). Buyer refund → 403. |
| H | Parties coerentes | **Não refutado.** INSERT `buyer_id` alheio → `order_buyer_attribution_denied`. Checkout order alheia → `order does not belong to buyer`. PATCH seller_id não persistiu. |
| I | Uma intenção payout ≤ uma Transfer | **Não refutado.** 6 POSTs paralelos, duas keys A/B → **duas** Transfers distintas (`tr_…Hmp` e `tr_…MlmW`) para **duas** intenções de 100 cêntimos. Retries da mesma key reutilizaram o mesmo `transferId`. |
| J | Duas intenções distintas → duas Transfers | **Confirmado** (comportamento esperado). |
| K | Catálogo posterior ≠ contrato | **Não refutado.** Contrato selado no INSERT; checkout usa `contract_unit_cents`. |
| L | Offer/bundle/reserva só com autoridade | **Não refutado.** INSERT offer aceite 0,01 → RLS. Self-accept → `offer_amount_immutable`. Prize shipping sem rifa → bloqueado. |

---

## Races (estado final)

| Race | Resultado |
|------|-----------|
| 10× INSERT order stock=1 | 0 criadas; produto `quantity=1` |
| 10× `create-payment-intent` mesma order | `ok=10 unique_sessions=1` (`cs_test_a1bK4oCI…`); `server_amount_cents=1010` |
| 6× payout 100 cêntimos, keys A e B | 2 Transfers (2 intenções); 1× `idempotency_key_in_use`; sem 3.ª Transfer |
| 2× refund-order + release/refund wallet em paralelo (order TEST paga 590) | 1 refund Stripe `re_3UACAOH7FWYUN3jh1i6Fhdqi`; 2.º `already_refunded`; wallets sem mint; order `cancelado` |
| 4× INSERT reviews | `review_order_required` |

---

## Stripe TEST

| Camada | O quê |
|--------|--------|
| SESSION CRIADA (JWT) | Sim. Cliente `amount=1` ignorado. Servidor cobrou **1955** cêntimos (18,00 € + taxa) e **1010** cêntimos (9,00 € + taxa). |
| CAPTURA REAL TEST | Sim, via fixture laboratorial `sec-fase2-e2e-oversell` `setup_paid_order` (segredo de staging, **não** é prova de JWT). PI `pi_3UACAOH7FWYUN3jh1mElVVHq` `succeeded` 590. Settle → order `pago`, `stock_units_applied=1`. |
| CAPTURA LÍQUIDA PERMANENTE | Após refund seller: order `cancelado`, `stripe_refund_id` preenchido, stock aplicado anulado (`null`). Sem mint wallet. |
| JWT 4242 até captura | **Não feito** neste freeze (lacuna). |

Webhook forjado (`stripe-signature: t=1,v1=deadbeef`) → `invalid` / 400. GET settle `cs_test_fake` → sem marcar pago.

---

## RPCs / DEFINER / GRANTs

Inventário live OpenAPI: **178** funções.  
Ataque JWT/anon nas funções económicas e admin com assinaturas exactas:

- `batata_is_admin` → `false` (anon/buyer/seller)
- `batata_admin_resolve_dispute` → excepção admin (fail-closed)
- `staging_nuke_user_data` → permission denied
- `batata_wallet_payout_debit` / `payout_finish` / `clawback` / `finalize_stripe_order_refund` / `settle_live_tip` → 403
- `batata_ensure_wallet(seller)` como buyer → 403
- Draw raffle buyer → `raffle_not_found` / não executa sorteio alheio

---

## RLS (row final)

- Buyer não lê wallet do seller (`200 []`).
- Buyer não lê orders de outros (`200 []`).
- Stream keys Mux: `SELECT mux_stream_key,stream_key` → 403 (buyer **e** seller via PostgREST; chave só na Edge `create-mux-live` para vendedor).
- Chat alheio: `GET chat_messages?chat_id=<terceiro>` → `200 []`.
- Storage buckets listáveis: vazio / sem leakage de objectos.
- Profiles: PATCH `user_type=admin|vendedor` HTTP 200 mas row final permanece `comprador`.

---

## Edge Functions

Buyer: `create-mux-live` 403 authz; payout `user_id` alheio 400; `tip_id` cliente recusado; `fase2_e2e_settle` 401; `sec-fase2-e2e-oversell` JWT 401; OCR sem token 401; pairing código inválido; `delete-test-account` 403 allowlist.  
Seller refund de order sem PI → 422 (não inventa reembolso).

---

## Lacunas (explícitas)

1. Checkout JWT **não** foi pago com cartão TEST 4242 até webhook/settle (prova de montante ficou na **Session** + alinhamento `price_total`).
2. Não se reproduziu **duas** Sessions; portanto duas capturas permanentes no mesmo stock=1 ficam **NÃO COMPROVADO** (a race aponta para 1 slot).
3. Assinaturas live de `batata_credit_wallet_once` / `debit` / `process_partial_refund_dispute` não coincidiram com os nomes tentados (404 schema); GRANTs observados noutras funções internas = service_role.
4. OCR/PS sem device token válido de vendedor — só caminho token inválido.
5. Conluio buyer+seller limitado às contas de laboratório (não se criou terceiro pagador Stripe JWT).

---

## Saturação

- Pass 1 cobertura (180 probes, 1 falso positivo descartado)
- Pass 2 dinheiro/races
- Pass 3 composição
- Pass 4 variantes + Stripe TEST fixture + 10× session race
- Pass 5 + 5b RPC perigosas com assinatura exacta  

Último passe completo **sem nova classe P0/P1**.  
**SATURAÇÃO = SIM**

---

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0, zero P1 confirmados. Invariantes A–L atacados em live. Composição e races executadas. Produção não tocada. Sem correcções.

---

## Artefactos

| Ficheiro | Conteúdo |
|----------|----------|
| `tool/redteam_blind_indep_20260830T1752/_http.dart` | Cliente HTTP |
| `pass1_discover.dart` … `pass5b_exact.dart` | Probes |
| `out/pass1.json` … `pass5b.json` | Matriz + evidência |
| `out/rpc_inventory.json` | 178 RPCs live |
| `frozen.json` | Machine-readable |

Identidades de laboratório (UUIDs públicos de fixture, sem secrets):  
buyer `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · seller `980f4fa1-0004-42f9-abca-69f1a9c29588`
