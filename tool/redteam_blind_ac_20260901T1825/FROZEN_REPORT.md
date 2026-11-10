AUDITOR: REDTEAM_BLIND_AC_POS_YZAA_v1
FROZEN_AT: 2026-09-01T17:36:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8]
VEREDICTO: FAIL_P1

## CONTAGEM

```
P0 aberto: NÃO         → quantos: 0
P1 aberto: SIM         → quantos: 7
P2 aberto: SIM         → quantos: 6
P3 aberto: SIM         → quantos: 3
```

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 7
5. P2 hygiene encontrado — SIM
6. Quantos P2: 6
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 3
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas (tabela) — NÃO
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO
27. Regressão funcional (happy path partido) — NÃO COMPROVADO
28. Saturação atingida — NÃO

## ÂMBITO

Poço: depois do fecho YZAA, forjar recibo, mentir MB WAY/disputa/cancel/review, ou injectar URL/prova — **sem mint directo**.  
Staging `fxdknzrqjenzqcvnwqqq`. Stripe TEST não foi necessário (Edge recusou sem metadata). Produção intocada. FASE 4 não iniciada. Código **não** corrigido.

Cegueira: triggers chat, RLS, cards Flutter, storage paths. Relatórios Z/Y/AA/W/V não lidos.

Prefixo fixture: `RTAC-20260901T1825-`.  
Thread: `4e89082a-a4f0-428e-9dad-5e4889a03715`  
Hold `reservado` 12,34 €: `60d32dc2-2d6f-4236-8905-9d960a240a79`  
Pago fixture (service_role): `8d22af32-c0d6-4877-b04c-def5175338bb`  
Offer pending 9,50 €: `3fec2a14-7292-414d-ae7c-1fdef6fb82ac`

## ANTI-ATROFIA

Variantes **novas** (não exact Z):
- JSON cru com whitespace Unicode (não `{` no primeiro byte)
- `proof_url` em host allowlisted com URL-em-URL (não `javascript:`)
- Inbox **INSERT** (trigger só no UPDATE)
- Cards `outcome`/`price_offer` sem cruzar status da tabela
- DELETE do card Unicode (não DELETE do prefixo `FLEABER_JSON_V1`)

Exactos Z1-DIRECT / Z1-BUNDLE-RAW / Z4 javascript / Z6 UPDATE inbox / upsert storage: **HOLD**.  
Atrofia: **0%**. Não `ATROFIA_ABORT`.

## FINDINGS P1

### AC2-WS-UNICODE-RAW · P1 · AC2 · buyer
**Título:** JSON cru `bundle_proposal` prefixado com whitespace Unicode passa o INSERT; o Flutter `trim()` corta esses caracteres e pinta o card com `total_eur` do JSON.  
**Repro:** `POST chat_messages` `text=<U+00A0|U+0085|U+2003|U+202F|U+3000>{"kind":"bundle_proposal","total_eur":6543.21,...}` sem `FLEABER_JSON_V1`.  
**Impacto:** `btrim()` do Postgres não corta NBSP/NEL/em-quad/NNBSP/ideographic space. `tryParseBundleProposalChatPayload` faz `text.trim().startsWith('{')` e mostra 6543,21 €. Trigger `assert_json_card` nunca corre.  
**Prova:** msgs 985/986/987/988/989 http=201. `_bundle` nulo ⇒ card pending usa payload.

### AC1-RES-OUTCOME-REJECTED-LIE · P1 · AC1 · seller
**Título:** Card «O vendedor recusou o pedido de reserva» com encomenda ainda `reservado`.  
**Repro:** `POST FLEABER_JSON_V1 kind=reservation_request_outcome outcome=rejected order_id=<reservado>` (seller).  
**Impacto:** Cruzamento de status só existe para `outcome=accepted`. Flutter compara `payload['outcome'] == 'accepted'` e pinta recusa.  
**Prova:** msg 1001 http=201. Pass2: order `60d32dc2-…` continua `status=reservado`, `amount_paid_cents=null`.

### AC1-PRICE-OFFER-ORPHAN-AMOUNT · P1 · AC1 · buyer
**Título:** `price_offer` sem `offer_id` e `amount=9999` aceite.  
**Repro:** `POST FLEABER_JSON_V1 kind=price_offer order_id=<pago> amount=9999` (sem offer_id).  
**Impacto:** Trigger exige `order_id`, não `offer_id` nem `product_offers`. `PriceOfferChatCard`: `offerId==null` ⇒ `_resolved=true`; valor = `payload['amount']`.  
**Prova:** msg 1003 http=201.

### AC1-PRICE-OFFER-OUTCOME-STATUS-LIE · P1 · AC1 · seller
**Título:** `price_offer_outcome=accepted` com amount correcto enquanto `product_offers.status=pending`.  
**Repro:** `POST FLEABER_JSON_V1 kind=price_offer_outcome outcome=accepted offer_id=<pending> amount=9.50`.  
**Impacto:** Trigger valida amount, não status. UI: «Proposta aceite — o comprador pode concluir a compra a este preço.»  
**Prova:** msg 1004 http=201. Pass2: offer `3fec2a14-…` ainda `pending` / `9.5`. `created_at` da msg inalterado (UPDATE created_at HOLD).

### AC4-PROOF-OPEN-REDIRECT-ALLOWLIST · P1 · AC4 · buyer
**Título:** `proof_url` no card MB WAY aceita URL-em-URL em `fleaber.app` / `fleaber.pt`; o mesmo URL é recusado em `orders.proof_url`.  
**Repro:**
- `https://fleaber.app/https://evil.example/receipt.png`
- `https://www.fleaber.pt/?next=https://evil.example/x`
- `https://fleaber.app/#https://evil.example/x`
- `https://fleaber.app/<TAB>https://evil.example/x`  
**Impacto:** Allowlist do chat = prefixo de host. `batata_orders_guard_proof_url` bloqueia `https?://.+/https?://`, query e hash; o assert do chat **não**. Flutter `_openProofImageDialog(proofUrl)` sem segundo filtro.  
**Prova:** msgs 1012/1013/1014/1021 http=201. `PATCH orders.proof_url` nested → `403 order_proof_url_denied`.

### AC5-INBOX-INSERT-FORGE · P1 · AC5+AC3 · buyer
**Título:** `INSERT chats` com `last_message="Seguro Fleaber 999,00 €"` e `last_message_time=2015-01-01` aceite.  
**Repro:** `POST chats user_a/b last_message="Seguro Fleaber 999,00 €" last_message_time=2015-01-01T00:00:00Z`.  
**Impacto:** `trg_batata_chats_guard_update` só corre em UPDATE. Inbox mostra recibo forjado; data antiga não é clampada no INSERT.  
**Prova:** chat `7527829b-6779-493c-aefe-30293ba5437e` — `last_message=Seguro Fleaber 999,00 €`, `last_message_time=2015-01-01T00:00:00+00:00`.

### AC5-DELETE-UNICODE-RAW-CARD · P1 · AC5 · buyer
**Título:** O card Unicode (sem prefixo) é apagável; DELETE só protege `FLEABER_JSON_V1:%`.  
**Repro:** INSERT NBSP+JSON → `DELETE chat_messages?id=985`.  
**Impacto:** Prova visual forjada e depois apagada.  
**Prova:** DELETE http=200. Pass2 GET id=985 → `[]`. DELETE de card com prefixo (reservation_request) → `403 chat_system_card_immutable`.

## FINDINGS P2

### AC1-SEGURO-LABEL-INJECT · P2 · AC1 · buyer
Segundo `seguro_fleaber_paid` com `total=12.34` (bate com `amount_paid_cents`) + `label="PIX confirmado 4321 €"`. Flutter concatena o label. Msg 1006.

### AC1-REVIEW-STARS-PAYLOAD · P2 · AC1 · buyer
Review real 5★ (`eed04e5f-…`). Card `order_review_submitted` `stars=1` persistido (msg 1025). UI usa JSON, não `reviews.stars`.

### AC1-CANCEL-OUTCOME-UNBOUND · P2 · AC1 · seller
`cancel_request_outcome outcome=rejected` em encomenda `reservado` sem pedido de cancel (msg 1007). Mesmo buraco que outcome de reserva: só `accepted` cruza BD.

### AC3-INBOX-TIME-FUTURE · P2 · AC3 · buyer
`PATCH last_message_time=+400d` → `2027-10-06T17:33:07Z`. Guard só clampa `< now-2min`. Thread pode ficar no topo da inbox. Datas no passado no UPDATE **são** clampadas.

### AC5-INBOX-REGEX-BYPASS · P2 · AC5 · buyer
Regex `(Seguro Fleaber|Compra paga).*(\d+[,.]\d+\s*€|€\s*\d+)` não apanha:
- `MB WAY 99,00 €`
- `Seguro Fleaber 12 €` (sem decimal)
- `PIX 4321,00 €`  
Thread principal ficou com `last_message=PIX 4321,00 €`.

### AC4-PROOF-STORAGE-PUBLIC · P2 · AC4 · buyer
`proof_url=https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png` aceite (msg 1020). Qualquer objecto no host de storage passa.

## FINDINGS P3

- ZWSP/ZWNJ + JSON cru: INSERT ok; Dart `trim()` **não** corta → não vira card, lixo visível.
- `chat_image.path` com `%2e%2e`: INSERT ok; `createSignedUrl` → Object not found (sem traversal).
- JSON array `[{kind:bundle_proposal}]` e prefixo `fleaber_json_v1:` em minúsculas: texto livre, Flutter não pinta card.

## HOLDS (defesa a trabalhar)

| Teste | Resultado |
|---|---|
| `javascript:` / `data:` / `vbscript:` / `file:` / `mailto:` / userinfo / subdomain | `chat_system_card_url_denied` |
| `kind` server-only (`order_paid`, `auto_feedback_generated`) | 403 |
| `reservation_reminder` / `raffle_prize_awarded` | 403 kind_denied |
| DELETE `FLEABER_JSON_V1` | 403 immutable |
| GraphQL delete | extension off |
| `x-upsert=true` no mesmo path | 403 RLS (policy UPDATE dropada) |
| PUT storage | 400 |
| COPY overwrite no mesmo Key | 400 already exists |
| B2 lê/escreve thread, lista/assina proofs | vazio / 403 |
| anon lê mensagens | 401 |
| Edge `create-payment-intent` amount/order | 400 Missing payment metadata |
| POST upsert merge no row JSON | 400 |
| `created_at` PATCH mensagens | valor inalterado |

AC8: o chat mente; a Edge **não** aceitou captura com amount mentiroso neste probe. Sem mint.

## LENTES

| Lente | Coberta | Resultado |
|---|---|---|
| AC1 Cards vs BD | sim | P1 outcome/offer/amount; P2 label/stars/cancel |
| AC2 Prefixo / encoding | sim | P1 Unicode vs `btrim`/`trim` |
| AC3 Cronologia | sim | P1 INSERT backdate; P2 future UPDATE; created_at msg HOLD |
| AC4 URLs / provas | sim | P1 URL-em-URL allowlist; javascript HOLD |
| AC5 Inbox / delete | sim | P1 INSERT + DELETE Unicode; UPDATE regex P2 |
| AC6 Storage | sim | upsert HOLD; copy-new-name só próprio ficheiro |
| AC7 Cross-user | sim | B2 isolado (user criado via admin, fixture) |
| AC8 Edge vs chat | sim | Edge recusa; chat mente (controlo) |

## NÃO CORRIGIDO

Finding = provar → documentar → continuar. Sem patches, sem produção, sem FASE 4.

Evidência: `tool/redteam_blind_ac_20260901T1825/probe_result.json`, `pass2.json`.
