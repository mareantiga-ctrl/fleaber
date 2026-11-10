# Fleaber — Auditoria cega independente (Red Team)

**Projecto staging:** `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST apenas  
**Produção:** não tocada  
**Fase 4:** não iniciada  
**Correcções:** não implementadas  

**FROZEN_AT:** `2026-08-29T16:51:36+01:00`

**Veredicto:** **B — FAIL_P1**

---

## 1. Âmbito e método

Auditoria adversarial ao estado LIVE de staging. Identidades: anon, buyer lab, seller lab, buyer descartável, chamadas directas a PostgREST / RPC / Edge (sem Flutter). `service_role` só para fixtures, observação e cleanup — nenhum finding de autoridade JWT depende de service_role.

Três passes conceptuais + um quarto passe de variantes após o P1 de Stripe:

| Passe | Foco |
|-------|------|
| 1 | Cobertura: RLS, RPC, Edge, auth, money, stock, reviews, chat, storage, Mux |
| 2 | Invariantes financeiros, FSM, catálogo vs contrato, wallet RPCs |
| 3 | Composição, races (stock=1, sessões paralelas), Stripe TEST até captura |
| 4 | Variantes da classe P1 (retry settle, sessão duplicada em order já paga) |

Histórico de auditorias / hardening **não foi consultado** antes deste freeze.

---

## 2. Findings

### F-RTF-P1-001 — P1 — Settle fail-closed na quote impede refund de oversell após captura Stripe

**Actor:** dois buyers autenticados (JWT), produto `quantity=1`, duas Checkout Sessions criadas em paralelo, ambos pagam em Stripe TEST.

**Pré-condições:**
- Produto marketplace com 1 unidade.
- INSERT de duas orders `reserva_pendente` (ambos HTTP 201) — stock **não** é reservado no INSERT.
- `create-payment-intent` cria **duas** Sessions (ambas HTTP 200, €9,05 cada).

**Reprodução:**
1. Buyer A e buyer B (conta descartável) criam order cada um no mesmo `product_id` com stock=1.
2. Ambos pedem Checkout Session (JWT).
3. Buyer A paga Session A (cartão TEST 4242). Settle: order A → `pago`, `amount_paid_cents=905`, `stock_units_applied=1`, produto `quantity=0` / `is_sold=true`.
4. Buyer B paga Session B. Stripe redirecciona para `checkout_return=success&session_id=cs_test_a1XKZ38…`.
5. Edge regista `sec_p001_settle_order_quote_failed` com `Checkout blocked: quantity 1 exceeds available stock 0.`
6. GET de re-settle (anon e JWT buyer) devolve **HTTP 500** com texto **«PAGAMENTO RECEBIDO»** + «Não foi possível validar o pagamento».
7. Order B permanece `reserva_pendente`, **sem** `stripe_payment_intent_id`, **sem** `amount_paid_cents`, **sem** `stripe_refund_id`. Evento `sec_fase2_oversell_refund` **ausente**.

**Causa (código actual, não comentários):** em `create-payment-intent`, o return-path recompute `resolveServerCheckoutQuote` **antes** de `settleOrderPaidOrRefundOversell`. A quote exige `products.quantity >= qty`. Com stock 0 a quote lança; o catch fail-closed **não chama** `refundOversoldStripeOrder`. O webhook reutiliza o mesmo GET.

**Impacto:**
- Uma unidade física → **uma** venda Fleaber válida (`pago`).
- Segunda captura Stripe TEST **reconhecida pela Edge** («PAGAMENTO RECEBIDO») **sem** order paga e **sem** refund persistido.
- Wallet seller/buyer **inalteradas** (39,81 / 6,41) — não há mint nem segundo payout.
- Buyer B fica cobrado sem artigo; fundos ficam na conta Stripe TEST da plataforma até refund manual.

**Não é P0:** o atacante não mint wallet, não obtém segunda venda válida, não desvia payout. É P1 porque a captura extra é reproduzível e o caminho automático de oversell-refund é **saltado**.

**Estado:** ABERTO (não corrigido nesta auditoria).

**Evidência:** `pass3_stripe_observe.json`, `pass4_raw.json`, Session A `cs_test_a1uvaijQah20VxtK1edSVq7BwzZrJ6c3GSdxd8oxw1obUszAgYfxw8yWR8` / PI `pi_3U9oSiH7FWYUN3jh1byXTunx`; Session B `cs_test_a1XKZ38IARekmVOMlG01klhh5s3dBM4HcXRu62Obcs58MOiTSVTr2nKclT`; orders `b241022c-…` (pago) e `10c41bc5-…` (pendente); produto `7c7de7b2-…`.

**Limitação:** não há `STRIPE_SECRET` no env de laboratório; o estado do PaymentIntent B no Dashboard Stripe não foi lido via API. A prova de captura usa o redirect de sucesso do Checkout + a mensagem «PAGAMENTO RECEBIDO» da Edge.

---

### F-RTF-P2-001 — P2 — Stock não reservado no INSERT: N orders pendentes + N Sessions na última unidade

**Actor:** buyers JWT.

**Reprodução:** INSERT paralelo em `quantity=1` → múltiplos 201; 8 INSERTs 201; 2 Sessions 200; 10 Sessions na **mesma** order 200.

**Impacto:** condição necessária para F-RTF-P1-001. Por si só **não** prova duas vendas `pago`. Classificado P2 (capacidade de reserva bypassada; o dano económico materializa-se no settle/Stripe).

**Estado:** ABERTO (desenho). Relacionado com P1.

---

### F-RTF-P2-002 — P2 — Conluio MB WAY: seller marca `pago` + buyer `concluido` + review

**Actor:** seller + buyer lab (conluio).

**Reprodução:** order MB WAY não paga via Stripe; seller PATCH `status=pago` **persiste** e `stock_units_applied=1`. RPC de release wallet **não** minta. Buyer PATCH `concluido` **sucesso** (salta `enviado`). Review INSERT 201 com `purchase_verified: false`. Segunda review na mesma order: **409 `review_duplicate`**.

**Impacto:** reputação / attest off-platform e consumo de stock **sem** captura Stripe. **Não** cria saldo Fleaber. Não é falsificação de pagamento de plataforma.

**Estado:** ABERTO. Order de laboratório `bb56dbbf-589f-4a5b-ba2d-81526e87cc33`.

---

### F-RTF-P3-001 — P3 — `price_total` cliente pode persistir no INSERT; contrato selado no checkout

INSERT com `price_total=0.01` e `status=pago` + PI falso: trigger força `reserva_pendente` e limpa PI/`amount_paid`. `contract_unit_cents` sela ao catálogo. Checkout cobra quote servidor (ex. 2690). Catálogo 25→1 após selo: checkout continua 2690.

**Impacto:** eco/persistência de campo não autoritativo. Checkout não segue o `price_total` hostil.

---

### F-RTF-P3-002 — P3 — RPC `batata_record_buyer_purchase_ledger` invocável por JWT falha 42P10

Buyer POST `{p_order_id}` → 400 `ON CONFLICT specification`. Não comprovado mint de ledger. Higiene / DEFINER quebrado no caminho autenticado.

---

### Descartaidos (não findings)

- Lookup de email: buyer em email de seller → `null`; não é PII leak.
- Wallet PATCH HTTP 200 `[]`: saldo inalterado.
- OpenAPI anon 401.
- Stream keys: `lives` 403; `hub_lives_public` só playback.
- Mux create buyer 403.
- Webhook sem assinatura 400.
- `refund-order` buyer 403.
- `fase2_e2e_settle` JWT rejeitado.
- Tip `tip_id` cliente rejeitado.
- Chat inject alheio 403.
- Draw raffle / mark sold como buyer: `not_allowed`.
- Sessão duplicada em order **já `pago`:** 400 `order status 'pago' cannot start payment` (pass 4).

---

## 3. Invariantes financeiros (tentativa de refutação)

| ID | Invariante | Resultado live |
|----|------------|----------------|
| A | Stripe cobra o contrato servidor | **Mantém** no POST checkout (amount/qty/item_price cliente ignorados). **Quebra parcial** no ciclo dual-pay: segunda Session cobra o mesmo contrato **depois** do stock esgotado. |
| B | Buyer sem autoridade preço/qty | **Mantém** (quote servidor). |
| C | release/refund/payout ≤ fundos legítimos | Refund JWT sem PI: 422 / `no_platform_funds`. Dual-pay: **segunda captura sem refund automático** (P1) — plataforma **recebe** a mais, não **paga** a mais. |
| D | Uma unidade ≠ duas vendas válidas | **Mantém** no FSM Fleaber (só uma `pago`). |
| E | JWT não cria wallet/ledger/PI/payout | **Mantém** (credit/debit/payout/finalize 403). |
| F | Pagamento off-platform ≠ saldo | **Mantém** (MB WAY attest sem mint). |
| G | Refund ≤ captura | Não comprovado excesso; unpaid refund bloqueado. |
| H | Parties coerentes | Troca product/seller/buyer no checkout **bloqueada**. |
| I | Uma intenção payout → ≤1 Transfer | Não se completou payout Stripe TEST nesta ronda (RPC 403). |
| J | Duas intenções distintas → duas Transfers | Não exercido (sem payout). |
| K | Catálogo posterior ≠ contrato selado | **Mantém** (25→1, checkout 2690). |
| L | Offer/bag/discount | Bag `line_total_cents=1` ignorado; quote 4790. |

---

## 4. Races

| Race | Resultado |
|------|-----------|
| 2 INSERTs stock=1 | 2×201, qty produto ainda 1 |
| 8 INSERTs stock=1 | 8×201 |
| 2 Checkout Sessions stock=1 | 2×200, €9,05 |
| 10 Sessions na mesma order | 10×200 |
| 2 pagamentos Stripe TEST na última unidade | 1×`pago` + 1×captura sem settle/refund (P1) |
| Retry GET settle Session B (anon + JWT) | 2×500, mesma quote fail, sem refund |
| 2 reviews mesma order | 409 duplicate |
| 2 payouts JWT | 403 |
| Wallet credit/debit JWT | 403 |

---

## 5. Stripe TEST

| Sessão | Estado Fleaber | Captura |
|--------|----------------|---------|
| A `cs_test_a1uvaijQ…` | order `pago`, 905 cents, stock aplicado | **CAPTURA REAL TEST** persistida |
| B `cs_test_a1XKZ38…` | order `reserva_pendente`, sem PI/refund | **CAPTURA REAL TEST** (redirect success + «PAGAMENTO RECEBIDO»); **CAPTURA LÍQUIDA PERMANENTE na BD Fleaber: NÃO**; **refund automático: NÃO observado** |

Duas Sessions ≠ duas vendas. Duas Sessions **não** são automaticamente seguras: a segunda captura não foi reembolsada pelo caminho oversell.

---

## 6. Superfícies atacadas

AUTH/PROFILES, ORDERS/FSM, PRODUCTS/CATALOG/PRICE/QTY, CHECKOUT/STRIPE SESSION/SETTLE/WEBHOOK/RETURN, BAG, WALLET/LEDGER/PAYOUT, STOCK, REFUNDS (full/partial), DISPUTES (INSERT), LIVE/RAFFLE RPCs, TIPS, CHAT, REVIEWS, STORAGE (`chat_media` listing — fotos marketplace públicas), MUX, OCR/pairing, RPCs SECURITY DEFINER (credit, debit, payout, refund, settle tip, admin list, join raffle IDs mortos), RLS SELECT/INSERT/UPDATE, Edge direct body tampering.

**Lacunas:**
- Stripe Dashboard/API PI B (sem secret no lab).
- Payout Transfer completa (JWT sem autoridade; não se usou service_role para «provar» payout).
- Rifa activa: query `is_active` 400 (coluna inexistente); joins com IDs mortos → `raffle_not_found`.
- Webhook `checkout.session.settled` **não** apareceu nos eventos da Session B (endpoint pode falhar 500 e retry, ou não estar ligado) — o GET return já correu e falhou da mesma forma.
- Bag dual-pay (dois artigos) não pago até ao fim em TEST.
- Live reservation qty RPC assinatura exacta não esgotada após P1.

---

## 7. Saturação

- Superfícies críticas atacadas: SIM  
- Invariantes financeiros testados: SIM  
- Composição executada: SIM (order × stock × session × settle × return)  
- Races executadas: SIM  
- Último passe (4) nova classe P0/P1: **NÃO** (só confirmação da classe P1 do passe 3)  
- **SATURAÇÃO = SIM** (com P1 aberto documentado)

---

## 8. Checklist final

1. P0 aberto encontrado: **NÃO**  
2. Quantos P0: **0**  
3. P1 aberto encontrado: **SIM**  
4. Quantos P1: **1**  
5. Buyer consegue manipular preço autoritativo: **NÃO**  
6. Buyer consegue manipular qty autoritativa: **NÃO**  
7. Seller consegue falsificar pagamento plataforma: **NÃO** (Seguro). MB WAY attest off-platform: P2.  
8. JWT consegue criar saldo/fundos: **NÃO**  
9. Refund pode exceder captura: **NÃO** (não comprovado excesso; unpaid bloqueado)  
10. Release+refund cria dinheiro líquido: **NÃO**  
11. Payout pode duplicar Transfer indevidamente: **NÃO** (não exercido até Transfer)  
12. Stock=1 pode produzir duas vendas válidas: **NÃO**  
13. Stock=1 pode produzir duas capturas líquidas permanentes: **SIM** no sentido Stripe (2ª captura reconhecida, sem refund Fleaber); **NÃO** no sentido duas rows `amount_paid_cents`. Ver P1.  
14. Existe bypass de capacidade/reserva: **SIM** (INSERT + dual Session)  
15. Existe cross-user financeiro: **NÃO**  
16. Existe cross-user de dados sensíveis: **NÃO** (fotos públicas de catálogo excluídas)  
17. Buyer pode assumir autoridade seller/admin: **NÃO**  
18. Seller pode assumir autoridade buyer/admin: **NÃO**  
19. Reviews podem ser forjadas/duplicadas: forja sem order/paga alheia **NÃO**; duplicada **NÃO**; conluio off-platform **P2**  
20. RPC/SECURITY DEFINER perigoso encontrado: **NÃO** (P0/P1). 42P10 = P3.  
21. RLS crítico quebrado: **NÃO**  
22. Edge Function confia em autoridade do cliente: **NÃO** no quote; o P1 é fail-closed da quote vs refund.  
23. Alguma conclusão crítica ficou NÃO COMPROVADA: **SIM** (PI B no Stripe API; payout Transfer; webhook delivery)  
24. Houve regressão funcional relevante: **NÃO** (auditoria não alterou produto)  
25. Último passe encontrou nova classe P0/P1: **NÃO**  
26. Saturação atingida: **SIM**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**  

---

## 9. Matriz (ataques materiais)

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA |
|------------|--------|------------|-----------|---------|------------|-----------|
| CHECKOUT×STOCK×STRIPE | Dual Session + dual Pay stock=1 | buyer A + buyer B | 1 pago + 1 PAGAMENTO RECEBIDO sem refund | 2ª captura sem venda | P1 | pass4_raw, observe |
| SETTLE GET | Re-hit success URL Session B | anon, buyer JWT | 500 quote stock 0 | refund não dispara | P1 | pass4 retry_* |
| ORDERS INSERT | qty=1 dois buyers | buyer JWT | 2×201 | reserva tardia | P2 | pass3_raw |
| CHECKOUT | amount=50 qty=99 item_price=0.01 | buyer | quote 2690 | sem autoridade cliente | — | pass2 |
| CATALOG | preço 25→1 pós-selo | seller+buyer | checkout 2690 | contrato estável | — | pass2 |
| WALLET | PATCH balance / INSERT | buyer | 200 [] / 403 | sem mint | — | pass1/2 |
| RPC | batata_credit/debit/payout | buyer JWT | 403 | — | — | pass3c |
| ORDER FSM | PATCH pago Seguro | seller | revertido | — | — | pass2 |
| ORDER FSM | PATCH pago MB WAY | seller | persiste | stock sem Stripe | P2 | pass3b |
| REVIEWS | dup mesma order | buyer | 409 | — | — | pass3b |
| REVIEWS | order alheia / sem order | buyer | bloqueado | — | — | pass2 |
| EDGE | webhook sem sig | anon | 400 | — | — | pass1 |
| EDGE | refund-order | buyer | 403 | — | — | pass1 |
| CHECKOUT | nova Session em order pago | buyer | 400 | sem 2ª Session | — | pass4 |
| MUX/LIVE | create / stream_key | buyer | 403 | — | — | pass1 |
| CHAT | inject thread alheia | buyer | 403 | — | — | pass1 |
| RPC ledger | p_order_id | buyer | 42P10 | sem mint | P3 | pass4 |
| BAG | line_total_cents=1 | buyer | quote 4790 | — | — | pass2 |

Matriz completa de cobertura (centenas de linhas HTTP) nos JSON `pass1_raw.json` / `pass3_raw.json`.

---

## 10. Tabela de findings

| ID | SEVERIDADE | TÍTULO | ACTOR | PRÉ-CONDIÇÕES | REPRODUÇÃO | IMPACTO | ESTADO |
|----|------------|--------|-------|---------------|------------|---------|--------|
| F-RTF-P1-001 | P1 | Quote fail-closed salta oversell-refund após 2ª captura | 2 buyers JWT + Stripe TEST | stock=1, 2 orders, 2 Sessions | Pagar A depois B; re-GET settle | Captura extra sem venda/refund | ABERTO |
| F-RTF-P2-001 | P2 | Sem reserva no INSERT / dual Session | buyers JWT | stock=1 | INSERTs e POSTs paralelos | Prepara oversell Stripe | ABERTO |
| F-RTF-P2-002 | P2 | MB WAY attest + review | seller+buyer | order MB WAY | PATCH pago→concluido→review | Stock/reputação off-platform | ABERTO |
| F-RTF-P3-001 | P3 | price_total INSERT hostil | buyer | INSERT | price 0.01 persiste; checkout ignora | Cosmético | ABERTO |
| F-RTF-P3-002 | P3 | ledger RPC 42P10 | buyer | GRANT execute | POST rpc | Erro SQL | ABERTO |

---

## 11. Artefactos

- Relatório: `tool/redteam_blind_f_20260829/FROZEN_REPORT.md`
- JSON: `tool/redteam_blind_f_20260829/frozen.json`
- Probes: `tool/redteam_blind_f_20260829/probes/*.dart`
- Raw: `pass1_raw.json` … `pass4_raw.json`, `pass3_pay_urls.json`, `pass3_stripe_observe.json`

---

## 12. Veredicto

**B — FAIL_P1**

Zero P0. Um P1 reproduzido (dual captura Stripe / settle quote fail-closed / sem refund automático). Invariantes de preço cliente, wallet JWT e segunda venda `pago` aguentaram-se. Produção não tocada. Fase 4 não iniciada. Nada corrigido.
