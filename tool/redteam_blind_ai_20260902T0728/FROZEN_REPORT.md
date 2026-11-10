# RED TEAM CEGO AI — PÓS-FECHO AEAFAG · CHAT / PROVAS / UI

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 8
P3 aberto: SIM          → quantos: 4  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AI_CHAT_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T06:40:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AI1, AI2, AI3, AI4, AI5, AI6, AI7, AI8]
VEREDICTO: FAIL_P2
```

**Missão:** depois dos fechos AEAFAG chat, ainda consigo forjar recibo, mentir MB WAY/disputa/cancel/review/oferta, ou injectar URL/prova falsa?

**Resposta:** sim — o chat ainda mente (display/label/notes/inbox/artigos do conjunto/papéis da oferta) e ainda aceita URL de prova fora do fluxo assinado. Sem mint directo nem dinheiro irreversível.

Prefixo fixtures: `RTAI-20260902T0728-`. Staging `fxdknzrqjenzqcvnwqqq`. Stripe TEST não foi necessário (recibo pago via fixture E2E `setup_paid_order`, 590 cêntimos). `service_role` só fixture.

Anti-atrofia: **0** achados = lista exacta AF/AC/Z (FF/VT/Ogham/LS/PS JSON, outcome `updated`, label PIX inteiro ASCII, notes «Comprovativo MB WAY 4321,00 €», inbox «Transferência», `fleaber.app` proof, raw `{`, DELETE unicode exact). Variantes novas abaixo.

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 8
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 4
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (só card/UI)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO (fora de poço chat)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 read/write thread e upsert storage bloqueados)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (`review_order_invalid_status` no pago de teste)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO neste poço
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (kind `marketplace_bag_paid` server-only)
27. Regressão funcional (happy path partido) — SIM (URL assinada de prova negada; kinds de reminder do cliente negados)
28. Saturação atingida — NÃO (mais sinónimos inbox/notes possíveis; a classe está demonstrada)

---

## FIXTURES

| Peça | ID |
|------|-----|
| chat B–S | `1b1250c4-8c4e-43a6-949b-16b8b6b7b496` |
| order pago (590 cêntimos) | `6fe7add4-c087-4ad1-9619-4520a4b7273a` |
| order reservado | `ffc2bb9a-1991-4811-acb4-e5feff94cc10` |
| order cancelado | `4d41b9bb-68b4-4147-a91c-a0d70547f0ae` |
| buyer2 | `c908ae94-3747-4b61-a04c-20dd7169983e` |
| evidência | `tool/redteam_blind_ai_20260902T0728/findings.json` · `pass2.json` |

---

## P2 ABERTO (8)

### P2-01 · AI1 · `display` de cancel livre (outcome válido)

**Pré:** `assert_json_card` restringe `outcome` a `accepted`/`rejected` e cruza estado da encomenda; **não lê `display`**. Flutter `_buildCancelOutcomeFromPayload` pinta `payload.display` verbatim.

**Repro (pago, outcome honesto `rejected`):**
```
POST chat_messages jwt=seller
text=FLEABER_JSON_V1:{"kind":"cancel_request_outcome","order_id":"<pago>","outcome":"rejected","display":"Compra cancelada — Reembolso 4321 EUR processado na hora."}
```
HTTP **201** msg `1143`. Texto persistido (pass2 GET).

**Repro (cancelado real, `accepted` + display mentirosa):** msg `1144` HTTP 201, display `Reembolso 4321 EUR confirmado (PIX).`

Não é o caso exacto `outcome=updated` (esse está fechado). O vendedor mente o **texto do card** com outcome legal. `_chatShowsOrderCancelled` só olha `outcome==accepted`, portanto o card «Compra paga» no pago **não** vira cancelado no caso `rejected` — a mentira é a linha do outcome.

Pass2: PATCH/DELETE jwt=seller de `1143` → `chat_system_card_immutable` (403). Card imutável, mas a mentira fica.

### P2-02 · AI1 · `seguro_fleaber_paid` label PIX/MB WAY sem dígitos ASCII

**Pré:** mismatch de label só se `v_label ~ '\d' AND` keywords. Sem dígitos ASCII o ramo não corre.

**Repro:** buyer, order pago 5,90 €:
```
kind=seguro_fleaber_paid order_id=<pago> total=5.9
label="PIX confirmado — pagamento recebido via MB WAY"
```
HTTP **201** msg `1145`. Flutter concatena o label na linha «Seguro Fleaber».

Variante fullwidth `PIX ４３２１ €` → **bloqueada** (`label_mismatch`) — nesta instância PG `\d` parece Unicode; extração `[0-9]` falha. Não contar como aberto.

### P2-03 · AI1 · `notes` de comprovativo furam `payment_lie_text`

Flutter mostra `Observações: $notes` no card `reservation_payment_submitted`.

| notes | HTTP | msg |
|-------|------|-----|
| `Reembolso 4321 € já enviado` | 201 | 1151 |
| `Pagamento aprovado 4321 €` | 201 | 1152 |
| `Transferencia 4321 EUR` (sem acento) | 201 | 1154 |
| `MB WAY confirmado pelo banco` (sem montante) | 201 | 1156 |
| `IBAN recebido 4321 EUR` | 201 | 1157 |
| `MB WAY 4321 euros` | 400 notes_forbidden (`EUR` casa prefixo de `euros`) | — |
| `MB WAY ４３２１ €` | 400 notes_forbidden | — |

Não é o texto exacto «Comprovativo MB WAY 4321,00 € confirmado».

### P2-04 · AI1 · `bundle_proposal` `product_ids` decoy

**Pré:** assert só `bundle_id` + `total_eur`. Flutter `BundleProposalChatCard` lista artigos de `payload.product_ids`.

**Repro:** conjunto real `total_eur=40` + `product_ids=[decoy 999 €]`. HTTP **201** msg bundle card. O total no JSON bate com a BD; a grelha de artigos mente.

### P2-05 · AI1 · `price_offer` papéis no JSON livres

**Pré:** assert cruza `offer_id` + `amount` + status `pending`. `offered_by` / `buyer_id` / `seller_id` livres.

**Repro:** oferta real 12 €; payload `offered_by=seller`, `buyer_id=<seller>`, `seller_id=<buyer>`. HTTP **201**. `PriceOfferChatCard` usa esses campos para headline e quem vê Aceitar/Recusar. Montante = BD (não é mint de preço).

### P2-06 · AI4 · URL crua `.png` / `order_proofs` (parser legado)

`assert_json_card` faz early-return se o texto não é `FLEABER_JSON_V1:` nem `{`. Flutter `_chatImageUrlFromMessage`: `http` + extensão imagem **ou** path com `order_proofs` → bolha de imagem.

```
POST text=https://example.com/rtai-fake-proof.png     → 201 msg 1172
POST text=https://evil.test/cdn/order_proofs/stolen.jpg → 201 msg 1173
```

Isto **injecta prova/URL falsa** no fio sem prefixo de sistema.

### P2-07 · AI5 · inbox `last_message` fura o regex alargado

`batata_chat_is_forged_inbox_preview` = `payment_lie_text` (keywords + €/EUR). PATCH `chats.last_message` jwt=buyer:

| preview | HTTP |
|---------|------|
| `Reembolso 4321 €` | 200 |
| `Transferencia 50€` | 200 |
| `PayPal 50€` | 200 |
| `Bizum 50€` | 200 |
| `ＰＩＸ 50€` (PIX fullwidth) | 200 |
| `Recebi 50€` | 200 |
| `MB WAY 50 euros` | 403 (EUR⊂euros) |
| `confirmado ４３２１ €` | 403 |

Não é o token exacto `Transferência` com acento.

### P2-08 · AI8/AI4/AI2/AI5 · prova assinada negada + unsigned aceite + Cf à frente do prefixo

**Happy path partido:** upload real `fleaber_private/order_proofs/{buyer}/{order}/…_rtai.png` (HTTP 200). `createSignedUrl` →  
`https://…/storage/v1/object/sign/fleaber_private/…?token=…`  
POST `reservation_payment_submitted.proof_url=<signed>` → **400** `chat_system_card_url_denied`.

O `like` exige  
`/storage/v1/object/fleaber_private/%`  
não `/object/sign/`. O cliente (`FleaberPrivateStorage.uploadOrderProof`) devolve signed URL.

**Atacante:** o mesmo path em forma **unsigned**  
`https://…/storage/v1/object/fleaber_private/order_proofs/…/…png` → **201** msg `1178`. Flutter carrega `proof_url` cru (`BatataCachedNetworkImage`).

GET `…/fleaber_private/../public/x.png` → 400 `Bucket not found` (não é open-redirect comprovado; ver P3).

**Cf + prefixo (não é FF/VT/Ogham/LS/PS):** `U+200B` + `FLEABER_JSON_V1:{...}` INSERT 201 (assert saltado: `v_raw not like 'FLEABER_JSON_V1:%'`). DELETE jwt=sender da msg `1134` → **200, linha desapareceu**. Imutabilidade só casa prefixo exacto / `{` trimado. Flutter actual `startsWith('FLEABER_JSON_V1:')` **não** pinta card (ZWSP não é White_Space) — o risco é apagar/alterar mensagens que um cliente futuro que faça trim de Cf passaria a tratar como card, e já hoje apagar o JSON «escondido».

Kinds que o cliente tenta injectar (`reservation_reminder`, `reservation_payment_check_reminder`, `reservation_shipping_reminder`, `raffle_prize_awarded`) → **403** `kind_denied`. Reminders oficiais do chat falham em REST.

---

## P3 (agrupados)

### P3-01 · AI2 · JSON cru com Cf / prefixo errado (não vira card)

Aceites (201): ZWSP/ZWNJ/ZWJ/WJ/RLO/LRI/SHY/MVS/ALM antes de `{`; `fleaber_json_v1:`; `Fleaber_JSON_V1:`; `FLEABER_JSON_V1 :`. Flutter não parseia (sem prefixo exacto; `trim()` não tira Cf). Bolha de texto com `total_eur:6543.21`. `jsonc_comment` e duplicate `kind` last=seguro (total ≠ 5,90) bloqueados.

### P3-02 · AI4 · `proof_url` lixo que casa o prefixo mas não serve ficheiro

Aceites: `../public`, `?redirect=https:%2f%2f…`, `#javascript:alert(1)`, backslash, path `order_proofs/{buyer2}/…`, ZWSP no path. GET traversal ≠ leak. `%2e%2e` e `/object/sign/` bloqueados.

### P3-03 · AI4 · `chat_image.url` bucket public

201 com `url=…/object/public/…` mas path `chat_uploads/{uid}/{chat}/` obrigatório; Flutter prefere path.

### P3-04 · AI1 · campos extra sem mentira de card

- `cancel_request` sem tabela de cancelamentos (201) — CTA de cancelamento mintável; sem estado BD.
- `order_direct_payment_details` aceita `mb_way`/`iban` no JSON; UI «Ver dados» chama RPC, não o payload.

---

## BLOQUEADO (controlo)

| Lente | Resultado |
|-------|-----------|
| AI3 | `created_at` INSERT forçado a `now()`; PATCH `created_at` imutável; `last_message_time=2020` clamped |
| AI5 | PATCH/DELETE card `FLEABER_JSON_V1` exacto → `chat_system_card_immutable` |
| AI6 | B2 upsert `order_proofs/{buyer}/…` negado |
| AI7 | B2 write/read thread B–S negado |
| AI8 | `marketplace_bag_paid` server-only |
| AI1 | kinds reminder/rifa denied; review JWT no pago `review_order_invalid_status`; disputa INSERT RLS 403 |

---

## LENTES

| # | Coberto | Síntese |
|---|---------|---------|
| AI1 | SIM | display/label/notes/product_ids/papéis |
| AI2 | SIM | Cf + prefixo case; não Ogham/LS/PS/FF |
| AI3 | SIM | clamp 30s / created_at OK |
| AI4 | SIM | signed vs unsigned; HTTP legado; traversal GET falhou |
| AI5 | SIM | inbox sinónimos; DELETE Cf+prefixo; DELETE exacto OK |
| AI6 | SIM | upsert cross-user bloqueado |
| AI7 | SIM | B2 thread bloqueada |
| AI8 | SIM | signed URL app vs like; reminders denied; bag_paid OK |

---

## VEREDICTO

`FAIL_P2` — P0/P1 fechados neste poço; **8 P2** abertos (mentira de card/inbox/prova + happy path de comprovativo assinado partido). Sem correcção. Produção intocada. FASE 4 não iniciada.
