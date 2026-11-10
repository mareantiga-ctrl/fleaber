# Fleaber — Auditoria cega independente (Red Team)

**FROZEN_AT:** `2026-08-30T16:35:00+01:00`  
**Projecto:** Supabase staging `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST (sessões criadas; captura permanente não concluída nesta ronda)  
**Produção:** não tocada  
**Fase 4:** não iniciada  
**Correcções:** nenhuma (auditoria apenas)

---

## Veredicto

**B — FAIL_P1**

Zero P0 comprovados. Um P1 confirmado e reproduzido com identidade independente: o comprador altera o montante de uma proposta **pendente criada pelo vendedor** e depois aceita-a; o contrato e a Checkout Session Stripe cobram ~1,18 € em vez do valor que o vendedor ofereceu (20–28 €) / catálogo (25–30 €).

---

## Findings

### RT1719-20 — P1 — Comprador altera proposta do vendedor e paga o preço mutado

| Campo | Valor |
|---|---|
| **Actor** | Buyer JWT (lab + helper fresco) |
| **Pré-condições** | Vendedor criou `product_offers` `offered_by=seller`, `status=pending`, amount 20–28 € |
| **Reprodução** | 1. Vendedor `POST /product_offers` amount=28 (ou 20). 2. Comprador `PATCH` o mesmo id `amount=0.50`. 3. Comprador `PATCH status=accepted` (mesmo enviando `amount=28`). 4. Comprador `POST /orders` com `product_offer_id`. 5. `create-payment-intent` |
| **Impacto** | `contract_unit_cents=50`, Stripe `server_amount_cents=118` (0,50 € + protecção). Artigo de 25–30 €. O `amount` no body do accept é ignorado (`NEW.amount := OLD.amount`). |
| **Estado** | ABERTO |
| **Prova 1** | Offer `0cbdf2a8-89c3-4794-8e9b-d99c472260e4` amount 0.50 accepted; order `c26c23a2-0ce9-44da-a429-90e78eaecb1c`; Session `cs_test_a1DdLsL1QPf2PryyMAHMtg93K7ZsBydFzwoL2uWGCie3q2eWNSiEXeR3D1` **118 cents** |
| **Prova 2 (identidade distinta)** | Helper `3469d715-ff7a-4519-9971-f29b6e7a2462`; offer `916bbbfb-de5f-4295-b8c4-edb5953fa51b`; order `725f4e09-24e9-4d3e-8ef0-13bd60d60de4`; Session `cs_test_a1C3j4fSp6RZtZaeQMqwZiITsMMGbyVzlrDjsXHJ27yf44JToOlmM7FNzj` **118 cents** |

Distinção Stripe: **SESSION CRIADA** a 118 cents. **CAPTURA REAL TEST:** não paga nesta ronda. O valor da Session é a autoridade de cobrança; não é eco de cliente (`body.amount` no checkout de catálogo foi ignorado noutros testes).

Helper estrangeiro `PATCH` na oferta alheia: `200 []` (RLS, sem escrita).

### RT1719-11 — P2 — Montante de proposta pending mutável + accept sem pin

Mesma raiz. Variante: comprador muta a **própria** proposta 25 € → 0,50 €; vendedor `PATCH status=accepted` (mesmo com `amount=22` no body) fica 0,50 €; checkout 118 cents (`cs_test_a1VflgwbAvdKbe3TiGCrwvHCU0zh2ho0lk17x5TLu4oN3RLbDcPOOhCuVS`). Race 10× patch vs accept: **5/10** aceites a 0,50 €. Requer o vendedor a aceitar (TOCTOU / UI stale). Não sobe a P1 autónomo; alimenta RT1719-20.

### RT1719-30 — P3 — Reserva live qty=99 como pending

Buyer `INSERT live_reservation_requests` `requested_qty=99` `status=accepted` → persistido **pending**, qty **99**, `queue_position=2` (`f9df80dd-60d6-4e9e-8e2a-2aa61c9a41ff`). Não comprovado convert/checkout de 99 unidades. Fila de espera, não venda.

---

## Superfícies testadas

AUTH/PROFILES, ORDERS, FSM, PRODUCTS, PRICE/CONTRACT, QTY, CHECKOUT, STRIPE SESSION, SETTLE GET, BAG, WALLET, LEDGER/PAYOUT RPCs, STOCK, REFUNDS (edge+RPC), DISPUTES, LIVE/RESERVATIONS, OFFERS, TIPS, CHAT, REVIEWS, STORAGE, MUX/LIVEKIT, PS/OCR (token), RPCs (177 via OpenAPI service_observe), RLS, Edge Functions listadas no código.

---

## Invariantes (tentativa de refutação)

| ID | Resultado |
|---|---|
| A Stripe = contrato servidor | **FALHA no fluxo proposta** (118 cents vs 20–30 €). Catálogo directo: 12,34 € → 1361 cents; após drop de catálogo para 1 €, checkout manteve 4265 cents (40 € selado). |
| B Buyer não define preço/qty no checkout | **Parcial.** `body.amount`/`qty`/`line_total` ignorados. **SIM via PATCH em `product_offers.amount`.** Qty de order: hold `order_hold_exceeds_stock`. |
| C Release/refund ≤ fundos plataforma | MB WAY concluido + `release` → `200 true`, **delta wallet vendedor = 0,00 €**. |
| D Uma unidade / duas vendas | INSERT 2.º order stock=1 → `order_hold_exceeds_stock`. 0/10 races INSERT duplo. |
| E JWT cria saldo/PI/payout | PATCH wallet 0 rows; `payout_debit`/`payout_finish` 403; `ensure_wallet` cruzado 403; INSERT order `pago`/Stripe IDs stripped. |
| F Off-platform → saldo Fleaber | **Não refutado** (delta 0). |
| G Refund > captura | Sem captura; buyer `refund-order` 403; seller 422 sem PI. |
| H Parties coerentes | Ghost seller INSERT 403 `order_buyer_attribution_denied`. Helper INSERT as lab buyer falhou. |
| I/J Payout 1:1 Transfer | JWT não chama debit/finish. (Pass1: seller chamou `create-connect-account` amount=100 **próprio** — levantamento legítimo 1 €, efeito colateral do probe.) |
| K Catálogo posterior | Selado 4000 cents; checkout 4265 após price=1 €. |
| L Offer só com autoridade | **FALHA:** comprador escreve amount na proposta do vendedor e aceita. |

---

## Races

| Teste | Resultado |
|---|---|
| 2 INSERT order stock=1 ×10 | 0/10 ambos OK |
| 2 checkout mesma order | Ambos 200, **mesmo** `cs_test_a1WIzAgTToxhAvWja16YuUKpuNgoUacNw6wCWJCwWCkNrOyxtlCdmq7Qqm` (slot/idempotência) |
| 2 checkout 2 buyers stock=1 | 2.º order nem chega a existir |
| Offer PATCH vs accept ×10 | 5/10 aceite a 0,50 € |
| Dual refund / dual payout JWT | debit/finish 403 |

---

## Stripe TEST

| | |
|---|---|
| SESSION CRIADA | Várias, incl. 118 cents (P1) e 1361/4265/1425 cents (catálogo/bag) |
| CAPTURA REAL TEST | Não concluída (sem `sk_test` local; não se pagou 4242) |
| CAPTURA LÍQUIDA PERMANENTE | NÃO COMPROVADO |

---

## Matriz (resumo)

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEV | EVIDÊNCIA |
|---|---|---|---|---|---|---|
| product_offers | PATCH amount na oferta do seller + accept | buyer / helper | 200 amount=0.50 accepted | contrato 50 cents, Session 118 | P1 | pass3/pass4 JSON |
| orders | INSERT status=pago + stripe + contract=1 | buyer | 201 status=reserva_pendente contract=1234 PI=null | selo OK | — | pass1 |
| orders | PATCH money/qty | buyer | 403 order_money_fields_immutable | — | — | pass1 |
| orders | PATCH pago (plataforma, sem PI) | buyer/seller | 200, status final reserva_pendente | FSM silent revert | — | pass1 |
| wallets | PATCH balance 99999 | buyer/seller/anon | 200 [] / sem mudança | — | — | pass1 observe |
| rpc payout_finish | p_failed=true | JWT | 401/403 | — | — | pass2 |
| rpc release | MB WAY concluido | buyer | 200 true, Δwallet=0 | — | — | pass2 |
| edge create-payment-intent | amount=50 qty=99 | buyer | 200 server_amount_cents=1361 | cliente ignorado | — | pass1 |
| edge refund-order | order alheia | buyer | 403 | — | — | pass1 |
| edge stripe-webhook | evento sem assinatura | anon | 400 | — | — | pass1 |
| reviews | INSERT sem order | buyer | 400 review_order_required | — | — | pass2 |
| profiles | PATCH user_type=admin | buyer | 200, user_type continua comprador | — | — | pass1 |
| lives stream_key | SELECT | buyer/seller | 403 | — | — | pass2 |
| livekit-mux-publish | token live do seller | buyer | 403 | — | — | pass2 |
| stock | INSERT qty=2 stock=1 | buyer | 400 hold_exceeds_stock | — | — | pass2 |
| bag | line_total=1 shipping hand | buyer | 200 server 1425 | portes selados | — | pass3 |
| storage disputes | list prefix seller | buyer | 200 [] | — | — | pass3 |

---

## Tabela de findings

| ID | SEV | TÍTULO | ACTOR | PRÉ | REPRO | IMPACTO | ESTADO |
|---|---|---|---|---|---|---|---|
| RT1719-20 | P1 | Buyer muta proposta do seller e Stripe cobra o mutado | buyer JWT | oferta seller pending | PATCH amount + accept + checkout | 118 cents vs 20–30 € | ABERTO |
| RT1719-20b | P1 | Reprodução independente (helper) | helper JWT | idem | idem | 118 cents vs 25 € | ABERTO (mesma classe) |
| RT1719-11 | P2 | Amount pending mutável; accept não faz pin | buyer+seller | proposta buyer | PATCH + seller accept | TOCTOU 5/10 | ABERTO |
| RT1719-30 | P3 | Reserva qty=99 pending | buyer | live item | INSERT | waitlist, não venda | ABERTO |

---

## Lacunas

- Captura Stripe TEST não paga (P1 fica em **Session criada**, não captura líquida).
- Oversell com duas **capturas** permanentes: NÃO COMPROVADO (2.º hold bloqueado).
- PS/OCR sem device token válido.
- Mux seller em quota diária; stream keys não lidas via PostgREST.
- 177 RPCs inventariadas; shotgun vazio/assinatura incompleta em várias; não se chamou cada uma com todos os argumentos.
- Pass 4 só reproduziu a classe P1; não esgotou rifas/bundles/partial refund com captura.

**Saturação:** SIM para **nova classe P0/P1** no último passe (pass 4 = reprodução da mesma classe). Não SIM no sentido de cobertura absoluta de todos os RPCs.

---

## Checklist final

1. P0 aberto: **NÃO**  
2. Quantos P0: **0**  
3. P1 aberto: **SIM**  
4. Quantos P1: **1 classe** (RT1719-20 / 20b)  
5. Buyer manipula preço autoritativo: **SIM** (via `product_offers.amount`; não via `body.amount` no checkout de catálogo)  
6. Buyer manipula qty autoritativa (order): **NÃO** (hold). Reserva qty=99 pending: sim, sem conversão comprovada.  
7. Seller falsifica pagamento plataforma: **NÃO** (PATCH pago sem PI não grava pago)  
8. JWT cria saldo/fundos: **NÃO**  
9. Refund > captura: **NÃO** (não exercido com captura)  
10. Release+refund cria dinheiro: **NÃO** (MB WAY Δ=0)  
11. Payout duplica Transfer: **NÃO** (JWT sem debit)  
12. Stock=1 duas vendas válidas: **NÃO** (2.º INSERT bloqueado)  
13. Stock=1 duas capturas permanentes: **NÃO COMPROVADO**  
14. Bypass capacidade/reserva: **PARCIAL** qty=99 pending; convert não provado  
15. Cross-user financeiro: **SIM** (buyer altera proposta do seller — preço)  
16. Cross-user dados sensíveis: **NÃO** (chats/events helper vazios; stream keys 403)  
17. Buyer assume seller/admin: **NÃO**  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO**  
20. RPC SECURITY DEFINER perigoso executável: **NÃO** (payout_* 403; release true sem crédito)  
21. RLS crítico quebrado: **NÃO** (excepto writes em `product_offers.amount` que a policy permite)  
22. Edge confia autoridade do cliente no checkout: **NÃO** (exceto o contrato já selado a partir da oferta mutada)  
23. Conclusão crítica NÃO COMPROVADA: **SIM** (captura Stripe permanente; oversell pago)  
24. Regressão funcional: **NÃO** (não se alterou código)  
25. Último passe nova classe P0/P1: **NÃO** (pass 4 reproduziu 20)  
26. Saturação: **SIM** (classe P1 estável; sem nova classe no último passe) com lacunas acima  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

---

## Probes

`tool/redteam_blind_indep_20260830T1719/`  
`pass1_discover.dart` · `pass2_money_races.dart` · `pass3_compose.dart` · `pass4_repro.dart`  
Bruto: `out/pass1.json` … `out/pass4.json` · `frozen.json`

**Efeito colateral do probe:** Pass 1 chamou `create-connect-account` como **seller** com `amount=100` (próprio JWT) → Transfer TEST `tr_1UABY6H7FWYUN3jhGQE39KdG` (~1 €). Não é exploit; é levantamento da conta lab.
