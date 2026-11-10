# FROZEN_REPORT — REDTEAM_BLIND_AT_MARKETPLACE_POS_ANAS_v1

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 3
P2 aberto: NÃO          → quantos: 0
P3 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 3

AUDITOR: REDTEAM_BLIND_AT_MARKETPLACE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T15:25:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AT1, AT2, AT3, AT4, AT5, AT6, AT7, AT8]
VEREDICTO: FAIL_P1

Prefixo fixtures: `RTAT-20260902T1607-`
Staging: `fxdknzrqjenzqcvnwqqq`
Stripe: TEST
Actors: anon · buyer JWT · seller JWT · buyer2 · seller2
service_role: só fixture / observação / cleanup

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — SIM (AT3-03: contrato de oferta 10€ + tier 10% no saco)
10. Buyer manipula qty autoritativa — NÃO (`offer_quantity_must_be_one`, hold stock)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO (`order_hold_exceeds_stock`)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B2 CPI/refund 403; Sessions duplicadas são do mesmo buyer)
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO (PATCH discounts 200 [] sem mutação)
22. Seller assume buyer/admin — NÃO (S2 accept bundle 200 [] sem mutação)
23. Reviews forjadas — NÃO
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (amount/currency body ignorados; só EUR)
27. Regressão funcional (happy path partido) — NÃO (setup_paid_order + setup_paid_bag OK)
28. Saturação atingida — SIM (8/8 lentes)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

P0 fechado. Três caminhos P1 exploráveis no checkout do saco pós-ANAS:

1. **AT3-03** — o comprador apaga `product_offer_id` na order (PATCH 200) e o saco aplica o desconto de conjunto **em cima** do preço já negociado.
2. **AT2-06** — o 2.º checkout do mesmo saco cria uma **segunda** Checkout Session Stripe ainda pagável (a 1.ª não é reutilizada nem aparece expirada).
3. **AT6-04** — a mesma falha em corrida (`Future.wait` 2×): duas `cs_` pagáveis no instante T+0.

Não se pagou as duas Sessions (Stripe TEST captura). Por isso não é P0; o caminho até captura duplicada / total abaixo do contrato de oferta está aberto.

Anti-atrofia: variantes **novas** pedidas no prompt (detach `product_offer_id`, 16 linhas / compact UUID, PATCH bundle). INSERT `accepted` forjado → 403 `bundle_status_pending_only`. Saco 16 linhas → 400 metadata 500. Oferta com qty=2 → `offer_quantity_must_be_one`. Achados exactos da lista AN/AH/AE/AB: **0 de 3**. Não é `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### AT3-03 · P1 · AT3 / AT1 — Detach `product_offer_id` empilha tier no preço de oferta

**Actor:** buyer JWT  
**Pré:** 2 produtos a 20,00 €; ofertas aceites a 10,00 €; `seller_bundle_discounts.tier_2_pct=10`; orders seladas `contract_unit_cents=1000` com `product_offer_id`.

**Repro:**
1. POST `product_offers` amount=10; seller PATCH `accepted`.
2. POST `orders` com `product_offer_id` → selo 1000.
3. `create-payment-intent` bag 2 linhas → `server_amount_cents=2165` (20,00 € itens + 1,65 € protecção; **sem** tier).
4. PATCH `orders` `{ "product_offer_id": null }` → HTTP 200; `contract_unit_cents` continua 1000; `product_offer_id` vazio.
5. Repetir bag checkout → `server_amount_cents=1955` (18,00 € + 1,55 € protecção = 10% sobre o preço **já** negociado).

**Esperado:** `product_offer_id` imutável **ou** o Edge continua a tratar o contrato como oferta (sem tier) **ou** o selo volta ao catálogo (20 €).  
**Obtido:** selo de oferta + tier de saco. Poupança 2,10 € por saco de 2 linhas (escala com `tier_5` 30% / `custom_tiers`).

**Porquê P1 não P0:** Session criada no total errado; não se capturou Stripe neste passo.

**Causa provável:** `batata_orders_seal_contract` só no INSERT; `product_offer_id` fora de `order_money_fields_immutable`; o Edge só bloqueia tier se `order.product_offer_id` ainda estiver preenchido.

Orders: `9eabd932-e0e3-49ed-8829-ce8709696483`, `b17d79ca-c045-4d1c-beed-9f770282f897` (pass1).

---

### AT2-06 · P1 · AT2 — Compact UUID: duas Sessions pagáveis no mesmo saco (sequencial)

**Actor:** buyer JWT  
**Pré:** saco 2 orders marketplace; metadata Stripe `bag_order_ids` em UUID **sem hífens** (fecho ANAS ≤500 chars).

**Repro:**
1. POST `create-payment-intent` `bag_checkout` 2 linhas → `cs_test_a1dbakWtcClHnSk0U0O3FnXRzsLoYGgXq4FW5wct4UCukl1tu6hyF2cXo9`, `reused_session=false`.
2. Mesmo POST outra vez → **outra** `cs_test_a12hslzGlEtTaE9s30Fzo4BjI0s9s2rVaVfZ120p20do9FVMo6jxKcFnHR`, outra vez `reused_session=false`.
3. GET HTML das duas `checkoutUrl`: **nenhuma** contém «This checkout session has expired»; ambas `title=Stripe Checkout`, HTTP 200.
4. A linha na BD fica só com a 2.ª `cs_`.

**Esperado:** reuse da mesma `cs_` **ou** expire Stripe da 1.ª antes de criar a 2.ª.  
**Obtido:** duas páginas de pagamento vivas para o mesmo saco.

**Porquê P1:** caminho para pagar duas vezes o mesmo saco (a BD só aponta para a última `cs_`; a 1.ª continua na Stripe). Não se fez captura dupla → não P0.

**Causa provável:** comparação `metadata.bag_order_ids` (compacto, 32 hex) ≠ ids das orders (hífenados) → o ramo de reuse nunca acerta; o expire da 1.ª Session **não** se materializa (página 1 continua pagável). `expireSharedBagCheckoutSession` também filtra `orders.id` com o compacto **sem** `hydrateCompactUuid`.

Pass1 15 linhas (~494 chars compactos) criou Session (1388 ¢). 16 linhas → 400 `bag too large for payment metadata`. O tecto 500 **funciona**; a identidade compacta vs hífen **não**.

---

### AT6-04 · P1 · AT6 — Corrida: duas `cs_` pagáveis no mesmo saco

**Actor:** buyer JWT  
**Pré:** 2 orders; `Future.wait` de dois POST bag no mesmo conjunto.

**Repro:** `Future.wait([bagCpi, bagCpi])` → duas `cs_` distintas, ambas HTML pagável no T+0 (`reused_session=false` nos dois).

**Esperado:** claim atómico → 1 Session.  
**Obtido:** `cs_test_a133TPnoz1J9ibBAdvcSIaCbvpiSnv77GO8s02otk2sivwtByhzataNTSD` e `cs_test_a13GuY7DfmVNAIs1IAngFB6E8uaW58KaRjVhKtXhiCQGoJDzvGJGPc8lRi`, ambas vivas.

**Nota:** a corrida **single-order** (AT6-01) ficou em 1 `cs_` (`reused=true` no 2.º). O buraco é do **saco**, alinhado com AT2-06.

Não é o caso exacto «14 linhas / 500 chars» nem INSERT bundle `accepted`. É a variante compact UUID + corrida pedida no prompt.

--------------------------------------------------
## LENTES (8/8)
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| AT1 Preço | INSERT `contract_unit_cents=1` reescrito para 1200. PATCH contrato 403 `order_money_fields_immutable`. Body `amount`/`currency=usd` → 400 só EUR. **Aberto via AT3-03** (preço pago ≠ contrato de oferta). |
| AT2 Session / saco | **AT2-06 aberto.** 15 linhas OK; 16 linhas bloqueadas. `product_id` cruzado nas lines → 400. `bag_orders_json` no body ignorado (mesmo total). |
| AT3 Conjunto / tier | INSERT `accepted`+total forjado → 403 `bundle_status_pending_only`. Buyer `discount_pct` forçado a 0. Buyer PATCH `accepted` → `bundle_accept_seller_only`. Seller `total_eur=0.50` recalculado a 16. Accepted congela desconto. Mix 2 `bundle_id` → 400. Buyer PATCH `seller_bundle_discounts` → 200 [] sem mutação. **AT3-03 aberto.** |
| AT4 Capturado / FSM | `setup_paid_order` Stripe TEST. CPI pós-pago 400. Buyer `cancelado` 403 `order_cancel_denied_post_pay`. CPI linha de saco já paga 400. |
| AT5 Stock / hold | stock=1 segunda order B1 e B2 → `order_hold_exceeds_stock`. qty=9 → mesmo. Após cancel B1, B2 INSERT 201 (hold liberta). |
| AT6 Race | Single-order: 1 Session. **Saco: AT6-04 aberto.** |
| AT7 2.º actor | B2 CPI order B1 → 400 `Invalid checkout user`. B2/S2 PATCH 200 [] **sem** mutação (confirmado GET). B2 `refund-order` 403 `Sem permissão`. |
| AT8 Caixa | `setup_paid_bag` ok: `paid_a=335` `paid_b=780` soma=`pi=1115`. Wallet seller 15,00 → 20,00 € após fixtures pagos; buyer 61,10 inalterado (pagamento Stripe, não carteira). Sem Δ anómalo além dos paid probes. |

--------------------------------------------------
## INVÁLIDOS / NÃO CONTAR
--------------------------------------------------

- **AT3-01** pass1: PATCH buyer em `seller_bundle_discounts` HTTP 200 [] — GET mostrou `tier_2_pct` inalterado (10).
- **AT7-03 / AT7-04** pass1: 200 [] — pass2 GET: shipping e bundle `pending` inalterados.
- **AT2-01b / AT6-02 / AT6-03:** detector «expired» falso (a palavra `expired` existe no JS da página Stripe **viva**). Substituído por AT2-06 / AT6-04 com frase exacta «This checkout session has expired».

--------------------------------------------------
## BLOQUEADOS (amostra — defesa ANAS a aguentar)
--------------------------------------------------

- `bundle_status_pending_only` no INSERT hostil
- `bundle_accept_seller_only` no PATCH buyer
- saco 16 UUIDs compactos >500 chars
- `offer_quantity_must_be_one`
- saco **com** `product_offer_id` **não** aplica tier (2165 ¢) — o fecho AN-P3-02 no Edge **funciona** enquanto o id não for apagado
- hold stock=1
- refund-order seller-only
- corrida single-order claim OK

--------------------------------------------------
## PROVAS
--------------------------------------------------

- `tool/redteam_blind_at_20260902T1607/pass1.json`
- `tool/redteam_blind_at_20260902T1607/pass2.json`
- `tool/redteam_blind_at_20260902T1607/pass3.json`
- `tool/redteam_blind_at_20260902T1607/pass4.json`
- Probes: `pass1.dart` … `pass4.dart`, `_rtat.dart`

--------------------------------------------------
## LIMITAÇÕES
--------------------------------------------------

- Captura Stripe das duas `cs_` **não** executada (evita P0 auto-infligido em TEST sem pedido). P1 = Session pagável.
- Wallet `buyer2`/`seller2` sem linha (utilizadores recém-criados).
- Não se leu relatórios AN/AH/AE/AB/Y/Z/AA/ANAS (cegueira). Código/SQL/Edge sim.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
