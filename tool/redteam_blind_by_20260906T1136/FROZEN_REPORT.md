## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 4
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 5

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 4
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

AUDITOR: REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1
FROZEN_AT: 2026-09-06T11:45:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BY1, BY2, BY3, BY4, BY5, BY6, BY7, BY8]
VEREDICTO: FAIL_P1

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTBY-20260906T1136-`
Actors: anon · buyer JWT · seller JWT · B2
service_role: só fixture/observação (`setup_paid_order`, SELECT, live fixture, end live)
Pasta: `tool/redteam_blind_by_20260906T1136/`

```
AUDITOR: REDTEAM_BLIND_BY_CHAT_POS_BRBW_v1
production_touched: false · fase4: false · corrections_applied: false
```

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 4
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora de âmbito chat)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (`chat_system_card_buyer_only` no `seguro_fleaber_paid`)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (fora)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (OCR `invalid_token`)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 list `[]`; GET B2 `NoSuchKey`; B2 INSERT chat RLS 403; anon GET chat 401)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`seguro_fleaber_paid` seller → `chat_system_card_buyer_only`)
23. Reviews forjadas — NÃO (fora)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_ingest_ocr_reservation_v2` → `invalid_token`)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`ingest-ocr-reservation` token falso 401; anon `missing_device_token`)
27. Regressão funcional (happy path partido) — NÃO (`setup_paid_order` 200; proof_url honesto 201; live ended)
28. Saturação atingida — SIM (8/8 lentes; pass2 sem classe nova P0/P1)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

**FAIL_P1.** Depois do fecho BRBW (Payoneer/WU/Interac/BTC/USDT/Paytm/Mercado Pago notes+inbox; strip U+180E/Hangul/U+2063; proof `．．`/`%c0%ae`), o denylist **não cobre rails/frases novas**. O comprador grava um card amarelo oficial «o comprador confirmou o pagamento» com notas Skrill / Neteller / «enviado MB» (sem verbos) / Paysafecard / MoneyGram / GCash / Perfect Money; o mesmo texto entra em `chats.last_message`; e no card `seguro_fleaber_paid` de uma encomenda **já capturada** o `label` aceita o mesmo rail (a UI pinta «Seguro Fleaber · 5,90 € · Skrill 12,00 €»).

Há um segundo P1 de **encoding**: controlos de formato que o `batata_chat_strip_format_controls` **não** remove (U+206A, U+034F CGJ, U+FFA0, U+061C, U+180B) reabrem rails **já fechados** (Clearpay / Payoneer) nas notes e no inbox. U+034F é invisível: «Clea⟨U+034F⟩rpay 12,00 €» mostra-se como Clearpay.

P2: `proof_url` aceita double-encoding `%252e%252e`, overlong 3-byte `%e0%80%ae` e `%c1%9c` (sem ASCII `..`). Storage **não** resolve — GET 400 `InvalidKey` / `FST_ERR_BAD_URL`. Sem loot.

Exactos BS/BM **não contados** e o fecho **segura**: Payoneer / Western Union notes ASCII → `chat_system_card_notes_forbidden`; inbox Payoneer/WU ASCII → `chat_inbox_preview_forbidden`; U+180E Clearpay → 400; `．．` e `%c0%ae` → `chat_system_card_url_denied`. Revolut Business (substring `revolut`) → 400/403. Bidi U+202E e soft hyphen U+00AD no meio de Clearpay/Payoneer → 400/403 (strip BRBW). Signed URL da **própria** outra encomenda → `url_denied`. OCR Edge token falso → 401.

Anti-atrofia: 0 de 3 exactos redescobertos como finding. Classes novas = rails off-denylist (3 superfícies) + format-control bypass + path não canonicalizado. Não é `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS PROVADOS
--------------------------------------------------

### RTBY-BY1-notes-off-denylist · P1 · BY1

**Título:** O card «o comprador confirmou o pagamento» aceita notas Skrill / Neteller / «enviado MB» / Paysafecard / MoneyGram / GCash / Perfect Money — rails e frases fora da denylist BRBW.

**Actor:** buyer JWT

**Pré:** order MB WAY `52db2fa8-47d3-481c-85b5-de3b93380b63` · chat `edb67d60-6e7f-4fee-8b69-44e9b69721a7`.

**Repro:**
```
POST /rest/v1/chat_messages
text = FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"<oid>","notes":"Skrill 12,00 €"}
```
O mesmo com `Neteller 12,00 €`, `enviado MB`, `enviado MB 12,00 €`, `Paysafecard 12,00 €`, `MoneyGram 12,00 €`, `GCash 12,00 €`, `Perfect Money 12,00 €`.

**Esperado:** `chat_system_card_notes_forbidden` (como Payoneer / Western Union).

**Obtido:** HTTP 201. Msgs `1461`–`1468` + pass2 Perfect Money. Seller JWT GET `1461` → texto persistido `notes":"Skrill 12,00 €"`.

A UI (`_buildReservationPaymentSubmittedCard`) pinta `Observações: $notes` no card amarelo oficial.

Controlo ASCII Payoneer / Western Union → 400 `chat_system_card_notes_forbidden`.
«Revolut Business 12,00 €» → 400 (substring `revolut` já na denylist) — não é finding.

**Não é o exacto** Payoneer/WU notes.

**Impacto:** o vendedor vê um card de sistema a afirmar pagamento + rail/e-wallet/remessa falso, ou «enviado MB» sem verbo de confirmação (a denylist exige `mbway` / `mb way` + verbos). Caminho para confirmar MB WAY / marcar pago. Sem captura Stripe neste fio MB WAY → **P1**, não P0.

Uma classe, vários payloads — **conta 1**.

---

### RTBY-BY5-inbox-off-denylist · P1 · BY5

**Título:** `chats.last_message` aceita o mesmo conjunto de rails/frases novas.

**Actor:** buyer JWT

**Repro:** `PATCH chats?id=eq.{chat}` `{"last_message":"Skrill 12,00 €"}` (também Neteller / enviado MB / Paysafecard / MoneyGram / GCash).

**Esperado:** `chat_inbox_preview_forbidden`.

**Obtido:** 200; `last_message` = o texto hostil. Pass2: inbox ainda `GCash 12,00 €`. Controlo `Payoneer 12,00 €` / `Western Union 12,00 €` / `Revolut Business 12,00 €` → 403 `chat_inbox_preview_forbidden`.

**Impacto:** a lista de conversas mostra «Skrill 12,00 €» / «enviado MB» / «GCash 12,00 €» como última mensagem.

---

### RTBY-BY1-seguro-label-new-rail · P1 · BY1

**Título:** Card `seguro_fleaber_paid` (encomenda já capturada) aceita `label` com rail novo e montante mentiroso.

**Actor:** buyer JWT

**Pré:** order Stripe TEST paga `193a6333-89a5-43a1-8df2-b7b49413a2a2` · `amount_paid_cents=590` · chat `bf654459-f8b5-4899-8bec-38c0eaafd820`.

**Repro:**
```
POST chat_messages
kind=seguro_fleaber_paid order_id=<paid> total="5.90" label="Skrill 12,00 €"
```
(e Neteller / enviado MB / Paysafecard / MoneyGram / GCash).

**Esperado:** `chat_system_card_label_mismatch`.

**Obtido:** HTTP 201. Msg `1471` (Skrill). Seller GET: `label":"Skrill 12,00 €"` no card de sistema. A UI (`_buildSeguroFleaberPaidCard`) acrescenta ` · $label` a «Paga através do Seguro Fleaber».

Seller a inserir o mesmo card → 403 `chat_system_card_buyer_only` (não é finding seller-forge).
Label `Revolut Business` / `Payoneer 12,00 €` → 400 `chat_system_card_label_mismatch`.

**Impacto:** num recibo oficial de captura Stripe, o comprador cola um rail/montante falso visível ao vendedor. Sem Δwallet extra → **P1**.

---

### RTBY-BY2-unlisted-format-bypass · P1 · BY2

**Título:** Controlos de formato fora do `batata_chat_strip_format_controls` reabrem Clearpay/Payoneer nas notes e no inbox.

**Actor:** buyer JWT

**Repro (notes, rail fechado Clearpay / Payoneer):**
- `Clea` + U+206A (inhibit symmetric swapping) + `rpay 12,00 €` → msg `1485` HTTP 201
- `Clea` + U+034F (combining grapheme joiner) + `rpay 12,00 €` → msg `1486` HTTP 201
- `Clea` + U+FFA0 (halfwidth hangul filler) + `rpay 12,00 €` → msg `1487` HTTP 201
- `Clea` + U+061C (arabic letter mark) + `rpay 12,00 €` → msg `1488` HTTP 201
- `Clea` + U+180B (mongolian FVS1) + `rpay 12,00 €` → msg `1489` HTTP 201
- `Payo` + U+206A + `neer 12,00 €` → msg `1490` HTTP 201

**Repro (inbox):** `PATCH last_message` com U+206A ou U+034F em Clearpay → persistiu.

Seller GET `1485` / `1486` → texto hostil visível ao vendedor. U+034F é invisível: lê-se «Clearpay 12,00 €».

**Esperado:** após strip/normalize, o mesmo `chat_system_card_notes_forbidden` / `chat_inbox_preview_forbidden` do ASCII.

**Obtido:** 201 / inbox 200.

Controlo (fecho BRBW **segura**, não contar):
- U+202E bidi override no meio de Clearpay/Payoneer → 400 / inbox 403
- U+00AD soft hyphen no meio de Clearpay/Payoneer → 400 / inbox 403
- U+180E Clearpay (exacto BS) → 400 / inbox 403

**Não é o exacto** U+180E Clearpay. É encoding **novo** sobre o fecho.

Soft hyphen no meio de Skrill persistiu — classe BY1 (Skrill já passa sem encoding); não duplicar aqui.

**Impacto:** denylist BRBW contornável sem alterar o aspecto do rail fechado. Caminho explorável no card/inbox → **P1**.

Uma classe, vários codepoints — **conta 1**.

---

### RTBY-BY4-noncanonical-proof-url · P2 · BY4

**Título:** `proof_url` aceita double-encoding `%252e%252e`, overlong 3-byte `%e0%80%ae` e `%c1%9c`; storage não resolve.

**Actor:** buyer JWT

**Pré:** PNG em `order_proofs/{B1}/{oidB}/rtby_b.png` (upload `image/png` 200). Card da encomenda A `52db2fa8-…`.

**Repro:**
```
proof_url = …/order_proofs/{B1}/{oidA}/%252e%252e/%252e%252e/order_proofs/{B1}/{oidB}/rtby_b.png
proof_url = …/order_proofs/{B1}/{oidA}/%e0%80%ae%e0%80%ae/…/{oidB}/rtby_b.png
proof_url = …/order_proofs/{B1}/{oidA}/%c1%9c%c1%9c/%c1%9c%c1%9c/…/{oidB}/rtby_b.png
```

**Esperado:** `chat_system_card_url_denied` (como ASCII `../`, `．．`, `%c0%ae`).

**Obtido:**
- INSERT `%252e%252e` → 201 msg `1497`
- INSERT `%e0%80%ae` → 201 msg `1498`
- INSERT `%c1%9c` sem ASCII `..` → 201 msg `1505`
- GET authenticated `%252e%252e` → 400 `InvalidKey` (storage descodifica uma vez para `%2e%2e`; não é traversal real)
- GET `%e0%80%ae` / `%c1%9c` → 400 `FST_ERR_BAD_URL`
- GET honesto da prova B (mesmo buyer) → 200

Controlo `．．` / `%c0%ae` → 400 `chat_system_card_url_denied`.
`%c1%9c../` **com** ASCII `..` → 400 (o guard `like '%..%'` apanha os pontos) — o bypass é o `%c1%9c` **sem** dots.

Signed URL da **própria** outra encomenda e path unsigned/authenticated dessa pasta → `url_denied`.

**Porquê P2 e não P1:** o card persiste um URL hostil (thumbnail que falha), mas **não há loot** da outra encomenda.

Uma classe, vários encodings — **conta 1**.

---

--------------------------------------------------
## BLOQUEADOS / FECHO BRBW AINDA SEGURA
--------------------------------------------------

| Probe | Resultado |
|---|---|
| Notes Payoneer / Western Union ASCII | 400 `chat_system_card_notes_forbidden` |
| Notes Revolut Business | 400 `chat_system_card_notes_forbidden` |
| Inbox Payoneer / WU / Revolut Business ASCII | 403 `chat_inbox_preview_forbidden` |
| U+180E Clearpay notes+inbox | 400 / 403 |
| U+202E bidi override Clearpay/Payoneer | 400 / 403 |
| U+00AD soft hyphen Clearpay/Payoneer | 400 / 403 |
| `proof_url` `．．` / `%c0%ae` | 400 `chat_system_card_url_denied` |
| Signed URL da **própria** outra encomenda | 400 `chat_system_card_url_denied` |
| Path unsigned / `object/authenticated` outra encomenda | 400 `url_denied` |
| INSERT `created_at` 2020 | forçado a `now()` (`2026-09-06T10:41:53Z`) |
| PATCH `created_at` 2020 | HTTP 200 mas valor imutável |
| DELETE card JSON | 403 `chat_system_card_immutable` |
| B2 INSERT/GET chat B1 | 403 RLS / `[]` |
| Anon GET `chat_messages` | 401 `batata_chat_is_participant` |
| B2 list `order_proofs` B1 | `200 []` |
| B2 GET prova B1 | `NoSuchKey` |
| B2 upload PNG prefixo B1 | 403 `AccessDenied` |
| Seller `seguro_fleaber_paid` | 403 `chat_system_card_buyer_only` |
| OCR Edge token falso / anon / RPC JWT | 401 `invalid_token` / `missing_device_token` / `{ok:false,error:invalid_token}` |

Live fixture `9e5dccf3-28fd-4807-9091-decc31ebecb5` → `status=ended`, `is_active=false`.

--------------------------------------------------
## FIXTURES
--------------------------------------------------

- SKU MB WAY: `f8ef4848-cf83-4ff5-833b-e5746d6cedde`
- Chat MB WAY: `edb67d60-6e7f-4fee-8b69-44e9b69721a7`
- Order MB WAY: `52db2fa8-47d3-481c-85b5-de3b93380b63`
- Paid Stripe 1: `193a6333-89a5-43a1-8df2-b7b49413a2a2` (590¢) chat `bf654459-f8b5-4899-8bec-38c0eaafd820` PI `pi_3UCdW0H7FWYUN3jh1mH1S9Sg`
- Paid Stripe 2 (outra encomenda própria): `c548838a-e478-4d67-9774-7e534926ceb8`
- B2: `39c7e4e9-41ab-4d6d-82ad-35dd3bdacc41`
- Buyer: `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96`

Evidência: `pass1.json`, `pass2.json`.
