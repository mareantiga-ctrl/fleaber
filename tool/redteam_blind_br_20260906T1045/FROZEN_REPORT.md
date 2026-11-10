# FROZEN_REPORT — REDTEAM_BLIND_BR_MARKETPLACE_POS_BLBQ_v1

AUDITOR: REDTEAM_BLIND_BR_MARKETPLACE_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T11:05:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BR1, BR2, BR3, BR4, BR5, BR6, BR7, BR8]
VEREDICTO: FAIL_P1

```
AUDITOR: REDTEAM_BLIND_BR_MARKETPLACE_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

1. P0? NÃO
2. Quantos P0: 0
3. P1? SIM
4. Quantos P1: 1
5. P2? NÃO
6. Quantos P2: 0
7. P3? NÃO
8. Quantos P3: 0
```

**VEREDICTO:** P1 aberto → `FAIL_P1`.

Anti-atrofia: 1 achado contado. **0** = lista exacta BFBK/BF (`AB∥AC dual Session` · hífen+compact mesma linha · detach offer). Variantes **novas** da missão BR testadas. Exactos BFBK/BF **não** entram na CONTAGEM (verificados; HOLD).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (`amount` / `unit_amount` string ignorados; Session = quote servidor)
10. Buyer manipula qty autoritativa — NÃO (qty Unicode `２`/`９` → 400 `22P02`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (Δwallet unpaid = 0)
13. Refund excede captura — NÃO (sem captura TEST paga; S2 refund 403)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito marketplace)
16. Stock=1 duas vendas válidas — NÃO (2.ª order no SKU recusada)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (sem pagar as Sessions órfãs; sem `sk_test_`)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (B2 saco B1 400; S2 refund 403)
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_claim_checkout_session_slot` 403 JWT)
25. RLS crítico quebrado — NÃO (`stripe_checkout_session_id` PATCH 403 `order_money_fields_immutable`)
26. Edge confia total do cliente — NÃO (`amount`/`unit_amount`/`line_items` extra ignorados)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — NÃO (P1 aberto na corrida 3 sacos; lentes 8/8 exercitadas)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Sessions `cs_test_` criadas; **sem** `STRIPE_SECRET_KEY` no env do auditor — não expire/confirm/metadata Stripe) · JWT buyer/seller + B2/S2 (fixture admin) · `service_role` só fixture/observe (`status=pago` para saco-com-pago; SELECT).

Prefixo: `RTBR-20260906T1045-`.

Pasta: `tool/redteam_blind_br_20260906T1045/`.

Código estudado: `create-payment-intent` (quote, claim, bag overlap expire, settle GET, `unit_amount` servidor), `batata_claim_checkout_session_slot`, triggers bundle/offer/order money. Relatórios BL–BQ · BF–BK · AT–BE **não lidos**.

Wallets (BR8): buyer 61,10 € / seller 93,33 € **inalterados** após todos os probes unpaid.

--------------------------------------------------
## ACHADOS CONTADOS
--------------------------------------------------

### BR-P1-01 — Corrida 3 sacos A∩B∩C cria 3 Checkout Sessions (BD fica com 1)

**Lente:** BR6 (também BR2)  
**Actor:** buyer JWT  
**Pre:** 3 SKUs / 3 orders do mesmo vendedor; bags AB, BC, CA em paralelo (`Future.wait`).  
**Repro:** 3× `POST create-payment-intent` `bag_checkout=true` em simultâneo.  
**Resultado (pass2, repetível):**

| | valor |
|---|---|
| Sessions devolvidas (3 URLs pagáveis) | `cs_test_a1RJdSQ…` · `cs_test_a1mHlRG…` · `cs_test_a1yEnlu…` |
| `reused_session` | false, false, false |
| SID nas orders no fim | **1** (`cs_test_a1mHlRG…` em B e C; order A ficou **sem** SID) |
| status orders | `reserva_pendente` · `amount_paid_cents` vazio |

Pass1 (independente) devolveu outros 3 `cs_test_` distintos; BD também ficou com 1.

**Porque P1 e não P0:** não pagámos as 2 Sessions órfãs (sem `sk_test_`). Caminho explorável: 2 URLs Stripe continuam vivas fora da BD; a order A ficou sem slot → novo POST cria **4.ª** Session. Captura dupla / oversell **não** comprovada (settle órfão tem ramo de refund no código; não exercitado).  
**Não é o exacto BFBK `AB∥AC dual Session`:** o exacto pairwise também devolveu 2 `cs_` nesta ronda e **não** foi contado. Esta variante é a **nova** pedida (3 sacos A∩B∩C). Sequencial AB→BC→CA deixou 1 SID nas orders (expire overlap no caminho feliz).  
**Evidência:** `findings_pass2.json` P2.TRIPLE.persist; `findings.json` BR6.PAR.triple.

--------------------------------------------------
## EXACTOS BFBK/BF — FORA DA CONTAGEM
--------------------------------------------------

| Exacto | Resultado nesta ronda | CONTAGEM |
|---|---|---|
| AB∥AC dual Session | 2 `cs_test_` distintos no `Future.wait` de 2 sacos | **não contar** |
| hífen+compact mesma linha | 200; 2 linhas (dedup); total 1766 = 10 % tier vendedor (não duplicou linha) | **não contar** |
| detach offer | PATCH `product_offer_id=null` → 403 `order_product_offer_id_immutable` | **não contar** |

--------------------------------------------------
## FALSOS POSITIVOS RETRACTADOS
--------------------------------------------------

- **BR2-SESSION-REOPEN-AFTER-EXPIRE:** sem `sk_test_` o expire Stripe **não correu**; o 2.º POST reusou Session **aberta** (desenho 1-order-1-session). Não é reopen pós-expire.
- **BR7-ANON-CHECKOUT (pass1):** `checkoutRaw(jwt: null)` caía no JWT do buyer. Pass2: Bearer=anon key → 400 `Invalid checkout user.` · Bearer lixo → 400 · sem Authorization → 400 `Missing authorization.`
- **BR1-BAG-9-9-UNDERPAY:** 1766 vs 1955 **não** é underpay. Vendedor lab tem `seller_bundle_discounts.tier_2_pct=10` / `tier_3_pct=20`. 18 € −10 % = 16,20 € + 1,46 € protecção = **1766**. 1 linha 9 € = 1010 (sem tier). Buyer/S2 `PATCH` tier → HTTP 200 **`[]`** (0 rows, RLS); row ficou `tier_2_pct=10`.
- **BR3-BUYER-PATCH-TIER / BR7-S2-PATCH-S1-TIER (pass3):** 200 vazio ≠ escrita. Retract.

--------------------------------------------------
## LENTES — O QUE SE PROVOU
--------------------------------------------------

### BR1 preço / contract_unit — HOLD (sem P0)

| Variante nova | Resultado |
|---|---|
| `currency`: `EUR ` / NBSP | 200 Session EUR ao contrato (trim) |
| ZWJ / ZWSP / NFD / fullwidth | 400 `only EUR is supported` |
| `unit_amount: "1"` + `line_items` extra | ignorado; 18 € → 1955 |
| `amount` `"1"` / `"50"` / `"1e1"` / `"0x32"` | Session ao contrato (reuse) |
| saco 9+9 | 1766 = tier 10 % do **vendedor** (não ataque) |

### BR2 Session / saco / claim — P1 na corrida a 3; resto HOLD

| Variante nova | Resultado |
|---|---|
| 3 sacos A∩B∩C **sequencial** | 3 `cs_` devolvidos; **1** SID nas orders |
| 3 sacos A∩B∩C **paralelo** | **P1-01** — 3 `cs_` vivos; BD 1 SID |
| saco com order `pago` (fixture PI) | 400 `order status 'pago' cannot start payment` |
| JWT RPC `claim_checkout_session_slot` | 403 permission denied |
| JWT PATCH `claiming:` | 403 `order_money_fields_immutable` |
| `bag_lines` product_ids cruzados | 400 `bag product does not match order` |
| metadata Stripe `bag_product_ids` reordenados | NÃO COMPROVADO (sem `sk_test_`) |
| Session reopen pós-expire | NÃO COMPROVADO (sem expire Stripe) |

### BR3 bundle / oferta — HOLD

| Variante nova | Resultado |
|---|---|
| bundle PATCH `total_eur=0.50` (buyer + seller após accept) | row `total_eur=40.0`; checkout saco **4265** (catálogo 40 € + prot) |
| offer `quantity` fullwidth | 400 PGRST204 (coluna inexistente) |
| offer `amount` `０．５０` | 400 `22P02` numeric |
| order `quantity="９"` + offer | 400 `22P02` integer |
| oferta 5 € sem accept seller | contrato selado **3000** (catálogo 30 €); checkout 3215 |

### BR4 FSM pós-captura — HOLD

| Variante nova | Resultado |
|---|---|
| settle SID inventado | 400 «Pagamento ainda não confirmado»; order não `pago` |
| settle Session expirada | NÃO COMPROVADO (sem expire) |
| checkout após `pago`+PI fixture | 400 `cannot start payment` |

### BR5 stock / hold — HOLD

| Variante nova | Resultado |
|---|---|
| stock=1 duas orders | 2.ª INSERT bloqueada |
| qty Unicode `２` | 400 `22P02` |

### BR6 race — **P1-01**

| Variante nova | Resultado |
|---|---|
| 3× CPI paralelo **single** mesma order | 1 `cs_` (claim) |
| 3× bag A∩B∩C paralelo | **P1-01** |

### BR7 2.º actor — HOLD

| Variante | Resultado |
|---|---|
| B2 checkout saco B1 | 400 `order does not belong to buyer` |
| S2 `refund-order` | 403 `Sem permissão.` |
| anon / jwt lixo / sem Authorization | 400 |

### BR8 caixa — HOLD

Δwallet unpaid = 0. Sem captura TEST → sem prova Stripe net em P0.

--------------------------------------------------
## LIMITES DESTA RONDA
--------------------------------------------------

- Sem `STRIPE_SECRET_KEY` `sk_test_`: não expire, não confirm `pm_card_visa`, não PATCH metadata Stripe, não listar `status=open` nas 3 Sessions. P1-01 fica em **URLs devolvidas + BD**; captura dupla = NÃO COMPROVADO.
- `service_role` usado só para marcar `pago` de fixture (saco-com-pago / checkout pós-captura) e SELECT. Actor do exploit = JWT.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `pass1.dart` / `findings.json`
- `pass2.dart` / `findings_pass2.json`
- `pass2b.dart` / `pass2b_discounts.json` / `pass2b_quotes.json`
- `pass3.dart` / `findings_pass3.json` (FP 200 [] — retract)
- `_rtbr.dart`
