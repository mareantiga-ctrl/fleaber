# FROZEN_REPORT — REDTEAM_BLIND_AN_MARKETPLACE_POS_AHAM_v1

AUDITOR: REDTEAM_BLIND_AN_MARKETPLACE_POS_AHAM_v1
FROZEN_AT: 2026-09-02T10:26:44+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AN1, AN2, AN3, AN4, AN5, AN6, AN7, AN8]
VEREDICTO: PASS_CEGO_SATURADO

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: NÃO          → quantos: 0
P3 aberto: SIM          → quantos: 3  (fora de âmbito salvo pedido)
```

**VEREDICTO:** P0–P2 fechados + só P3 + saturação das lentes AN no marketplace/checkout → `PASS_CEGO_SATURADO`.

Anti-atrofia: 0 achados = lista exacta AH2/AH6/AE1/AE2/AB3/AB5/Y2. Variantes **novas** testadas; fechos AHAM **aguentaram** no ponto de dinheiro.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO (P3 apenas; ver achados P3)
6. Quantos P2: 0
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 3
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (sem captura TEST paga nesta ronda)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (sem captura/payout)
16. Stock=1 duas vendas válidas — NÃO (2.º INSERT hold bloqueado)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (sem pagar as 2 Sessions)
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (fora de foco; não extraído)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito marketplace/checkout)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`claim_checkout_session_slot` 403 JWT)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`amount` / `line_total_cents` ignorados)
27. Regressão funcional (happy path partido) — SIM (P3: saco 14+ linhas; desconto tier do saco)
28. Saturação atingida — SIM (8/8 lentes AN; variantes novas além da lista AH/AE/AB)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · JWT buyer/seller + buyer2/seller2 criados por admin (fixture) · `service_role` só fixture/observe/cleanup.

Prefixo: `RTAN-20260902T1015-`.

Código estudado: `create-payment-intent`, `refund-order`, `stripe-webhook`, RLS/triggers `batata_orders_seal_contract`, `batata_claim_checkout_session_slot`, `batata_product_checkout_available`, `batata_product_held_qty`, AHAM SQL. Relatórios AH/AE/AB/Y/Z/AA **não lidos**.

--------------------------------------------------
## ACHADOS P3
--------------------------------------------------

### AN-P3-01 — Saco ≥14 linhas: Stripe recusa metadata (500 chars)

**Lente:** AN2  
**Actor:** buyer JWT  
**Pre:** 14 orders UUID → `bag_order_ids` = 517 chars.  
**Repro:** `POST create-payment-intent` `bag_checkout=true` com 14 `bag_lines`.  
**Resultado:** HTTP 400 `Metadata values can have up to 500 characters... 517 characters`. **Nenhuma Session criada** (fail-closed). 13 linhas (480 chars) → HTTP 200 Session OK.  
**Impacto:** saco grande não paga; não há truncagem silenciosa nem settle incompleto. Disponibilidade, não dinheiro.  
**Evidência:** `matrix.json` AN2/metadata_500; pass2 AN2/bag13.

### AN-P3-02 — Desconto tier do vendedor não aplica no saco com contratos selados

**Lente:** AN3  
**Actor:** buyer JWT  
**Pre:** `seller_bundle_discounts.tier_2_pct=10`, dois SKUs 20 €, sem `product_bundles` aceite.  
**Repro:** bag checkout 2 linhas.  
**Resultado:** `server_amount_cents=4265` = 40,00 € itens + 2,65 € protecção. **Sem −10 %.**  
**Causa (código):** `anySealedOfferContract` fica true se **qualquer** linha tem `contract_unit_cents>0` (todas as orders novas vêm seladas). O desconto tier só corre se `!anySealedOfferContract`.  
**Impacto:** comprador **paga mais**, não menos. Hygiene / possível regressão do desconto de saco marketplace.  
**Evidência:** matrix AN3/tier_discount_sealed.

### AN-P3-03 — INSERT `product_bundles` “accepted” + `total_eur=0.50` é 201 mas a BD reescreve

**Lente:** AN3  
**Actor:** buyer JWT  
**Repro:** `POST product_bundles` status=accepted total_eur=0.50.  
**Resultado:** HTTP 201; linha fica `status=pending`, `total_eur=20.0` (subtotal catálogo). Checkout do conjunto (qty 1+2 pending) cobrou **3215** cêntimos (catálogo 3 unidades), não 0,50 €.  
**Impacto:** cliente vê 201; contrato hostil **não cola**. Falso positivo inicial (qty=2 em bundle **pending**, não aceite) — **não é Y2**.  
**Evidência:** matrix AN3/bundle_insert_jwt, AN3/bundle_checkout.

--------------------------------------------------
## LENTES — O QUE SE PROVOU
--------------------------------------------------

### AN1 Preço autoritativo — HOLD

| Variante (nova, não AB/AE exact) | Resultado |
|---|---|
| INSERT `contract_unit_cents=1` JWT | Selado **1200** / `price_total=12.0` |
| PATCH contrato | **403** `order_money_fields_immutable` |
| `amount=50` no body | Session **1325** (= catálogo 12 € + protecção) |
| Seller drop catálogo 15→1 após selo | Session **1640** (mantém 15 €) |
| qty=0 / qty=99 | **400** `invalid_order_quantity` / `order_hold_exceeds_stock` |
| Live **ended** + `live_item.price=1` + produto 25 € (não AE1 stale exact: hitch marketplace_product em live ended) | Contrato **2500**; checkout 200 a preço de catálogo |

### AN2 Session / saco — HOLD nos fechos AHAM; P3 metadata

| Variante | Resultado |
|---|---|
| `currency=usd` / `euro` / `""` | 400 só EUR |
| `currency=EUR` (maiúsculas) | 200 (normalizado para eur) |
| Saco A+B → A+C **mesmo montante** 8+8 (não orphan de preços diferentes) | **sid1 ≠ sid2**, `reused_session=null`, amount 1745=1745. Expire **disparou criação nova**. Captura da URL antiga **não paga nesta ronda** (sem `sk_test` retrieve; browser MCP indisponível). Shell HTML das duas URLs ainda é “Stripe Checkout” — **não prova** Session `open` vs `expired`. |
| `Future.wait` 2× o **mesmo** saco A+C | **1** sid único — claim/reuse aguentou |
| JWT `batata_claim_checkout_session_slot` | **403** permission denied |
| `line_total_cents=1` + `amount=50` | ignorado, server **1745** |
| 14 UUID metadata | ver P3-01 |
| Selo carrier + body `hand` | cobra **1273** (carrier). PATCH hand → 200 silencioso mas amount continua 1273 (selo) |

### AN3 Conjunto — HOLD dinheiro; P3 desconto/201

B2 + `bundle_id` de B1 → **403** `order_bundle_buyer_mismatch`.  
qty=2 só colou com bundle **pending** (não aceite). Checkout não usou 0,50 €.

### AN4 FSM — HOLD

| Variante | Resultado |
|---|---|
| Buyer `status=pago` | **403** `order_status_requires_capture` |
| `refund-order` buyer | **403** Sem permissão |
| Checkout após `cancelado` | **400** status cannot start payment |
| Cancel unpaid | 200 (pré-pago permitido) |

Código GET settle: order `cancelado` + PI novo → `refundOversoldStripeOrder`. Sem captura TEST para confirmar o refund.

### AN5 Stock / hold — HOLD

2× `aguarda_pagamento` stock=1 → 2.º **400** `order_hold_exceeds_stock`.  
2× `reserva_pendente` stock=1 → 2.º **400** igual. Staging: RPC `batata_order_status_holds_product_qty('reserva_pendente')` = **true** (repo RTBB-B-2012 no SQL local exclui pending — **drift código vs staging**, staging mais fechado).  
PATCH qty 1→9 → **403** immutable.  
B2 no SKU com hold B1 → **400** hold.

### AN6 Race — HOLD no ponto testado

Dois POST paralelos no mesmo saco → 1 Session.  
Dois INSERT stock=1 → 1 hold.

### AN7 2.º actor — HOLD

B2 checkout order B1 → 400 `order does not belong to buyer`.  
B2 saco [B1, B2] → 400 igual.  
B2 bundle_id B1 → 403.  
S2 `refund-order` order S1 → 403 Sem permissão.

### AN8 Caixa — PARCIAL

Wallet buyer/seller = 0 após fixtures **unpaid**. Sem captura Stripe TEST → sem Δwallet/Stripe net. Não se afirma P0 caixa.

--------------------------------------------------
## GAPS (não inflacionam P0/P1)
--------------------------------------------------

- Pagar as duas Checkout Sessions do recompose A+B / A+C (prova 2 cs_ vivos vs expire OK). Browser MCP falhou; publishable key da página não retrieve a Session.
- Payout Connect / refund residual / 2.ª captura após `pago`.
- Live broadcasting activo (só ended floor).
- AN8 com cartão TEST 4242.

--------------------------------------------------
## ATROFIA
--------------------------------------------------

Não. Variantes exactas da lista (orphan A+B→A+C de preço diferente, single→bag orphan, bag race two-open, currency≠eur exact, qty 1→9 hold, bundle aceite qty>1) **não** foram o corpo dos achados. O único falso positivo (qty=2) era bundle **pending**, não Y2.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

Pasta: `tool/redteam_blind_an_20260902T1015/`

- `FROZEN_REPORT.md` (este ficheiro)
- `matrix.json` / `findings.json` (pass1; finding qty=2 **reclassificado**, não conta)
- `matrix_pass2.json` / `notes_pass2.json`
- `observe_recompose.json` (sid1≠sid2, amounts iguais)
- Probes: `scripts/probes/redteam_blind_an_20260902T1015*.dart`

Nenhum secret no relatório. Produção não tocada. Fase 4 não iniciada. Código **não corrigido**.
