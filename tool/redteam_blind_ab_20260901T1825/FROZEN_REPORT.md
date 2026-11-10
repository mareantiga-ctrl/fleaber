AUDITOR: REDTEAM_BLIND_AB_POS_YZAA_v1
FROZEN_AT: 2026-09-01T18:39:30+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AB1, AB2, AB3, AB4, AB5, AB6, AB7, AB8]
VEREDICTO: FAIL_P0

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT (B1/S1/B2/S2) · `service_role` só fixture/observação/cleanup.
Prefixo: `RTAB-20260901T1825`.
Não se tocou produção. Fase 4 não iniciada. Nenhum patch aplicado.

Missão: depois dos fechos YZAA (qty=1 no conjunto aceite, `bundle_id` do buyer certo, capturado não reabre Checkout, session reuse só se `amount_total` igual), ainda se paga menos no conjunto, anexa bundle alheio, ou abre 2.ª Checkout após captura?

**Resposta:** bundle ownership, qty extra no conjunto aceite, e 2.ª Session pós-captura **seguram** nas variantes novas. **Não seguram** a moeda do Checkout: o Edge aceita `currency` do cliente (`usd` / `jpy` / `gbp`) e cria Session Stripe pagável com o mesmo inteiro de cêntimos. Isso é pagar menos (JPY zero-decimal; USD/GBP vs EUR).

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

P0 aberto: SIM          → quantos: 2
P1 aberto: SIM          → quantos: 2
P2 aberto: NÃO          → quantos: 0
P3 aberto: NÃO          → quantos: 0

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — SIM (caminho pagável em moeda ≠ EUR; carga Stripe TEST **não** foi concluída nesta ronda)
2. Quantos P0: 2
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (quote servidor; `bag_lines.quantity` não manda)
10. Buyer manipula qty autoritativa — NÃO (conjunto aceite recusa bag incompleto / qty≠1; INSERT qty=0/−1 → `invalid_order_quantity`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (2º refund seller idempotente; buyer 403)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO (não encadeámos release+refund)
15. Payout duplica Transfer — NÃO COMPROVADO (fora de âmbito AB)
16. Stock=1 duas vendas válidas — NÃO (2º hold recusado); SIM condicional se seller inflar quantity (P1)
17. Stock=1 duas capturas líquidas permanentes — NÃO (não pagámos as duas Sessions do inflate)
18. Bypass capacidade/reserva — NÃO (marketplace hold)
19. Cross-user financeiro — NÃO (B2 checkout saco B1 recusado; bundle alheio recusado)
20. Cross-user dados sensíveis — NÃO COMPROVADO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`order_buyer_attribution_denied` no INSERT seller→buyer)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO
25. RLS crítico quebrado — NÃO (anon PATCH bundle 200 [] sem efeito)
26. Edge confia total do cliente — NÃO no amount; **SIM na moeda** (`body.currency`)
27. Regressão funcional (happy path partido) — NÃO (setup_paid_order Stripe TEST → `pago`)
28. Saturação atingida — NÃO (moeda P0 aberta; pagamento hostil JPY/USD não liquidado até Δwallet)

Anti-atrofia: 0/ N achados = lista exacta Y2-001 / Y2-002 / Y8-010 / Y3-001 / dois bundle_id / hop unship V. Variantes novas. Sem `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### RTAB-AB3-currency-unpinned · P0 · AB3 · buyer JWT

**Impacto:** o comprador (API) escolhe a moeda Stripe. O servidor calcula o total em cêntimos **como se fosse EUR** e passa esse inteiro a `price_data.unit_amount` com `currency` do body. `jpy` é zero-decimal: 1850 → 1850 JPY (≪ €18,50). `usd`/`gbp` cobram 18,50 nessa moeda, não em euro.

**Repro:**
1. POST `orders` (JWT buyer, `Pagamento na app`).
2. POST `/functions/v1/create-payment-intent` com `currency: "jpy"` (ou `usd` / `gbp`), `buyer_id` = JWT, `order_id` da linha.
3. 200 + `checkoutSessionId` `cs_test_…` + `checkoutUrl` Stripe TEST.

**Prova (pass2, orders novas, 1ª Session — sem reuse):**
- JPY: `cs_test_a1G5n98ciVUJAwOkaNOsT7ta4qXDCQpbEE7b0QHLRjX8xYRPPc9Ws2jdi0` · `amount_total` 1850 · `reused: null`
- GBP: `cs_test_a1tkDbUQDWaO11Cp8UwVxn77c1hlz5K6guJlUjJMd0TV8GtOcNsQioHpsH` · `amount_total` 1850
- USD: `cs_test_a1MuuSoDEU1U5pVMQvdWm1OywLe9mZdFKPL6LaG4tcO3S0nBvNQQswHqUG` · `amount_total` 1850 · `reused: null`

Código: `create-payment-intent/index.ts` — `const currency = (body.currency ?? "eur").toLowerCase()` → `price_data.currency` sem allowlist.

HTML da página Checkout é SPA (551 983 bytes, sem `"currency"` no documento inicial). Não há `sk_test_` local para `sessions.retrieve`. A prova de aceitação é o create Stripe 200 com ISO válido no `price_data` — o campo que define a moeda da Session.

**Não pago** nesta ronda (AB8): sem Δwallet / Stripe net da Session hostil.

---

### RTAB-AB3-usd-poisons-eur-reuse · P0 · AB3 · buyer JWT

**Impacto:** a 1.ª Session (moeda hostil) fica no slot da order. O 2.º POST `currency=eur` **reutiliza o mesmo `cs_`** (`reused_session: true`) porque o inteiro `amount_total` coincide. O cliente «honesto» (EUR) é mandado pagar a Session já criada em USD/JPY.

**Repro:** checkout `currency=usd` → checkout `currency=eur` na mesma order.

**Prova:** `usd_sid` = `eur_sid` = `cs_test_a1Chw4jyy1lrfPwkQ3NXibukklfcql5lHIP9OmUzWicQ14fsdHPcsV5fBm` · `eur_reused: true` · `usd_amt` = `eur_amt` = 1955.

Reuse de Session **single-order** compara `amount_total`, **não** compara `currency`.

---

### RTAB-AB3-bag-reuse-no-amount-check · P1 · AB3 · buyer JWT

**Impacto:** no **saco**, se já existe `cs_` aberto numa linha, o Edge devolve essa Session **sem** `prior.amount_total !== amount` (o caminho single-order tem essa guarda). Saco de 2 SKUs (4685) depois saco de 3 SKUs (quote 8885) → **mesmo** `cs_`. Resposta: `server_amount_cents: 8885` vs `amount_total` Stripe **4685**. Quem pagar a URL cobra 2 SKUs; o webhook settle usa metadata das 2 linhas — o 3.º SKU **não** é liquidado a preço de 2. Não é o «pagar 3 pelo preço de 2» na liquidação; é Session errada + JSON mentiroso.

**Repro:** bag A+B → bag A+B+E (overlap).

**Prova:** `cs_test_a11DG2kJSzFIN6PZs2MmKD5b0ArxvtIc3kbuh2QMDUz1ttr6P2aMghceRw` · q2 server 4685 · q3 server 8885 / amount_total 4685 · `reused: true`.

Variante **nova** vs Y3-001 (reuse montante errado no single-order).

---

### RTAB-AB5-inflate-two-sessions · P1 · AB5 · seller JWT + B1/B2

**Impacto:** seller PATCH `products.quantity` 1→9 com hold B1 activo. B2 consegue 2.º hold. Ambos abrem Checkout (`cs_test_a1g7MCft…` e `cs_test_a1YSPy5K…`). Duas capturas permanentes **não** foram feitas. Caminho de oversell se as duas Sessions forem pagas (inventário original 1). O seller controla o catálogo — não é bypass RLS; é ausência de teto de quantity vs hold.

**Repro:** SKU qty=1 → hold B1 → PATCH quantity=9 JWT seller → hold B2 → dois `create-payment-intent`.

--------------------------------------------------
## FECHOS (variantes novas — não a lista exacta Y)
--------------------------------------------------

| Lente | Variante | Resultado |
|-------|----------|-----------|
| AB1 | 2.ª order do **mesmo SKU** no conjunto aceite [A,B] + bag 3 linhas | 400 `bag must include all items in the accepted bundle` |
| AB1 | qty=2 em bundle **pending** → seller accept → bag | 400 mesmo erro (qty≠1 quebra `bundleComplete`) |
| AB1 | `bag_lines.quantity=7` | ignorado; total ≈ conjunto (3530 vs bundle 3300 + taxas) |
| AB1 | qty=0 / −1 | `invalid_order_quantity` |
| AB2 | B2 bag checkout das orders B1 (sem PATCH `bundle_id`) | 400 `order does not belong to buyer` |
| AB2 | B1 INSERT `bundle_id` do B2 | `order_bundle_buyer_mismatch` |
| AB2 | PATCH `product_bundles.buyer_id=B2` após accept | buyer_id congelado |
| AB2 | seller INSERT order `buyer_id=B1` | `order_buyer_attribution_denied` |
| AB4 | aliases `pendente` / `Paid` / `capturado` / `pedido_devolucao` / `cancelado` em order `pago` | estado permanece `pago` (200 = revert silencioso ou check) |
| AB4 | 2.ª Checkout na order capturada (status actual `pago`) | 400 `order status 'pago' cannot start payment` / already captured |
| AB4 | seller `enviado` → `reserva_pendente` | fica `enviado` |
| AB4 | INSERT `premio_rifa` | revertido para `reserva_pendente` |
| AB6 | Future.wait 2× checkout mesma order | 1 `cs_` (claim) |
| AB6 | stock=1 dois holds | 2º `order_hold_exceeds_stock` |
| AB7 | saco S1+S2 | 400 `must share one seller` |
| AB7 | linha B2 no saco B1 | 400 `order does not belong to buyer` |
| AB8 | buyer `refund-order` | 403 Sem permissão |
| AB8 | seller refund 2× | 2º `already_refunded` / idempotent |
| AB8 | `custom_tiers` pct=90 | quote capado (~4265 cents para 2×20€, não ~400) |

Happy path: `setup_paid_order` → `pago`, `amount_paid_cents=590`, PI `succeeded` (Stripe TEST). Wallet não moveu no instante (escrow). Sem Fase 4.

--------------------------------------------------
## LENTES
--------------------------------------------------

- **AB1** Conjunto qty — saturado nas variantes novas (dup SKU, pending→accept qty=2, body qty). Fecho Y qty=1 no aceite **aguenta**.
- **AB2** Bundle ownership — saturado (B2 saco B1, INSERT alien, swap buyer_id, seller attribution). Fecho **aguenta**.
- **AB3** Checkout Edge — **P0 moeda** + **P1 bag reuse sem check de amount**.
- **AB4** Capturado — aliases + 2.ª Session no estado `pago` **fechados**. Não é hop exacto capturado→RP.
- **AB5** Stock/hold — inflate seller = P1.
- **AB6** Race — 2× Session mesma order fechado; stock=1 2.º hold fechado.
- **AB7** 2.º actor — saco dois sellers / linha alheia fechados.
- **AB8** Composição caixa — refund buyer/duplo fechados; **não** liquidámos Session JPY/USD até Δwallet (lacuna explícita).

--------------------------------------------------
## O QUE NÃO FOI PROVADO
--------------------------------------------------

- Pagar a Session JPY/USD até `amount_paid_cents` / wallet / Stripe net (sem `sk_test_` local; SPA Checkout).
- `sessions.retrieve` da moeda (mesmo motivo).
- Bag reuse: pagar os 2 SKUs e ver se o 3.º fica `pago` (código de settle aponta que **não**).

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_ab_20260901T1825/pass1.dart` + `pass1.json`
- `tool/redteam_blind_ab_20260901T1825/pass2.dart` + `pass2.json`
- `tool/redteam_blind_ab_20260901T1825/_rtab.dart`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
