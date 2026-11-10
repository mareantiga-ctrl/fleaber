# Fleaber — Auditoria cega independente (Red Team)

**FROZEN_AT:** 2026-08-30T14:00:00+01:00  
**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções aplicadas:** NÃO  
**Veredicto:** **A — FAIL_P0**

Auditoria cega: código actual + schema live + probes JWT (anon / buyer / seller).  
service_role só para fixtures, observação e cleanup.  
Não foram consultados relatórios de auditorias/hardening/reteste anteriores.

---

## 1. Veredicto

Existe **P0 confirmado e reproduzido** (≥2 variantes independentes): o comprador autentica, insere uma encomenda **sem oferta aceite**, com `payment_method` contendo `proposta` e `price_total` arbitrário; o selo de contrato persiste esse valor; a Edge `create-payment-intent` cria uma **Checkout Session Stripe TEST pagável** por esse montante (mais portes/protecção), não pelo catálogo.

**CAPTURA REAL TEST:** não completada (página Stripe recusou URL truncada no browser). O `amount_total` da Session é o contrato de cobrança Stripe; o atacante só tem de pagar a Session.

---

## 2. Findings

### RTI-P0-001 — Buyer sela preço arbitrário via `proposta` sem oferta aceite

| Campo | Valor |
|---|---|
| **Severidade** | P0 |
| **Actor** | Buyer JWT (PostgREST directo, sem Flutter) |
| **Estado** | CONFIRMADO |
| **Pré-condições** | Produto de catálogo do seller; JWT comprador |

**Reprodução**

1. `POST /rest/v1/orders` (JWT buyer) com `payment_method: "proposta"` (também `PROPOSTA`, `Proposta aceite`), `price_total` baixo (0.50 / 0.80 / 1.20), `product_offer_id` omitido, `status: reserva_pendente`, `shipping_method: mao` ou `ctt`, `quantity` 1 (ou 3).
2. Observar row (service_role): `contract_unit_cents` = `price_total*100`, `product_offer_id` = null, catálogo intacto.
3. `POST /functions/v1/create-payment-intent` com `{order_id, buyer_id: self, shipping_method}` — **não** enviar `amount` como autoridade.
4. Resposta 200: `amount_total` << catálogo + protecção.

**Evidência live**

| Variante | Catálogo | Contrato selado | Session `amount_total` | Session ID |
|---|---|---|---|---|
| hand + proposta 0.50 € | 42.00 € | unit=50, offer=null | **118** cêntimos (1.18 €) | `cs_test_a1cotEbJicntISQI6eUfmBGdSFbHaNtzgQQf5RO6jtTix3bbCTR7Ih8jws` |
| ctt + proposta 0.50 € | 42.00 € | unit=50 | **485** cêntimos (4.85 €) | `cs_test_a1XHDPkp8pdwyk1Z7Rqzq9bBwpTndlc4U0PZcSZpmpgLkFESPKhXT6FVOa` |
| controlo hand catálogo | 42.00 € | unit=4200 | **4475** cêntimos (44.75 €) | `cs_test_a1NutY920THnvq3CYPN5i5EKJgUxyToCOlBn6lho2QNSyGvsJYg1Lx4BTQ` |
| hand + proposta 0.80 € | 55.00 € | unit=80, offer=null | **149** cêntimos (1.49 €) | `cs_test_a1eE0RvVZjtwpiEjLTjc8TGTZhfP2y6zWiuX7X7YQSib6dngvHA9PeWrEx` |
| `PROPOSTA` 1.20 € | 55.00 € | unit=120 | checkout HTTP 200 | `cs_test_a1Q25gvnd59xTaHuGhF9bRQg7XhzFtWYu8SAZivqyP3wy24eM4vIUhEhoU` |

qty=3 + `Proposta aceite` selou unit=50 e `price_total=1.50` (3×0.50) sem oferta.

**Impacto:** pagar na app **muito abaixo** do preço do anúncio, sem o vendedor ter aceite proposta. Stripe cobra `amount_total`. Stock fica em hold pela order `reserva_pendente`.

**Causa (código actual, confirmada pelo comportamento):** `batata_orders_seal_contract` trata `payment_method ILIKE '%proposta%'` como autorização para baixar o unitário a `price_total`, **sem** exigir `product_offers.status=accepted`. A Edge cobra `contract_unit_cents` da order, não o catálogo.

---

### RTI-P2-001 — JWT persiste `contract_unit_cents` no INSERT (não cobrável a 1 cêntimo)

| Campo | Valor |
|---|---|
| **Severidade** | P2 |
| **Actor** | Buyer JWT |
| **Estado** | CONFIRMADO |

INSERT `pagamento na app` + `contract_unit_cents=1` + `reserva_pendente` → row final `unit=1`, `price_total=0.01`. Checkout: `Checkout blocked: item without price.`  

Não produz Session. Envenena o contrato na BD; o caminho cobrável é RTI-P0-001 (≥50 cêntimos + portes válidos).

---

## 3. Superfícies atacadas

AUTH/PROFILES, ORDERS + FSM, PRODUCTS/CATALOG, PRICE/CONTRACT, QTY, CHECKOUT, STRIPE SESSION, SETTLE GET, BAG (não exercido em profundidade — gap), WALLET/LEDGER/PAYOUT, STOCK, REFUNDS, DISPUTES, LIVE/LIVE ITEMS, RESERVAS (fixture falhou `ref_code` NOT NULL), OFFERS, RAFFLES (draw sem raffle), TIPS, CHAT, REVIEWS, STORAGE, MUX, LIVEKIT, PS/OCR ingest, RPCs/SECURITY DEFINER/GRANTs, RLS, TRIGGERS, EDGE FUNCTIONS, WEBHOOK.

---

## 4. Invariantes

| ID | Invariante | Resultado |
|---|---|---|
| A | Stripe cobra o contrato legítimo do servidor | **REFUTADO** — Session usa contrato envenenado pelo cliente |
| B | Buyer não define preço/qty autoritativos | **REFUTADO** (preço via `proposta`); qty 3 aceite no selo proposta |
| C | release/refund/payout ≤ fundos legítimos | Não refutado neste passe (payouts TEST com saldo real do seller lab) |
| D | Uma unidade ≠ duas vendas válidas | Stock=1: 1/10 INSERT; 2.ª order `order_hold_exceeds_stock` |
| E | JWT não cria saldo/ledger/Stripe IDs | INSERT wallet 403; PATCH balance não persistiu 8888; Stripe IDs no INSERT rejeitados / reescritos |
| F | Pagamento off-platform não minta saldo | 3.ª order MB WAY bloqueada por hold (stock); FSM JWT não chegou a `concluido` |
| G | Refund ≤ captura | Refund sem PI → 422; buyer 403 |
| H | Parties coerentes | Checkout `buyer_id` ≠ JWT → Invalid checkout user |
| I/J | Payout 1 intenção ≤ 1 Transfer; 2 intenções = 2 Transfers | Mesma key → mesmo `transferId`; keys distintas → 2 Transfers TEST (comportamento esperado) |
| K | Catálogo posterior não muda contrato | Checkout falhou metadata/portes no 1.º passe; controlo selou 4200 vs drop de catálogo não retestado com Session |
| L | Offer só altera preço com autoridade | **REFUTADO** — string `proposta` basta, sem offer row |

---

## 5. Races

| Race | Resultado |
|---|---|
| 10× INSERT stock=1 | 1 aceite / 10 |
| 2.ª order stock=1 | `order_hold_exceeds_stock` |
| Dual Session mesma order (metadata correcta) | bloqueado `pendente` no passe 3; com `reserva_pendente`+portes cria Session (não 10× pago) |
| Dual refund unpaid | 422 / 422 |
| Dual review | schema `rating` inexistente; `stars` + unpaid → `review_order_invalid_status` |
| Dual payout keys distintas | 2 Transfers TEST 1 € (saldo seller) |
| Dual payout mesma key | mesmo `tr_1UA97vH7FWYUN3jhhLJlbu6e` |
| Tip session bind | unique `live_tips_stripe_session_uidx` 409 |
| Reserva última unidade | fixture `live_items.ref_code` NOT NULL — **NÃO COMPROVADO** |

---

## 6. Stripe TEST

| Tipo | Resultado |
|---|---|
| SESSION CRIADA (subpreço) | SIM — 118, 485, 149 cêntimos vs catálogo 42 € / 55 € |
| SESSION CRIADA (controlo) | 4475 cêntimos para 42 € + mão + protecção |
| CAPTURA REAL TEST | **NÃO COMPROVADA** (Checkout hosted: link incompleto no browser) |
| CAPTURA LÍQUIDA PERMANENTE | NÃO COMPROVADA |

---

## 7. RLS / RPC / Edge (resumo)

- Anon: orders/wallets vazios ou 401; `lives`/`products` permission denied; webhook sem assinatura 400.
- Buyer não lê orders de terceiros (`n=0` no filtro alheio). Extra user: orders/wallets `n=0`.
- Stream keys: SELECT explícito 401/403.
- `batata_credit_wallet_once`, `payout_debit`, `apply_tip_once`, `settle_tip`, `finalize_refund`, `lab_clear_*`: 42501 JWT.
- Admin RPCs: `batata_is_admin` false; list/resolve negados.
- `create-mux-live` buyer: 403 só vendedor.
- `sec-fase2-e2e-oversell`: 401 só service_role.
- `mark_live_item_sold` buyer em item real: `{ok:false, not_allowed}`.
- Review sem order paga: bloqueada. Self-accept offer: `offer_accept_not_authorized`.
- FSM PATCH `pago`/`concluido`: HTTP 200 mas estado final `pendente`.
- Wallet PATCH `stripe_account_id`: 200 `[]`, conta inalterada.

---

## 8. Lacunas

- Captura Stripe TEST da Session subpreço não fechada.
- Bag multi-seller / descontos / refund parcial com captura real.
- Reserva live (faltou `ref_code` no INSERT).
- Disputa+refund com captura.
- `stripe_checkout_events` SELECT buyer/seller n=5 — não provado leak cross-user.
- `lives` SELECT * 403 mesmo seller (views/coluna) — não aprofundado.
- Dual Session paga no mesmo stock=1.

---

## 9. Saturação

**SATURAÇÃO = NÃO**

P0 encontrado nos passes 5–7; último passe reproduziu a mesma classe, não uma classe P0/P1 nova, mas o critério de saturação exige zero P0/P1 abertos.

---

## 10. Checklist

1. P0 aberto: **SIM**  
2. Quantos P0: **1** (RTI-P0-001)  
3. P1 aberto: **NÃO**  
4. Quantos P1: **0**  
5. Buyer manipula preço autoritativo: **SIM**  
6. Buyer manipula qty autoritativa: **SIM** (qty=3 selada em proposta falsa; qty=99 bloqueada por hold)  
7. Seller falsifica pagamento plataforma: **NÃO** (neste passe)  
8. JWT cria saldo/fundos: **NÃO**  
9. Refund excede captura: **NÃO**  
10. Release+refund cria dinheiro líquido: **NÃO COMPROVADO** (release `true` só após `concluido` via service_role)  
11. Payout duplica Transfer indevidamente: **NÃO** (mesma key idempotente)  
12. Stock=1 duas vendas válidas: **NÃO** (1 order / hold)  
13. Stock=1 duas capturas líquidas permanentes: **NÃO COMPROVADO**  
14. Bypass capacidade/reserva: **NÃO** (hold); reserva live **NÃO COMPROVADO**  
15. Cross-user financeiro: **NÃO** (salvo o P0 é o próprio buyer vs catálogo do seller)  
16. Cross-user dados sensíveis: **NÃO** comprovado  
17. Buyer assume seller/admin: **NÃO**  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO** (unpaid bloqueado)  
20. RPC DEFINER perigoso: o selo `proposta` é trigger DEFINER — **SIM** (é o P0)  
21. RLS crítico quebrado: **NÃO**  
22. Edge confia em autoridade do cliente: **parcial** — Edge lê contrato já selado na BD (envenenado no INSERT), não o `amount` do body  
23. Conclusão crítica NÃO COMPROVADA: **SIM** (captura Stripe; oversell pago)  
24. Regressão funcional: **NÃO AVALIADO** (auditor não corre QA app)  
25. Último passe nova classe P0/P1: **NÃO** (reprodução)  
26. Saturação: **NÃO**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

---

## 11. Probes

- `tool/redteam_indep_cega_20260830T1443.dart`
- `tool/redteam_indep_cega_20260830T1443_pass4.dart` … `_pass7.dart`
- Outputs: `tool/redteam_indep_cega_20260830T1443/pass1.json` … `pass7.json`, `frozen.json`
