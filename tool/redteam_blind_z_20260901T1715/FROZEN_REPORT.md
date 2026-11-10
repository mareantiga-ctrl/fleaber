# FROZEN_REPORT — REDTEAM BLIND Z CHAT PÓS-W

```
AUDITOR: REDTEAM_BLIND_Z_CHAT_POS_W_v1
FROZEN_AT: 2026-09-01T16:25:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [Z1, Z2, Z3, Z4, Z5, Z6, Z7, Z8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTZ-20260901T1715-`.  
Actors: buyer JWT `bfcbeeee-…` · seller JWT `980f4fa1-…` · B2 `e621595b-…` (demo_bot_01) · anon.  
`service_role` só fixture (chat dedicado, recibo `seguro_fleaber_paid`, reserva `c3cf2791-…`, `setup_paid_order`, observação). **Nunca** actor do exploit.

Pedido Stripe TEST capturado: `1c12455b-7393-4e9e-86d0-edcd5d75083a` · PI `pi_3UAuRSH7FWYUN3jh0px9oz7V` · **590 cêntimos** `pago`.  
Thread fixture: `4aa6e40a-3bd4-468b-b17c-351dce58d4d5` (não se apagou o chat legítimo B/S).

**Não se tocou em produção. Não se iniciou Fase 4. Não se aplicou correcção.**

--------------------------------------------------
MISSÃO
--------------------------------------------------

Depois dos fechos W+VWX (JSON imutável DELETE/`created_at`, totais Seguro, cards enviados/concluídos alinhados, `proof_url` INSERT), ainda consigo forjar recibo, apagar prova, mentir cancelamento/envio, ou injectar URL/prova falsa?

**Sim, no ecrã.** O poço de dinheiro (Edge `refund-order`, PATCH `pago`, B2 na thread) **não obedece** ao chat. O poço de **autoridade visual** (totais, prazos, disputa, avaliação, comprovativos no JSON) **ainda mente**, com REST 201.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Não é a lista proibida (DELETE JSON exact, seguro `total=4321` exact, cancel `outcome=accepted` exact, `created_at` 2020 exact, `proof_url` INSERT evil em pago exact, bundle 7777 com bundle real exact).

Variantes novas: `amount_eur` no card de pagamento directo; `price_offer_outcome` sem oferta; JSON cru sem prefixo `FLEABER_JSON_V1`; `bundle_proposal` sem `bundle_id`; `proof_url` **dentro** de `reservation_payment_submitted`; `expires_at` no card (não `created_at` da mensagem); inbox `last_message`; upsert storage no mesmo path.

--------------------------------------------------
## CONTAGEM

```
P0 aberto: NÃO         → quantos: 0
P1 aberto: SIM         → quantos: 10
P2 aberto: SIM         → quantos: 6
P3 aberto: SIM         → quantos: 1
```

--------------------------------------------------
## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 10
5. P2 hygiene encontrado — SIM
6. Quantos P2: 6
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO (`orders.price_total` / Stripe 590 intactos)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (Stripe/PI); SIM no **card** (não na BD)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora do poço)
16. Stock=1 duas vendas válidas — NÃO (neste poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO COMPROVADO (B2 0 rows; sign B2 → 404; traversal cross-user sem objecto vítima privado)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO na tabela `reviews`; SIM o **card** (P1)
24. RPC SECURITY DEFINER perigoso executável — NÃO (RPCs de «pago via chat» 404)
25. RLS crítico quebrado — NÃO (B2/anon)
26. Edge confia total do cliente — NÃO (`refund-order` 403 «Sem permissão»)
27. Regressão funcional (happy path partido) — NÃO (thread fixture; chat B/S legítimo não apagado)
28. Saturação atingida — SIM neste poço (kinds restantes = mais do mesmo padrão JSON≠BD)

--------------------------------------------------
FINDINGS
--------------------------------------------------

### Z1-DIRECT-PAY-AMOUNT-LIE · P1 · Z1

**Actor:** seller JWT  
**Repro:** `POST chat_messages` `FLEABER_JSON_V1` `kind=order_direct_payment_details` `order_id=c3cf2791-…` (reserva 12,34 €) `amount_eur=1.0` (+ MB WAY/IBAN no JSON). HTTP **201**, msg `956`.  
**Impacto:** Flutter `_buildBundleDirectPaymentDetailsCard` pinta «Valor a transferir» a partir de `payload['amount_eur']`. O botão «Ver dados» reconstroi o sheet a partir de `order.priceTotal` (BD) — o **card** mente, o sheet pode não. Comprador a olhar só para o card transfere o valor errado.  
**Prova:** `probe_result.json` · msg 956.

### Z1-PRICE-OFFER-OUTCOME-FAKE · P1 · Z1

**Actor:** seller JWT  
**Repro:** `kind=price_offer_outcome` `outcome=accepted` `amount=0.01` `offer_id` fantasma, `order_id` do pedido Stripe. HTTP **201**, msg `957`.  
**Impacto:** `PriceOfferOutcomeChatCard` lê só o JSON («Proposta aceite — 0,01 €. O comprador pode concluir a compra a este preço.»). `product_offers` não é consultado. Checkout real usa a tabela de ofertas (Z8 não dispara).  
**Prova:** msg 957.

### Z1-BUNDLE-RAW-JSON-NO-PREFIX · P1 · Z1 / Z2

**Actor:** buyer JWT  
**Repro:** `POST chat_messages` **sem** `FLEABER_JSON_V1:` — corpo `{"kind":"bundle_proposal","total_eur":8888,…}`. HTTP **201**, msg `958`.  
**Impacto:** O trigger só valida prefixo `FLEABER_JSON_V1:%`. `tryParseBundleProposalChatPayload` também aceita `text.trim().startsWith('{')`. Card pinta 8888 €. Mensagem **apagável** (P2 irmão).  
**Prova:** msg 958; DELETE pass2 `gone=true`.

### Z1-BUNDLE-NO-ID-TOTAL-FREE · P1 · Z1

**Actor:** buyer JWT  
**Repro:** `FLEABER_JSON_V1` `kind=bundle_proposal` **sem** `bundle_id`, `total_eur=6543.21`. HTTP **201**, msg `959`.  
**Impacto:** `batata_chat_messages_assert_json_card` só cruza `product_bundles.total_eur` quando `bundle_id` está presente. Flutter, sem bundle, mostra o total do payload.  
**Prova:** msg 959.

### Z4-JSON-PROOF-URL-UNGUARDED · P1 · Z4

**Actor:** buyer JWT  
**Repro:** `kind=reservation_payment_submitted` `order_id=c3cf2791-…` com  
- `proof_url=javascript:alert(document.cookie)` → **201** msg `964`  
- `proof_url=https://evil.example/fake-mbway-receipt.png` → **201** msg `965`  
**Impacto:** Denylist de `chat_image` e `orders.proof_url` **não** se aplica a este campo. Flutter `_buildReservationPaymentSubmittedCard` mete `proof_url` no `CachedNetworkImage` e no dialog. XSS / comprovativo falso para o vendedor confirmar MB WAY.  
**Prova:** msgs 964–965.

### Z5-DISPUTE-CARD-SALDO-BLOQUEADO · P1 · Z5

**Actor:** buyer JWT  
**Repro:** `kind=order_dispute_opened` no pedido **pago** (à hora do INSERT ainda sem linha `order_disputes` nossa). HTTP **201**, msg `970`.  
**Impacto:** `_buildOrderDisputeOpenedCard`: se `_loadDisputeThread` devolve null, o texto é «Disputa aberta. O saldo desta transação encontra-se temporariamente bloqueado.» — **sem** disputa na BD. (Fixture posterior criou disputa `83f6b0f6-…` com `reason=em_falta` só para o teste de replies; o card já tinha mentido.)  
**Prova:** msg 970 · Flutter `chat_page_widget.dart` ~3106–3110.

### Z5-REVIEW-CARD-WALLET-COPY · P1 · Z5

**Actor:** buyer JWT  
**Repro:** `kind=order_review_submitted` `author_role=comprador` `stars=1` sem INSERT em `reviews`. HTTP **201**, msgs `971` / `977`.  
**Impacto:** UI vendedor: «Avaliação recebida (1★). O valor ficará disponível na tua carteira.» Sem review e sem release.  
**Prova:** msg 977.

### Z5-SELLER-CANCEL-CARD-ON-PAID · P1 · Z5

**Actor:** seller JWT  
**Repro:** `kind=reservation_cancelled_by_seller` `order_id=1c12455b-…` (Stripe `pago`, sem `stripe_refund_id`). HTTP **201**, msg `972`. Status da encomenda **continua `pago`**.  
**Impacto:** Flutter: «O vendedor cancelou a reserva.» Envio/concluído *estão* alinhados à BD (W); **cancelamento pelo vendedor no card não está**.  
**Prova:** msg 972 · `orders.status=pago`.

### Z3-RESERVATION-ACCEPTED-EXPIRES-BACKDATE · P1 · Z3

**Actor:** seller JWT  
**Repro:** `kind=reservation_accepted` `expires_at=2018-01-01T00:00:00.000Z`. HTTP **201**, msg `973`. `created_at` da mensagem = now() (forçado).  
**Impacto:** `_buildReservationAcceptedCard` formata `payload['expires_at']` («Tens até 1 jan 2018 para pagar»). Cronologia do **prazo**, não da timeline `created_at`.  
**Prova:** msg 973.

### Z5-RESERVATION-OUTCOME-NO-STATE · P1 · Z5

**Actor:** seller JWT  
**Repro:** `kind=reservation_request_outcome` `outcome=accepted` na reserva fixture. HTTP **201**, msg `974`.  
**Impacto:** Card «Reserva aceite — o prazo de pagamento foi iniciado.» sem cruzar estado.  
**Prova:** msg 974.

--------------------------------------------------
P2 / P3
--------------------------------------------------

### Z4-CHAT-IMAGE-ARBITRARY-HTTPS · P2 · Z4  
`kind=chat_image` `url=https://evil.example/…` HTTP 201 (msg `961`). Guard só `javascript:` / `data:` / `//`. Flutter `url.startsWith('http')`.

### Z4-CHAT-IMAGE-PATH-TRAVERSAL-STORED · P2 · Z4  
`path=chat_uploads/../order_proofs/{buyer}/{order}/…` persistido (msg `963`). `createSignedUrl` no **próprio** objecto normaliza e assina (pass2). Cross-user **não comprovado** (sem objectos `fleaber_private` de outro buyer listáveis).

### Z4-PROOF-URL-UNPAID-EXTERNAL · P2 · Z4  
`PATCH orders.proof_url=https://evil.example/…` em `reservado` HTTP 200. Allowlist de host só corre quando `v_paid`. Se o pedido passar a pago **sem** UPDATE de `proof_url`, o URL externo sobrevive.

### Z4-STORAGE-UPSERT-PROOF · P2 · Z4  
`POST storage/v1/object/fleaber_private/order_proofs/{buyer}/{order}/RTZ-…overwrite.png` `x-upsert: true` → 200. URL estável, bytes substituíveis.

### Z6-INBOX-LAST-MESSAGE-FORGE · P2 · Z6 / Z3  
`PATCH chats` `last_message='Compra paga através do Seguro Fleaber (9999.00 €)'` `last_message_time=2010-01-01`. HTTP 200. Inbox mente valor e ordem.

### Z2-DELETE-RAW-BUNDLE-CARD · P2 · Z2  
DELETE da msg `958` (JSON cru) `gone=true`. Imutabilidade só cobre prefixo `FLEABER_JSON_V1:`.

### Z2-BOM-PREFIX-JSON · P3 · Z2  
`U+FEFF` + `FLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","total":"4321"}` HTTP 201, msg `975`. Trigger não vê o prefixo; Flutter `startsWith` também não — bolha de texto, não card. Hygiene.

--------------------------------------------------
FECHOS (poço Z — não são findings)
--------------------------------------------------

| Teste | Resultado |
|-------|-----------|
| DELETE `chat_messages` JSON (recibo svc `953`) | **CLOSED** 403 `chat_system_card_immutable` |
| DELETE `chats` com JSON dentro | **CLOSED** 403 `chat_system_card_immutable` (não há CASCADE) |
| UPSERT PostgREST no recibo | **CLOSED** 403 |
| Bulk DELETE `text=like.*FLEABER_JSON_V1*` | **CLOSED** 403 |
| PATCH plain → JSON + DELETE | upgrade 200; DELETE JSON **CLOSED** 403 |
| GraphQL delete | extensão `pg_graphql` desligada |
| `created_at=2015` no INSERT | **CLOSED** forçado `now()` |
| `kind=order_paid` JWT | **CLOSED** `chat_system_card_server_only` |
| `seguro_fleaber_paid` total ≠ 5,90 | não retestado exact 4321; extra keys `display_total` ignoradas pela UI |
| `reservation_order_shipped` em `pago` | **CLOSED** `chat_system_card_status_mismatch` |
| `reservation_order_completed` | **CLOSED** 400 |
| `chat_image` `JAVASCRIPT:` | **CLOSED** 400 |
| `proof_url` pago `supabase.co.evil.example` | **CLOSED** `order_proof_url_denied` |
| `fleaber.app/redirect?u=https://` | **CLOSED** 403 |
| B2 GET/INSERT mensagens | **CLOSED** 0 rows / 403 |
| B2 PATCH inbox | 2xx **0 rows** |
| anon GET | **CLOSED** 401 |
| `refund-order` após cards forjados | **CLOSED** 403 «Sem permissão.» · encomenda continua `pago` / 590 ¢ / `stripe_refund_id` null |
| Seller `PATCH status=pago` na reserva fixture | **CLOSED** `batata_stock_insufficient` (não é Edge a ler o chat) |
| PATCH `order_dispute_replies.proof_photos` → javascript | HTTP 200 **0 rows** / fotos inalteradas — **CLOSED** na prática |

Z8: **chat mente, Edge/caixa não obedece.**

--------------------------------------------------
NOTAS DE FIXTURE
--------------------------------------------------

- Recibo servidor msg `953` (label `RTZ-20260901T1715-svc-receipt`) permanece — imutável.  
- Disputa fixture `83f6b0f6-2238-4780-a0a3-b17bd48713a2` no pedido e2e (reason `em_falta`) para o teste de replies.  
- Objecto storage `fleaber_private/order_proofs/…/RTZ-20260901T1715-overwrite.png`.  
- Artefactos: `probe.dart` / `pass2.dart` / `pass3.dart` · `probe_result.json` · `pass2_result.json` · `pass3_result.json`.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
