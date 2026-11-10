# Fleaber — Auditoria cega independente (Red Team)
## Staging · Pós-hardening · NÃO produção · NÃO Fase 4 · NÃO correcções

**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST (Sandbox «Área restrita de Mare Antiga Unipessoal, Lda»)  
**FROZEN_AT:** `2026-08-30T15:32:00Z`  
**Auditor:** Red Team independente (cego — código + schema LIVE + comportamento LIVE)  
**Identidades:** anon · buyer JWT laboratório (`bfcbeeee-…`) · seller JWT laboratório (`980f4fa1-…`) · helper descartável (utilizador fresco, sem staff)

---

## Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0. Zero P1. Invariantes financeiros atacados com prova LIVE (incluindo captura Stripe TEST + 2.ª sessão paga + refund da PI duplicada + race de refund). Composição e races executadas. Último passe completo sem nova classe P0/P1.

Existem P2/P3 de endurecimento (sessões Checkout paralelas; enumeração email→UUID). Não elevam a falha de autoridade financeira.

---

## Checklist final

| # | Pergunta | Resposta |
|---|----------|----------|
| 1 | P0 aberto encontrado | **NÃO** |
| 2 | Quantos P0 | **0** |
| 3 | P1 aberto encontrado | **NÃO** |
| 4 | Quantos P1 | **0** |
| 5 | Buyer manipula preço autoritativo | **NÃO** |
| 6 | Buyer manipula qty autoritativa | **NÃO** |
| 7 | Seller falsifica pagamento plataforma | **NÃO** |
| 8 | JWT cria saldo/fundos | **NÃO** |
| 9 | Refund excede captura | **NÃO** |
| 10 | Release+refund cria dinheiro líquido | **NÃO** |
| 11 | Payout duplica Transfer indevidamente | **NÃO** (mesma key → mesma Transfer; keys distintas → Transfers distintas, 1€ cada) |
| 12 | Stock=1 duas vendas válidas | **NÃO** |
| 13 | Stock=1 duas capturas líquidas permanentes | **NÃO** |
| 14 | Bypass de capacidade/reserva | **NÃO** (com a evidência obtida) |
| 15 | Cross-user financeiro | **NÃO** |
| 16 | Cross-user dados sensíveis | **NÃO** (IBAN só com relação; helper sem IBAN) |
| 17 | Buyer assume seller/admin | **NÃO** (`user_type=admin` não persistiu; `batata_is_admin`=false; Mux create 403) |
| 18 | Seller assume buyer/admin | **NÃO** |
| 19 | Reviews forjadas/duplicadas | **NÃO** |
| 20 | RPC/SECURITY DEFINER perigoso | **NÃO** (payout debit / settle tip / credit wallet / finalize refund: EXECUTE negado a JWT) |
| 21 | RLS crítico quebrado | **NÃO** |
| 22 | Edge confia em autoridade do cliente | **NÃO** (amount 50 cêntimos → cobrança 2060/852 cêntimos de contrato; `buyer_id` tem de coincidir com JWT) |
| 23 | Conclusão crítica NÃO COMPROVADA | **SIM** (parcial: 176 RPCs no OpenAPI — nem todas as assinaturas foram varridas; Mux/LiveKit stream-key como vendedor não esgotado; janela Stripe entre captura B e refund medida só neste ciclo TEST) |
| 24 | Regressão funcional relevante | **NÃO** (auditoria sem alterações de produto) |
| 25 | Último passe nova classe P0/P1 | **NÃO** |
| 26 | Saturação atingida | **SIM** |
| 27 | Produção tocada | **NÃO** |
| 28 | Fase 4 iniciada | **NÃO** |

---

## Superfícies testadas

AUTH/PROFILES · ORDERS + FSM · PRODUCTS/CATALOG/PRICE/QTY · CHECKOUT · STRIPE SESSION + CAPTURA TEST + SETTLE/RETURN · WEBHOOK (unsigned) · BAG (não multi-seller neste freeze) · WALLET · LEDGER/PAYOUT · STOCK · REFUNDS (race) · DISPUTES · LIVE / LIVE ITEMS / RESERVAS · OFFERS · RAFFLES (assinatura RPC) · TIPS wallet · CHAT · REVIEWS · STORAGE · MUX create (buyer) · PS pairing/OCR · RPCs privilegiados · RLS · Edge Functions listadas.

---

## Invariantes — resultado da refutação

| ID | Invariante | Resultado |
|----|------------|-----------|
| A | Stripe cobra o contrato do servidor | **Mantido.** Body `amount=50` → `server_amount_cents=2060` (15,50€ + CTT + protecção). Catálogo 20€ selado; produto baixado a 1€ → checkout **2165** cêntimos (contrato, não 1€). |
| B | Buyer não define preço/qty | **Mantido.** `contract_unit_cents=1` no INSERT → selo 1250/4000. Qty 99 → `order_hold_exceeds_stock`. PATCH qty/price/PI/`amount_paid` **não persiste** (observe service_role). |
| C | Release/refund/payout ≤ fundos recebidos | **Mantido** nas provas. MB WAY concluído+review 5★: wallets inalteradas. Refund Stripe: wallets inalteradas (reembolso no cartão). |
| D | Uma unidade ≠ duas vendas válidas | **Mantido.** 10 INSERTs paralelos em stock=1 → **1** hold. |
| E | JWT não cria saldo/PI/session/payout authority | **Mantido.** INSERT wallets 403. `batata_wallet_payout_debit` / `batata_credit_wallet_once` / `batata_settle_live_tip_from_stripe` / `batata_finalize_stripe_order_refund`: permission denied. PATCH capture fields revertido. |
| F | Pagamento off-platform não minta saldo plataforma | **Mantido.** Ciclo MB WAY seller→pago, buyer→concluido, review 5★: `wallet_release` null; seller 30,26→30,26. |
| G | Refund acumulado ≤ captura | **Mantido.** Race 6× refund: um `re_3UAAcDH7FWYUN3jh1HLEPwXo` de 852 cêntimos; retries `already_refunded`. |
| H | Parties coerentes | **Mantido.** INSERT com `buyer_id` alheio → `order_buyer_attribution_denied`. Checkout helper → `Invalid checkout user` / `order does not belong to buyer`. |
| I | Uma intenção payout → no máximo uma Transfer | **Mantido.** Idempotency key repetida → mesmo `tr_1UAAVcH7FWYUN3jhDFRTqqcx`. |
| J | Duas intenções distintas → duas Transfers | **Mantido.** Key diferente → `tr_1UAAVdH7FWYUN3jh9vWtcp9L`; saldo −1€ ×2. |
| K | Catálogo posterior não altera contrato aceite | **Mantido.** Preço 20€ → 1€ no produto; checkout 21,65€. |
| L | Offer só altera preço com autoridade real | **Mantido.** Self-accept buyer 403 `offer_accept_not_authorized`. Seller accept 5€ → contrato 500 cêntimos. Mutação amount pós-accept não baixou para 0,50€. |

---

## Races

| Race | Resultado |
|------|-----------|
| 10× INSERT order stock=1 (buyer+helper) | 1 criado / 1 hold / qty produto=1 |
| 8× create-payment-intent mesma order (sequencial/burst) | 8 Session IDs (classe P2) |
| 2× create-payment-intent **paralelo** | 2 Sessions distintas; ambas pagáveis |
| 2× payout mesma idempotency key | 1 Transfer |
| 2× payout keys diferentes | 2 Transfers, 2 débitos de 1€ |
| 6× refund-order paralelo | 1 refund Stripe; extras idempotentes ou 500 in-progress da key Stripe |
| 2 capturas TEST mesma order | PI A permanece; PI B **reembolsada** (`sec_dup_session_pi_refunded` / `re_3UAAe6H7FWYUN3jh0MQWV7NI`) |

---

## Stripe TEST

| Etapa | Evidência |
|-------|-----------|
| SESSION CRIADA | `cs_test_a1p9fmV05BefGyqxYwac8BKjMO5s0TPAUxSFwYnvxIJNnEbFIHLcIC2MIV` e `cs_test_a1HEqpMjpcIAIynBGqDklWHVf2GI1myqDzAAqotpA9XkGF71lnk3GyIJP0` · 8,52€ |
| CAPTURA REAL A | Checkout Sandbox, cartão `4242…4242`, order `e44e602e-…` **pago**, `amount_paid_cents=852`, `pi_3UAAcDH7FWYUN3jh1hnfGXPN`, produto qty=0 sold=true |
| CAPTURA REAL B | Segunda sessão aceite no Checkout (ainda 8,52€ com stock já 0) |
| CAPTURA LÍQUIDA PERMANENTE | **Uma.** Settle B: `sec_dup_session_pi_refunded` + retry `already_refunded`. Order continua uma PI. Stock não duplicou. |
| REFUND SELLER da venda A | `cancelado`, stock restaurado qty=1, um `refund_id` |

Webhook unsigned: `400 missing_signature`. GET settle sessão não paga: texto «Pagamento ainda não confirmado». `sec-fase2-e2e-oversell` com JWT buyer: `401 Só service_role`.

---

## Findings

### RTI1606-P2-01 — Sessões Checkout paralelas na mesma order (P2)

**Actor:** buyer JWT  
**Pré-condições:** order `reserva_pendente`; dois POSTs simultâneos a `create-payment-intent`.  
**Reprodução:** `Future.wait` de 2 invokes → 2 `cs_test_*` distintos; ambos os URLs Checkout aceitam pagamento TEST.  
**Impacto:** Segunda captura ocorre; o settle reembolsa a PI duplicada. Não é segunda venda nem captura líquida permanente. Risco residual: janela de fundos retidos, taxas Stripe de refund, UX de «paguei duas vezes».  
**Estado:** OPEN (hardening: uma Session viva por order **antes** do pagamento, não só no settle).  
**Evidência:** `out/pay_meta.json`, `out/observe` via `observe_pay.dart`, evento `sec_dup_session_pi_refunded`.

### RTI1606-P3-01 — Oracle email→UUID (P3)

**Actor:** helper JWT fresco  
**Reprodução:** `batata_find_user_id_by_email` com email do seller de laboratório → UUID do seller. Email inexistente → `null`.  
**Impacto:** Enumeração de contas. Sem leitura de IBAN por helper (`batata_seller_direct_payment_details` → `[]`).  
**Estado:** OPEN (higiene / rate-limit já referido no SQL; prova LIVE: 1 hit imediato).

### RTI1606-P3-02 — PATCH financeiro HTTP 200 sem persistência (P3)

**Actor:** buyer/seller JWT  
**Reprodução:** PATCH `status=pago`, `amount_paid_cents`, `stripe_payment_intent_id` devolve 200 + representação; observe service_role: campos inalterados.  
**Impacto:** Não é bypass. Pode confundir clientes/testes que tratam 200+body como mutação.  
**Estado:** OPEN (defesa em profundidade de API).

Falsos positivos descartados: `batata_get_my_payout_details` (dados próprios); pairing PS pelo buyer de laboratório (é `seller_helpers` com `can_manage_reservations=true` — helper fresco recebeu `not_allowed`).

---

## Lacunas (explícitas)

- Nem todas as 176 RPCs OpenAPI foram chamadas com a assinatura correcta (varredura por nome + parâmetros típicos).
- LiveKit token/egress e Mux stream-key: buyer não tem SELECT em `lives` (403); não se esgotou o caminho vendedor (custos Mux).
- OCR ingest com token roubado: não aplicável ao helper (pairing `not_allowed`).
- Bag multi-seller e partial refund Stripe da mesma PI partilhada: não recriados neste freeze (ciclo único 8,52€ reembolsado na íntegra).
- Janela temporal captura B → refund: observada neste ciclo; não medida em atraso de horas sem settle/webhook.

---

## Saturação

**SIM.** Três passes conceptuais:

1. Cobertura (RLS, RPC privilegiados, Edge, storage, FSM, ofertas, reviews).  
2. Variantes (MB WAY, catálogo retroactivo, checkout hostil, stock=1, payout keys).  
3. Composição + races + **captura Stripe TEST dupla** + refund concorrente.

Último passe: sem nova classe P0/P1 (a classe «2 Sessions» foi **despromovida** de hipótese P0/P1 para P2 após prova de refund da PI duplicada).

---

## Produção / Fase 4

Não tocadas. `service_role` só para fixtures, observe e cleanup de contas helper. Exploits reproduzidos com JWT/anon/Stripe TEST.
