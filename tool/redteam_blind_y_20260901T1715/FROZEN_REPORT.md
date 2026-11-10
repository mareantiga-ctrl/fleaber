```
AUDITOR: REDTEAM_BLIND_Y_POS_VWX_v1
FROZEN_AT: 2026-09-01T16:35:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Y1, Y2, Y3, Y4, Y5, Y6, Y7, Y8]
VEREDICTO: FAIL_P0
```

# FLEABER — RED TEAM CEGO Y · PÓS-FECHO VWX

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT (anon / B1 / S1 / B2 / S2) · `service_role` só fixture (`setup_paid_order`) / observação. **Não se corrigiu nada.** Prefix `RTY-20260901T1715-`.

Poço: depois de `shipped_at`, anti-hop FSM, conjunto exacto no Edge e refund pós-envio bloqueado — ainda se paga menos no conjunto (qty extra) e ainda se reabre checkout numa order já capturada.

## CONTAGEM

```
P0 aberto: SIM          → quantos: 1
P1 aberto: SIM          → quantos: 2
P2 aberto: SIM          → quantos: 2
P3 aberto: NÃO          → quantos: 0
```

Retractado (falso positivo): `RTY-Y5-002` (refund em pago sem disputa — o INSERT da disputa falhou; o refund é o happy path).

## CHECKLIST

1. P0 dinheiro irreversível encontrado — SIM (caminho Session Stripe a preço de 2 un. para 4 un.; captura desta Session não clicada nesta ronda por ausência de `sk_test_` local; quote+cs_ reproduzidos 2×)
2. Quantos P0: 1
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 2
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — SIM (conjunto: `total_eur` do bundle ignora `contract_qty` extra)
10. Buyer manipula qty autoritativa — SIM (qty 3+1 aceite no INSERT; Edge cobra como 1+1)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`batata_credit_wallet_once` / `debit` 42501)
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO (não exercido)
16. Stock=1 duas vendas válidas — NÃO (2.ª order `order_hold_exceeds_stock`)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — SIM (B1 anexa bundle aceite de B2)
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (credit/debit JWT recusados)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`amount`/`total_eur` no body ignorados; o buraco é `bundle_id`+qty no servidor)
27. Regressão funcional (happy path partido) — NÃO (refund pré-envio OK)
28. Saturação atingida — NÃO (P0 conjunto qty ainda aberto; 2.ª captura do hop não liquidada)

## ANTI-ATROFIA

Variantes **não** são a lista proibida:
- hop não foi `enviado→RP→pago` exacto → foi `pago→reserva_pendente` ( capturado ) e aliases fora do CHECK
- extra-SKU exacto não usado → **qty extra nas mesmas SKU do conjunto**
- `order_cannot_reopen_pago` directo exacto não usado
- offer qty=1 exacto não usado
- bag incompleto exacto não usado
- Hub qty=0 não usado
- dual Session exacto não usado → race 3× deu 1 `cs_`; reuse é Session **única** com quote divergente

Proporção lista atrofia: **0%**. Sem `ATROFIA_ABORT`.

## FINDINGS

### RTY-Y2-001 · P0 · Y2 · buyer JWT

**Título:** Conjunto aceite cobra `total_eur` (2 SKU) e ignora `quantity`/`contract_qty` extra.

**Actor:** B1 JWT → `create-payment-intent` bag.

**Pré:** Dois produtos 20€, qty catálogo 8. Bundle B1 aceite `discount_pct=50` → `total_eur=20`. Orders: A `quantity=3` `contract_qty=3` `bundle_id=…`; B `quantity=1` `contract_qty=1` mesmo bundle. List 80€; conjunto de 2 = 20€.

**Repro:**
1. POST `product_bundles` + seller PATCH `accepted` 50%.
2. POST `orders` qty=3 e qty=1 com o mesmo `bundle_id`.
3. POST `/functions/v1/create-payment-intent` `bag_checkout=true` `buyer_id=B1`.

**Esperado:** recusar qty≠1 no conjunto, ou cobrar 3×20+1×20 (+ taxas).

**Obtido:** `server_amount_cents=2165` (~20€ itens + protecção mão). Session Stripe `cs_test_a1VvJ1ya…` (pass2) e `cs_test_a1wz2cIF…` (pass3). Edge: `bundleComplete` compara **sets de product_id**, não quantidades; substitui `itemsCents` por `bundleTotalCents`.

**Impacto:** Pagar preço de 2 unidades, levar 4. GET settle recompute usa a mesma função → `paidTotal === quote` → `settlePaidBagOrders` aplica stock das linhas (3+1). Captura cartão desta Session **não** foi clicada aqui (sem `STRIPE_SECRET_KEY` local); o instrumento de pagamento (Checkout Session TEST no montante errado) foi criado duas vezes.

**Prova:** `tool/redteam_blind_y_20260901T1715/pass2.json` `RTY-Y2-001`; `pass3.json` nota `Y2.liq.quote`. Orders `d7ba6f91-…` qty=3 + `a0f6a4bd-…` qty=1.

---

### RTY-Y2-002 · P1 · Y2+Y7 · buyer JWT

**Título:** B1 anexa `bundle_id` de conjunto aceite de B2; Edge usa `total_eur` alheio.

**Actor:** B1 PATCH nas próprias orders (pré-pago `bundle_id` ainda mutável).

**Pré:** Bundle B2 aceite 50% nos mesmos SKU (25€+25€). B1 cria orders sem bundle, PATCH `bundle_id=<id B2>`.

**Repro:** PATCH `orders.bundle_id` → bag checkout.

**Esperado:** `bundle.buyer_id` == `order.buyer_id`.

**Obtido:** PATCH 200; `server_amount_cents=2690` (25€+prot, não 50€+prot). Edge lê só `status, total_eur, product_ids`.

**Impacto:** Free-ride no contrato de outro comprador. Money cols só congelam `bundle_id` **depois** de pago.

**Prova:** pass2 `RTY-Y2-002`; bundle `8aeb4499-e1b3-4931-bb73-fb964e287957`.

---

### RTY-Y8-010 · P1 · Y1+Y8 · seller JWT + buyer checkout

**Título:** Order Stripe já capturada: hop `pago`→`reserva_pendente` permite nova Checkout Session.

**Actor:** S1 PATCH status; B1 `create-payment-intent`.

**Pré:** `setup_paid_order` → `pago`, `amount_paid_cents=590`, `pi_3UAuZuH7FWYUN3jh12m6OtDc`, `stock_units_applied=1`, `shipped_at=null`.

**Repro:** PATCH `status=reserva_pendente` (200, persistido) → POST create-payment-intent.

**Esperado:** checkout blocked (já capturada / não está em estados de hold).

**Obtido:** Session nova `cs_test_a1Kgz4ge…` gravada em `stripe_checkout_session_id`; PI antigo e `amount_paid_cents=590` mantêm-se. Unship `pago→RP` **não** está no fecho VWX (esse bloqueia RP só se `shipped_at` ou old∈enviado/entregue/concluido). `assertOrderStatusAllowsCheckout` inclui `reserva_pendente`.

**Impacto:** 2.ª captura possível; 1.º PI pode ficar órfão succeeded. Pagamento da 2.ª Session **não** liquidado nesta ronda (sem sk local).

**Prova:** pass3 `RTY-Y8-010`; order `9b10bcab-b1c0-433f-bca0-2d82313b5696`.

---

### RTY-Y1-010 · P2 · Y1 · seller JWT

**Título:** Seller regride `pago` (capturado) para `aguarda_confirmacao` / `reservado` / `pendente` / `reserva_pendente`.

**Actor:** S1 PATCH. Refund a seguir é o mesmo refund pré-envio já permitido em `pago` — **não** é dinheiro extra; o hop é o bug.

**CHECK** `orders_status_batata_check` rejeita aliases (`em_transito`, `shipped`, ZWSP). `pago→entregue` **funciona** sem selar `shipped_at`; refund Edge bloqueia por status `entregue` (`order_refund_blocked_status`). JWT não limpa `shipped_at`. Refund após `enviado` real: `order_refund_blocked_shipped`.

**Prova:** pass2 notes `Y1.allow.*`; probe stdout aliases 23514.

---

### RTY-Y3-001 · P2 · Y3 · buyer JWT

**Título:** Reuse de Checkout Session barata quando o saco já é A+B.

**Obtido:** mesmo `cs_test_a1EkbNvY8…`; `server_amount_cents=5105` (quote novo) vs `amount_total=905` (Session antiga). Metadata da Session **não** é actualizada → settle pagaria só a linha A. Não é extra-SKU grátis; é mentira de API + risco de UX.

**Prova:** pass2 `RTY-Y3-001`.

---

## FECHADO / NÃO EXPLORÁVEL NESTA RONDA

| Lente | Resultado |
|-------|-----------|
| Y1 enviado real | `shipped_at` selado; refund 403 `order_refund_blocked_shipped` |
| Y1 aliases fora do CHECK | 23514 `orders_status_batata_check` |
| Y1 TOCTOU refund∥ship (Y6) | PATCH `enviado` ganha; refund 403; `stripe_refund_id` null |
| Y2 dois `bundle_id` | 400 `bag cannot mix multiple bundle contracts` |
| Y3 race 3× POST | 1 `cs_` (claim slot) |
| Y4 stock=1 duas orders | 2.ª INSERT `order_hold_exceeds_stock` |
| Y5 disputa em pago | RLS 403 no INSERT (pago sem enviado/receção) |
| Y7 B2/S2 | B2 PATCH 200 `[]`; S2/B2 refund 403 Sem permissão |
| Y8 credit/debit JWT | 42501 permission denied |
| Happy path | refund pré-envio → `cancelado` + `stripe_refund_id` |
| MB WAY seller `pago` | não partido (não forçado a falhar) |

## TÁCTICAS

1. Stripe TEST pago: sim (`setup_paid_order` / PI `pm_card_visa` 5,90€) + checkout marketplace (`create-payment-intent` Sessions). Disputa em pago: RLS recusou.
2. Contabilidade: wallets observadas nas fixtures e2e; PI ids; `stripe_refund_id`; `shipped_at`; stock holds.
3. Race real: 3× checkout (1 session); Future.wait enviado∥refund (ship ganha); TOCTOU +250ms (ship ganha).
4. REST/RPC/Edge ≠ Flutter: PATCH status, PATCH `bundle_id`, bag Edge.
5. Não partido: refund antes de enviar; compra single e2e; MB WAY não atacado.

## SATURAÇÃO

Não. P0 conjunto qty extra continua; hop capturado→RP+2.ª Session não foi pago até Δwallet/PI órfão. Oferta produto-mismatch sem evidência (POST offer falhou silencioso no pass2).

## FICHEIROS

- `tool/redteam_blind_y_20260901T1715/_rty.dart`
- `tool/redteam_blind_y_20260901T1715/probe.dart` (parcial; crash json Set — aliases Y1)
- `tool/redteam_blind_y_20260901T1715/pass2.json`
- `tool/redteam_blind_y_20260901T1715/pass3.json`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
