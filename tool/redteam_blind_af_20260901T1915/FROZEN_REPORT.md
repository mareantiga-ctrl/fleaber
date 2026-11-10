# FLEABER — RED TEAM CEGO AF
## Auditor independente · PÓS-FECHO ABACAD · CHAT / PROVAS / UI

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 5
P2 aberto: SIM          → quantos: 4
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0  (fora de âmbito)
```

```
AUDITOR: REDTEAM_BLIND_AF_CHAT_POS_ABACAD_v1
FROZEN_AT: 2026-09-01T18:32:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AF1, AF2, AF3, AF4, AF5, AF6, AF7, AF8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq`. Stripe TEST não necessário (Edge recusou sem metadata; recibos via `service_role` só fixture). Produção intocada. FASE 4 não iniciada. Código **não** corrigido.

Prefixo fixtures: `RTAF-20260901T1915-`  
Actors JWT: buyer `bfcbeeee-…` · seller `980f4fa1-…` · buyer2 `RTAF-20260901T1915-b2@fleaber.test`  
Chat: `b3188bdd-c957-46c1-8f0f-db55ba442605`  
Pedidos fixture: reservado `352251b6-…` · pago `3b6fc32f-…` · unpaid `6588c6e0-…`

Provas brutas: `tool/redteam_blind_af_20260901T1915/findings.json` · `findings_pass2.json`

Não foram lidos relatórios AC/Z/Y/AA/W/V. Superfície estudada: trigger `batata_chat_messages_assert_json_card` / `batata_chat_strip_unicode_ws` / inbox guards, RLS `chat_messages`, Flutter `tryParseBundleProposalChatPayload` + cards de outcome/prova, storage `fleaber_private`.

Anti-atrofia: 0/5 P1 são os exactos da lista AC/Z (NBSP+JSON, outcome=rejected, offer orphan, offer outcome=pending, URL-em-URL https, inbox INSERT exact, DELETE unicode card, javascript proof, `{` cru). Variantes novas.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 5
5. P2 hygiene encontrado — SIM
6. Quantos P2: 4
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (card mente; `amount_paid_cents` / PI intactos)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 SELECT thread = 0 rows; storage B2 = 404/RLS)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`chat_system_card_buyer_only` em `reservation_payment_submitted`)
23. Reviews forjadas — NÃO (`chat_system_card_review_missing`)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`create-payment-intent` 400 Missing payment metadata; chat recusou `seguro_fleaber_paid` em unpaid)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — NÃO

--------------------------------------------------
## P1 (5)
--------------------------------------------------

### AF-P1-01 · AF2/AF5 · JSON cru com White_Space residual → card bundle fantasma (mutável / apagável)

**O que é:** o trigger só trata como card de sistema JSON que, depois de `batata_chat_strip_unicode_ws`, começa por `{`, ou texto com prefixo exacto `FLEABER_JSON_V1:`. O strip não remove Form Feed (U+000C), Vertical Tab (U+000B), Ogham space (U+1680), Line Separator (U+2028) nem Paragraph Separator (U+2029). O Flutter, em `tryParseBundleProposalChatPayload`, faz `text.trim()` (Unicode White_Space) e depois `jsonDecode` sem exigir o prefixo — só para `kind=bundle_proposal`. O card usa `payload.total_eur` quando não há bundle na BD.

**Repro (buyer JWT):**
```
POST /rest/v1/chat_messages
text = U+000C + {"kind":"bundle_proposal","total_eur":6543.21,...}
```
Variantes 201: FF msg `1027` · VT `1028` · Ogham `1029` · LS `1030` · PS `1031`. Simulador Dart `trim()+jsonDecode` → `flutter_parses=true`.

**Pass 2:** PATCH msg `1027` (ainda FF+JSON, sem prefixo) `total_eur` 6543.21 → 1.00 (HTTP 200). DELETE msg `1028` removeu a linha (HTTP 200, `still=null`). DELETE de `FLEABER_JSON_V1:` próprio → 403 `chat_system_card_immutable` (controlo).

**Não é** o exact `{` cru nem NBSP+JSON: esses caracteres já estão no strip. ZWSP/ZWNJ/RTL inserem (201) mas o Flutter `trim()` não os tira — não pintam card; são só lixo apagável (ver AF-P2-03).

**Impacto:** o interlocutor vê uma proposta de conjunto com total inventado, sem `bundle_id`. O autor pode alterar o número ou apagar o card. Não mexe em `product_bundles` nem em dinheiro (AF8).

---

### AF-P1-02 · AF1 · `reservation_request_outcome` sem `accepted`/`rejected`

**O que é:** o trigger só cruza `orders.status` se `outcome` for `accepted` ou `rejected`. Qualquer outro valor (ou campo omisso) passa. O Flutter faz `accepted = payload['outcome'] == 'accepted'` e no else pinta «O vendedor recusou o pedido de reserva.»

**Repro (seller JWT, pedido reservado `352251b6`):**
- sem `outcome` → 201
- `outcome=expired` → 201
BD continua `status=reservado`.

**Não é** o exact `outcome=rejected` em reservado.

**Impacto:** o comprador lê recusa; o prazo/stock da reserva na BD mantém-se.

---

### AF-P1-03 · AF1 · `reservation_accepted` em pedido pago

**O que é:** para `reservation_accepted` o trigger compara `expires_at` com `reservation_expires_at` (se este não for null) e exige papel seller. Não exige status `reservado`. O Flutter pinta «Tens até {expires_at} para pagar» / «Aguarda o pagamento…».

**Repro (seller JWT):** `kind=reservation_accepted` `order_id=<pago 3b6fc32f>` `expires_at=<igual à BD>` → 201. Pedido: `status=pago`, `amount_paid_cents=1234`.

**Impacto:** card de «ainda podes pagar» sobre uma captura já feita. Não altera o pedido.

---

### AF-P1-04 · AF1 · `cancel_request_outcome.display` livre = recibo de reembolso falso

**O que é:** `cancel_request_outcome` só valida BD se `outcome` ∈ {accepted, rejected}. `outcome=updated` (ou outro) não é cruzado. O Flutter `_buildCancelOutcomeFromPayload` mostra `payload['display']` cru se não vazio.

**Repro (seller JWT, pedido pago):**
```
kind=cancel_request_outcome
order_id=<pago>
outcome=updated
display=Cancelamento aceite — reembolso de 4321,00 € processado na hora.
```
→ 201. BD: `status=pago`, `stripe_refund_id` null.

**Impacto:** o chat afirma reembolso de 4321 €. Carteira/Stripe não mexidos (AF8). Caminho explorável de fraude social no fio.

---

### AF-P1-05 · AF1 · `price_offer_outcome` sem `accepted`/`rejected`

**O que é:** o trigger só compara `product_offers.status` para `accepted` / `rejected`. `PriceOfferOutcomeChatCard`: se `outcome != 'accepted'` pinta «Proposta recusada.» (usa `payload.amount`).

**Repro (seller JWT, oferta pending amount=9.50):**
- `outcome=withdrawn` → 201
- campo `outcome` omisso → 201

**Não é** o exact `outcome=pending`.

**Impacto:** o comprador lê recusa; a oferta na BD continua `pending`.

--------------------------------------------------
## P2 (4)
--------------------------------------------------

### AF-P2-01 · AF1 · label `seguro_fleaber_paid` foge ao regex decimal+€

`total` tem de bater com `amount_paid_cents` (12.34). O check do `label` só corre se casar `(Seguro|PIX|MB WAY|Compra paga).*\d+[,.]\d+\s*€`.

Aceites (buyer JWT, pedido pago):
- `label=PIX 4321 €` (inteiro, sem casas)
- `label=MB WAY 4321,00 EUR` (€ ausente)

Flutter concatena o label no subtítulo do card «Comprado! / Venda paga».

---

### AF-P2-02 · AF1 · `reservation_payment_submitted.notes` livre

201 com `notes=Comprovativo MB WAY 4321,00 € — transação XYZ`. Flutter: «Observações: …». Sem `proof_url`. Mentira de MB WAY no texto do card, não no thumbnail.

---

### AF-P2-03 · AF5 · preview da inbox foge ao regex ABACAD

`batata_chat_is_forged_inbox_preview` = `(Seguro Fleaber|Compra paga|MB WAY|PIX).*(\d+[,.]?\d*\s*€|€\s*\d+)`.

INSERT chats aceite:

- NBSP: `MB\u00a0WAY 4321,00 € confirmado` → chat `f006e599-…`
- concat: `MBWAY 4321,00 €` → `b037a8ef-…`
- transfer: `Transferência confirmada 4321,00 €` → `3d1b428e-…`
- EUR: `Pagamento recebido 4321,00 EUR` → `90a9b582-…`

PATCH thread existente → `Transferência confirmada 4321,00 €` (200).

Bloqueados (regex ainda casa): `MB WAY 4321,00€` · `Compra paga 99,00 €` · PATCH `MB WAY 12€`.

ZWSP/RTL/fullwidth JSON cru: INSERT 201 e DELETE 200 (não são `FLEABER_JSON_V1:` nem `btrim {`). Lixo na timeline, não card.

---

### AF-P2-04 · AF4/AF7 · `proof_url` / `chat_image.url` allowlist ainda larga

`javascript:` / `data:` / `vbscript:` / `blob:` / `file:` / host com backslash → denied (controlo). Nested `https://…/https://` e `/object/public/` no proof do card → denylist presente no SQL (não retestados os exactos AC).

Ainda 201 em `reservation_payment_submitted.proof_url` (Flutter `Image.network` sem 2.º filtro):

- origem marketing: `https://fleaber.app/favicon.ico`
- origem .pt: `https://www.fleaber.pt/robots.txt` (GET 200 neste host)
- CRLF percent: `https://fleaber.app/x%0d%0aLocation:%20https://evil.example/…`
- query proto-rel: `https://fleaber.app/l?next=//evil.example/receipt.png`
- query host nu: `https://fleaber.app/l?u=evil.example/receipt.png`
- fragment: `https://fleaber.app/x#@evil.example/…`
- traversal LIKE: `…/object/fleaber_private/../public/avatars/x.png`
- `%2e%2e`: `…/fleaber_private/%2e%2e/public/avatars/x.png`
- path outro uid: `…/fleaber_private/order_proofs/{buyer2}/{order}/x.png`

`orders.proof_url` (pedido reservado) aceitou o mesmo `https://fleaber.app/favicon.ico` (paridade allowlist larga, não nested-URL).

`chat_image.url` aceita `…/object/public/avatars/x.png` (esta allowlist não tem o denylist `/object/public/` do proof). Path continua `chat_uploads/{sender}/…`.

DNS `fleaber.app` falhou neste PC (`Failed host lookup`) — open-redirect HTTP não comprovado. O card persiste a URL na mesma; o telemóvel pode resolver o host.

--------------------------------------------------
## P3 (1)
--------------------------------------------------

### AF-P3-01 · AF3 · `last_message_time` −90 s dentro da janela de 2 min

INSERT `chats.last_message_time = now()-90s` persistiu (~60 s de atraso). `+3 h` foi clamped para `now()`. `chat_messages.created_at` PATCH → imutável (controlo).

--------------------------------------------------
## Controlos que aguentaram (amostra)
--------------------------------------------------

| Ataque | Resultado |
|---|---|
| `order_dispute_opened` sem row | `chat_system_card_dispute_missing` |
| `order_review_submitted` sem review | `chat_system_card_review_missing` |
| `seguro_fleaber_paid` em unpaid | `chat_system_card_order_not_paid` |
| seller → kind buyer-only | `chat_system_card_buyer_only` |
| B2 INSERT na thread B–S | `chat_system_card_not_participant` |
| B2 SELECT mensagens | 200, 0 rows |
| B2 GET storage chat_uploads B | 404/`NoSuchKey` (sem leak) |
| storage `x-upsert=true` mesmo path | 403 RLS |
| upload `order_proofs/{seller}/…` buyer | 403 RLS |
| sign path alheio | 404 `NoSuchKey` |
| DELETE `FLEABER_JSON_V1:` próprio | 403 `chat_system_card_immutable` |
| `FLEABER_JSON_V1:` + FF no JSON | `chat_system_card_invalid_json` |
| Edge `create-payment-intent` amount=1 | 400 Missing payment metadata |
| `vbscript:` / `file:` / `blob:` proof | `chat_system_card_url_denied` |

--------------------------------------------------
## Lentes
--------------------------------------------------

| Lente | Coberta | Resultado |
|---|---|---|
| AF1 Cards vs BD | SIM | P1-02..05, P2-01..02 |
| AF2 Prefixo / encoding | SIM | P1-01 (FF/VT/Ogham/LS/PS); ZWSP não pinta |
| AF3 Cronologia | SIM | P3-01; created_at fechado |
| AF4 URLs / provas | SIM | P2-04; XSS clássico fechado |
| AF5 Inbox / delete | SIM | P2-03; mutate/delete do P1-01 |
| AF6 Storage | SIM | upsert/cross-prefix fechados |
| AF7 Cross-user | SIM | thread/storage fechados; path proof outro uid = P2-04 |
| AF8 Edge vs chat | SIM | Edge recusa; chat dos P1 mente sem mint |

--------------------------------------------------
## Falsos positivos (não contar)
--------------------------------------------------

- `AF5.DEL.JSONV1` pass 1: HTTP 200 `[]` — 0 rows (PostgREST + RLS), card FLEABER intacto. Pass 2 confirmou 403.
- `AF2.KIND.UNICODE-ESCAPE`: `\u005f` é JSON normativo; kind vira `seguro_fleaber_paid` com total correcto. Não é bypass.

--------------------------------------------------
## Notas
--------------------------------------------------

- Sem mint directo. Os P1 são mentira no fio (recibo / recusa / prazo / total de conjunto) com BD financeira a dizer o contrário.
- `service_role` só criou products/orders/offers e leu estado.
- Não se corrigiu SQL nem Flutter.
