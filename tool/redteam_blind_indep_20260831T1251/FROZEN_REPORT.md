# FROZEN_REPORT — REDTEAM_BLIND_INDEP_v4

```
AUDITOR: REDTEAM_BLIND_INDEP_v4
FROZEN_AT: 2026-08-31T13:12:00Z
production_touched: false
fase4: false
corrections_applied: false
stamp: 20260831T1251
project: fxdknzrqjenzqcvnwqqq (STAGING)
Stripe: TEST (captura pm_card_visa via Edge e2e fixture)
```

Auditor cego da segunda onda. Sem correções. Sem produção. Sem Fase 4.  
`service_role` só fixture / evidência / cleanup. Findings de autoridade exigem JWT ou anon.

Prefixo fixtures: `RTI4-20260831T1251-`.

Probes: `tool/redteam_blind_indep_20260831T1251/` (`_rt.dart`, `pass1.dart` … `pass5.dart`).  
Bruto: `tool/redteam_blind_indep_20260831T1251/out/pass*.json`.

--------------------------------------------------
## Poços
--------------------------------------------------

| Poço | Exercitado | Captura / estado final |
|------|------------|------------------------|
| 1 morto/montra | SIM | Hold/Session/BD; captura Stripe do SKU morto **não** paga (Session ≠ captura). Captura TEST noutro fluxo (poço 2). |
| 2 pós-caixa | SIM | Order `pago` + PI `succeeded` 590¢; saltos JWT; refund; review; disputa; GET settle unpaid |
| 3 política fina | SIM | Anon 401 tabelas base; views Hub; silent PATCH; RPC DEFINER |
| 4 órbita | SIM | Connect origin; tips; follows/fav; device token; cron; webhook; auto-feedback |

Race N=4 em `quantity=1`: 1 hold, 3× `order_hold_exceeds_stock`.  
Composição: unlist→offer→accept→order; bundle→unlist membro→accept→order; live leftover `is_active`→order unlist→Session; pago→enviado→refund; Session→unlist→GET settle.

--------------------------------------------------
## Invariantes A–L
--------------------------------------------------

| ID | Núcleo single-checkout | Segunda onda |
|----|------------------------|--------------|
| A | **HOLD** — PI TEST 590¢ `succeeded`, order `amount_paid_cents=590` `status=pago` | **HOLD** — GET settle unpaid após unlist ≠ pago (HTTP 402) |
| B | **HOLD** — PATCH `amount_paid_cents`/`pi_fake` 403, valores intactos | **HOLD** — qty client ignorada no hold (qty selada); offer amount não chegou a captura |
| C | **HOLD** — `wallet_release_processed_at` null após `concluido` mão; JWT não grava flag (403) | **NÃO COMPROVADO** delta wallet exacto (query `wallet_transactions.category` 42703) |
| D | **HOLD** — 4 INSERT // qty=1 → 1 hold | **HOLD** — 2.º order `is_sold` / unlist bloqueados |
| E | **HOLD** — JWT não cria PI/payout; refund buyer 403 | **HOLD** — release RPC JWT → `false` |
| F | **NÃO COMPROVADO** (não forçámos MB WAY neste freeze) | — |
| G | **HOLD** — seller refund após `enviado` 403 `order_refund_blocked_status` | — |
| H | **HOLD** — disputa JWT alheio RLS 403; refund fresh 403 | — |
| I | **NÃO COMPROVADO** (sem payout Connect Transfer neste freeze) | — |
| J | n/a | — |
| K | **HOLD** — unlist após Session unpaid não marca pago | **HOLD** — Hub vazio para unlist/`is_sold` |
| L | **HOLD** — bundle INSERT unlist `bundle_product_not_listed`; hold sold `order_hold_product_sold` | **FALHA parcial (P2)** — offer+accept unlist persiste; bundle accept após unlist persiste (sem hold do morto) |

--------------------------------------------------
## Findings
--------------------------------------------------

### P0 / P1
Nenhum com cadeia de atacante JWT/anon + efeito económico permanente.

**Descartado como P1 (anti-falso-positivo):** `P1-ZOMBIE-LIVE-UNLIST`  
- **O que aconteceu:** com `lives.status=ended` e `is_active=true`, buyer JWT fez hold + `create-payment-intent` devolveu `checkoutUrl` `cs_test_…` para produto `list_on_marketplace=false` **sem** `live_item`. Hub `hub_products_public` vazio.  
- **Porque não é P1:** `is_active=true` foi posto com **service_role** (fixture). Seller JWT `PATCH lives` → **403** `permission denied for table lives`. Em freeze **zero** lives `is_active=true` no staging. Sem pré-condição armável pelo atacante, não há autoridade.  
- **Latente (P2):** o SQL `batata_live_is_active_now` trata `is_active` residual como directo; o bypass de unlist **não exige** o produto em `live_items`. Se um completo Mux falhar a baixar `is_active`, ou se o seller voltar a ter GRANT UPDATE (a app Flutter ainda faz PATCH `status=live, is_active=true`), a Session de SKU morto reproduz-se com buyer JWT.  
- **SESSION CRIADA ≠ CAPTURA:** essa Session **não** foi paga. Order não passou a `pago`.

### P2

**P1-OFFER-UNLIST** — Oferta + accept em SKU unlist persiste  
- Actor: buyer JWT INSERT `product_offers` amount=2; seller JWT PATCH `accepted`.  
- Pré: `list_on_marketplace=false`, Hub vazio, buyer SELECT products → `[]`.  
- Depois: offer `status=accepted`. `POST orders` → 400 `order_hold_product_not_listed`.  
- Impacto: contrato fantasma / UX de proposta sobre morto; **sem** hold nem Session.  
- Repro: UUID conhecido → POST offer → PATCH accepted → POST orders.

**P1-BUNDLE-ACCEPT-AFTER-UNLIST** — Seller aceita conjunto depois de unlist de um membro  
- Pré: bundle pending com 2 listed; seller unlist+`is_sold` num membro.  
- PATCH `accepted` persiste; `subtotal_eur` recalculado para o vivo (6.00). `product_ids` ainda inclui o morto.  
- Order do membro morto → 400 `order_hold_product_sold`. Order do vivo + checkout → Session (SKU ainda listado — esperado).  
- Impacto: conjunto aceite com UUID morto no array; sem segunda venda do morto.

### P3 / residual
- Favorite INSERT em unlist (UUID conhecido) → 201. Sem SELECT do morto.  
- `create-mux-live` devolve `stream_key` ao **seller** dono (esperado para publicar). Buyer `GET lives` 403.  
- Tip pending em live `ended` permitido (decisão de produto Extra A); `PATCH status=completed` HTTP 200 mas ficou `pending` (silent); Edge `Client tip_id is not allowed.`; wallet tip ended `not_allowed`.  
- Webhook sem assinatura 400 `missing_signature` (núcleo; residual).  
- `create-connect-account` com `web_return_origin` evil → URL Connect Stripe, **sem** eco evil (HOLD).  
- HTTP 200 silent: buyer PATCH `enviado` / seller PATCH `concluido` em order `pago` → status não muda (não é finding).

--------------------------------------------------
## Tácticas
--------------------------------------------------

1. Race N=4 stock qty=1 — 1 hold.  
2. Composição unlist×offer, unlist×bundle, leftover live×unlist×Edge, pago×enviado×refund, Session×unlist×settle.  
3. Pagar TEST **1×**: `sec-fase2-e2e-oversell` `setup_paid_order` PI `pi_3UATx7H7FWYUN3jh0SX9MSQV` `succeeded` 590¢, order `bedc6a59-bd37-45e5-8704-72a6f57d8f34` `pago`. Segunda captura: order `e0c09e65-25bd-45d5-978d-3d0bc25bf000` mão → buyer `concluido`.  
4. Contabilidade: captura 590 = `amount_paid_cents`; refund seller após enviado recusado; sem refund extra. Release wallet flag continua null.  
5. Payload Edge: `buyer_id`/`amount` hostil no 2.º checkout (produto já unlist — ordem pode ter falhado); GET settle fake `cs_` 400 sem oráculo Stripe. Tip Edge rejeita `tip_id` cliente. Connect origin evil não redirecciona.  
6. Buyer fresco signup `b34d49a1-…` / `269de162-…`: refund/disputa/follows hijack 403.  
7. Anon Hub views 200; anon `products`/`profiles`/`lives` 401.  
8. Distinção: Session unlist leftover **criada**; **não** capturada. Captura permanente só no fluxo listed e2e.

--------------------------------------------------
## Não é finding
--------------------------------------------------

- HTTP 200 silent revert de status.  
- RPC 404 por assinatura (args vazios).  
- Coluna `cost_price` / `deleted_at` / `email` em profiles **não existem**.  
- `create-mux-live` deixa `status=scheduled is_active=false` — unlist **não** bypassa (400 `order_hold_product_not_listed`). Completámos o live (`complete-mux-live` 200) para não deixar directo aberto.

--------------------------------------------------
## Checklist 1–28
--------------------------------------------------

```
1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: NÃO
4. Quantos P1: 0
5. Buyer manipula preço autoritativo: NÃO
6. Buyer manipula qty autoritativa: NÃO
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO COMPROVADO
12. Stock=1 duas vendas válidas: NÃO
13. Stock=1 duas capturas líquidas permanentes: NÃO
14. Bypass capacidade/reserva: NÃO
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: NÃO
21. RLS crítico quebrado: NÃO
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: SIM
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: SIM
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços v4 exercitados: morto/montra=SIM · pós-caixa=SIM · política fina=SIM · órbita=SIM
ATROFIA (só redescobriu núcleo fechado): NÃO

VEREDICTO: D PASS_CEGO_SATURADO
```

**Item 23 SIM** porque: (a) Transfer/payout Connect não exercitado; (b) off-platform MB WAY não exercitado; (c) delta wallet pós-`concluido` sem ledger limpo; (d) captura do SKU morto com leftover `is_active` não paga. Nenhuma destas é P0/P1 demonstrado.

**PASS_CEGO_SATURADO:** poços 1–3 tentados; A–L tentados no núcleo (pass 2) e na segunda onda (unlist/Hub/bundle/offer/live leftover/pós-pago); último passe (pass 5) sem classe nova P0/P1; ATROFIA=NÃO (os P2 são offer/bundle/gate leftover — não a lista anti-atrofia do núcleo).

--------------------------------------------------
## Cleanup
--------------------------------------------------

Lives `RTI4-20260831T1251-*` → `ended` `is_active=false` (incl. Mux `complete-mux-live`).  
Products título `RTI4-20260831T1251-*` → `list_on_marketplace=false`.
