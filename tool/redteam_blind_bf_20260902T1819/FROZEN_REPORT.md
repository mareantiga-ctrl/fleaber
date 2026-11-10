## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 2

AUDITOR: REDTEAM_BLIND_BF_MARKETPLACE_POS_ATBE_v1
FROZEN_AT: 2026-09-02T19:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BF1, BF2, BF3, BF4, BF5, BF6, BF7, BF8]
VEREDICTO: FAIL_P1

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTBF-20260902T1819-`
Actors: anon · buyer JWT · seller JWT · B2 · S2
service_role: só fixture/observação (`setup_paid_order`, `setup_paid_bag`, SELECT)
Pasta: `tool/redteam_blind_bf_20260902T1819/`

--------------------------------------------------
MISSÃO
--------------------------------------------------
Depois do fecho ATBE no saco/oferta, ainda consigo total abaixo do contrato,
Sessions gémeas, ou stock incoerente — com variantes **novas** (não exactos ATBE).

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### RTBF-BF2-two-bags-share-order-dual-session · P1 · BF2/BF6

**Título:** Dois sacos que partilham uma encomenda, em paralelo, criam duas Checkout Sessions abertas.

**Actor:** buyer JWT

**Pré:** três SKUs do mesmo vendedor (14 €, 11 €, 7 €), três holds `reserva_pendente` A/B/C.

**Repro:**
1. `Future.wait` de dois `POST create-payment-intent` `bag_checkout=true`:
   - saco AB = orders A+B
   - saco AC = orders A+C
2. Observar `checkoutSessionId` nas duas respostas e `orders.stripe_checkout_session_id`.

**Esperado:** uma Session (expirar a outra) ou recusar o 2.º saco que reutiliza A.

**Obtido (pass1, repetido pass2):**
| | Session | Montante | Gravada em |
|---|---------|----------|------------|
| saco AB | `cs_test_a1MFdUkkabBv0wchpeFAsiyJxcr4LA4NswsqEBsTY1ER00RKEDUIUQhfqL` | **2428** cêntimos | A e B |
| saco AC | `cs_test_a1HmBkhJWejmFh2A5eN2krKVoZy30OitAJoZpjA4AQj89V4YkHwEYbdcrg` | **2050** cêntimos | **só C** |

Order A (`15bd1139-7511-431a-a176-68a9cd28f65a`) ficou com a SID do saco AB; C (`3af0a7a6-3463-4eee-828a-7662fcd66d66`) com a SID do saco AC. Ambas as respostas foram 200 com `checkoutUrl`. Status das três lines: `reserva_pendente`, `amount_paid_cents=null`. Réplica pass1: SIDs `cs_test_a11nvaxN…` / `cs_test_a1I1aeyab…`, mesmos montantes 2428 / 2050.

**Porquê (código, não relatório ATBE):** o loop de expire só corre se a order **já** tem `cs_` — na corrida as duas requests passam o loop vazias. Depois do claim, se a SID reutilizável tem `bag_order_ids` **diferente**, o Edge **não expira** e cai em `sessions.create`. O UPDATE final grava a SID nova só nas lines do saco corrente → B fica com S1, C com S2, A com a última escrita.

**Impacto:** caminho explorável para pagar S2 (A+C) e S1 (A+B). A entra nos dois metadata. Settle da 2.ª captura em order já `pago` tenta `refundOrphanDuplicatePaymentIntent` no PI novo — **não capturado aqui** (4242 não liquidado). Sem prova de dinheiro irreversível → **P1**, não P0.

**Não é o exacto ATBE** «compact∥hífen dual Session»: as duas bags são conjuntos **distintos** que partilham uma line (variante pedida: «2 bags partilham 1 order»).

---

### RTBF-BF2-dup-hyphen-compact-noprod · P2 · BF1/BF2

**Título:** A mesma order em hífen e compacto no mesmo POST (sem `product_id`) duplica a linha e o total da Session.

**Actor:** buyer JWT

**Pré:** 1 SKU 15 €, stock 4, 1 hold qty=1. Contrato selado `contract_unit_cents=1500`, `contract_qty=1`. Honest checkout = **1640** cêntimos (15 € + protecção).

**Repro:**
```
bag_lines: [
  { "order_id": "<uuid-hífen>" },
  { "order_id": "<uuid compact 32 hex>" }
]
```
Sem `product_id` (com `product_id` compacto o Edge recusa `bag product does not match order`).

**Esperado:** `seenBag` colapsa compacto∥hífen → 1 linha, 1640 cêntimos.

**Obtido:** Session `cs_test_a1v53ak4W9vZIxS5ACzrskbxotBgPkK1oRmwW791g5YdZKJwAemmRZY1C2` · `server_amount_cents` = **2900**. Order `3c4036de-d9b3-4e33-b819-f77446775223` `price_total=14.50` (metade de 29 €). Produto qty continua 4.

Conta: 2×15 € = 30 €; desconto de conjunto ~10 % (2 «itens») → 27 €; protecção 2 € → 29,00 €.

**Impacto:** o comprador **paga mais**, não menos. Metadata `bag_order_ids` leva o UUID duplicado. `seenBag` compara a string crua (não `normalizeBagOrderIdsKey`). Não é dual Session; é linha duplicada no mesmo pedido.

**Não contar como exacto ATBE** «compact∥hífen dual Session».

--------------------------------------------------
FALSOS POSITIVOS (retraídos)
--------------------------------------------------
- `RTBF-BF1-currency-accepted-eur_nbsp`: `currency=eur` + NBSP. `String.trim()` ES2019 come o NBSP → fica `eur`; Session **1115** = catálogo. Não é finding.
- `RTBF-BF2-session-reopen-new-cs`: 3 SIDs em POST sequenciais saco(A,B) → saco(A,C) → saco(A,B) outra vez. O 2.º POST dispara `expireSharedBagCheckoutSession`; o 3.º cria substituição. Composição sequencial ≠ corrida. Não é finding.

--------------------------------------------------
DEFESAS QUE AGUENTARAM (variantes novas + lentes)
--------------------------------------------------
**BF1 preço:** body `amount=1` ignorado. `EURO` / `usd` / ZWSP / fullwidth / vazio → `only EUR is supported`. `EUR`/`Eur`/`eUr` → EUR 1115. product_ids trocados no saco → `bag product does not match order`.

**BF2 saco/claim:** ZWJ, ZWSP, hífen Unicode → `invalid input syntax for type uuid` (fail-closed). Sequência saco(A,B) depois saco(A,C) expira S1 (código). Compacto+hífen **com** `product_id` compacto recusado.

**BF3 oferta/conjunto:** `offer_quantity_must_be_one` no INSERT qty=3. PATCH qty → `order_money_fields_immutable`. 2.ª order mesma oferta → `offer_already_consumed`. Detach `product_offer_id` → `order_product_offer_id_immutable` (**exacto ATBE, não contar**). Buyer/seller PATCH `total_eur=0.50` após accepted: totais ficam 18 € (50 % de 36 €). Checkout conjunto completo = **1955** (18 € + protecção), não o catálogo 3845.

**BF4 FSM:** compra Stripe TEST `pago` PI `pi_3UBHwvH7FWYUN3jh00Ld0FgJ` 590 cêntimos. Buyer cancel → `order_cancel_denied_post_pay`. Seller MB WAY `pago` sem prova → `order_mbway_pago_requires_proof`.

**BF5 stock:** SKU qty=1 + hold oferta 7 €; B2 INSERT → `order_hold_exceeds_stock`. Só 1 Session no hold∥checkout.

**BF6 race:** hold∥checkout oferta selada: B2 não obtém 2.ª Session. (A race 2 bags é o P1.)

**BF7 2.º actor:** B2 checkout order B1 → `order does not belong to buyer`. Anon → `Invalid checkout user`. PATCH `buyer_id` → 200 [].

**BF8 caixa:** `setup_paid_order` `pi_3UBHx1H7FWYUN3jh09kSoBfF` 590 cêntimos, `status=pago`, `stock_units_applied` coerente. `setup_paid_bag` PI `pi_3UBHx4H7FWYUN3jh0DICk3am` 1115 cêntimos. JWT INSERT `wallet_transactions` → RLS 403.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Checkout Stripe TEST pago marketplace: sim (`setup_paid_order` + `setup_paid_bag`).
2. Contabilidade fechada na compra legítima: stock · PI · status · wallets.
3. Race `Future.wait`: 2 bags partilham 1 order; hold oferta ∥ checkout B2.
4. MB WAY: seller `pago` sem prova recusado.
5. Compra legítima single-item e saco pago **não** partiram.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Exactos ATBE **não contados:** compact∥hífen dual Session · detach `product_offer_id` · metadata 500 compact.
0/2 findings na lista exacta. Variantes novas: 2 bags partilham 1 order; compacto∥hífen **mesma request** sem `product_id`.
Não ATROFIA_ABORT.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------
1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO (PATCH imutável; dup line inflaciona o **saco**, não o selo)
11. Seller falsifica pagamento plataforma — NÃO (MB WAY exige prova)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO (não se liquidaram as Sessions hostis)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora do poço)
16. Stock=1 duas vendas válidas — NÃO (B2 hold recusado)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora do poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (amount ignorado; IDs do saco ainda não normalizados no `seenBag`)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — NÃO (P1 aberto; 8/8 lentes exercidas)

--------------------------------------------------
NÃO FEITO / LIMITES
--------------------------------------------------
- Sessions hostis **não** liquidadas com cartão 4242 — por isso o overlap de sacos fica P1, não P0.
- HTML estático do Checkout Stripe é SPA: a palavra «expired» no JS **não** prova estado da Session.
- Produção não tocada. Fase 4 não iniciada. Código de produto **não** corrigido.

Evidência: `pass1.json`, `pass2.json`, `observe.json`, este ficheiro.
