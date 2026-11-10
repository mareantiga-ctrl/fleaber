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

AUDITOR: REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T10:56:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BS1, BS2, BS3, BS4, BS5, BS6, BS7, BS8]
VEREDICTO: FAIL_P1

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTBS-20260906T1046-`
Actors: anon · buyer JWT · seller JWT · B2
service_role: só fixture/observação (`setup_paid_order`, SELECT, live fixture, end live)
Pasta: `tool/redteam_blind_bs_20260906T1046/`

```
AUDITOR: REDTEAM_BLIND_BS_CHAT_POS_BLBQ_v1
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
20. Cross-user dados sensíveis — NÃO (B2 list `[]`; GET B2 `NoSuchKey`; B2 INSERT chat 403 RLS; anon GET chat 401)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO (`seguro_fleaber_paid` seller → `chat_system_card_buyer_only`)
23. Reviews forjadas — NÃO (fora)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_ingest_ocr_reservation_v2` → `invalid_token`)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (`ingest-ocr-reservation` token falso 401; anon `missing_device_token`)
27. Regressão funcional (happy path partido) — NÃO (`setup_paid_order` 200; proof_url honesto 201; live ended)
28. Saturação atingida — SIM (8/8 lentes; pass2/2b sem classe nova P0/P1)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

**FAIL_P1.** Depois do fecho BLBQ (Clearpay/Shop Pay/Strike/Sezzle/Bancontact/Zelle notes+inbox; `proof_url` canónico sem `../`; card `meta` extra; fullwidth/cirílico no normalize), o denylist **não cobre rails novos**. O comprador grava um card amarelo oficial «o comprador confirmou o pagamento» com notas Payoneer / Western Union / Interac / BTC / USDT / Paytm / Mercado Pago; o mesmo texto entra em `chats.last_message`; e no card `seguro_fleaber_paid` de uma encomenda **já capturada** o `label` aceita o mesmo rail (a UI pinta «Seguro Fleaber · 5,90 € · Payoneer 12,00 €»).

Há um segundo P1 de **encoding**: controlos de formato que o `batata_chat_strip_format_controls` **não** remove (U+180E, Hangul filler U+3164, U+2063) reabrem rails **já fechados** (Clearpay / Strike) nas notes e no inbox. U+2063 é invisível: «Stri⟨U+2063⟩ke 12,00 €» mostra-se como Strike.

P2: `proof_url` aceita travessia com pontos fullwidth `．．` e `%c0%ae` (o guard só procura ASCII `..` / `%2e%2e`). Storage **não** resolve — GET 400 `InvalidKey` / `FST_ERR_BAD_URL`. Sem loot.

Exactos BM/BG **não contados** e o fecho **segura**: Clearpay/Strike notes ASCII → `chat_system_card_notes_forbidden`; inbox Clearpay ASCII → `chat_inbox_preview_forbidden`; `proof_url` `../` → `chat_system_card_url_denied`; `meta` extra → `chat_system_card_payload_forbidden`. Signed URL da **própria** outra encomenda e `object/authenticated` bucket errado → `url_denied`. Overlong UTF-8 no JSON → `PGRST102`. PATCH `created_at` imutável. OCR Edge token falso → 401.

Anti-atrofia: 0 de 4 exactos redescobertos como finding. Classes novas = rails off-denylist (3 superfícies) + format-control bypass + path não canonicalizado. Não é `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS PROVADOS
--------------------------------------------------

### RTBS-BS1-notes-off-denylist · P1 · BS1

**Título:** O card «o comprador confirmou o pagamento» aceita notas Payoneer / Western Union / Interac / BTC / USDT / Paytm / Mercado Pago — rails fora da denylist BLBQ.

**Actor:** buyer JWT

**Pré:** order MB WAY `463c3d0b-e1bf-4dbd-8137-8ee4fddef5bd` · chat `3f0069dd-14cd-470c-9d34-50e3b17d75f7`.

**Repro:**
```
POST /rest/v1/chat_messages
text = FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"<oid>","notes":"Payoneer 12,00 €"}
```
O mesmo com `Western Union 12,00 €`, `Interac 12,00 €`, `BTC 12,00 €`, `USDT 12,00 €`, `Paytm 12,00 €`, `Mercado Pago 12,00 €`.

**Esperado:** `chat_system_card_notes_forbidden` (como Clearpay / Strike).

**Obtido:** HTTP 201. Msgs `1417`–`1423`. Seller JWT GET `1417` → texto persistido `notes":"Payoneer 12,00 €"`.

A UI (`_buildReservationPaymentSubmittedCard`) pinta `Observações: $notes` no card amarelo oficial.

Controlo ASCII Clearpay / Strike → 400 `chat_system_card_notes_forbidden`.

**Não é o exacto** Clearpay/Strike notes.

**Impacto:** o vendedor vê um card de sistema a afirmar pagamento + rail BNPL/crypto/remessa falso. Caminho para confirmar MB WAY / marcar pago. Sem captura Stripe neste fio MB WAY → **P1**, não P0.

---

### RTBS-BS5-inbox-off-denylist · P1 · BS5

**Título:** `chats.last_message` aceita o mesmo conjunto de rails novos.

**Actor:** buyer JWT

**Repro:** `PATCH chats?id=eq.{chat}` `{"last_message":"Payoneer 12,00 €"}` (também Western Union / Interac / BTC / USDT / Paytm / Mercado Pago / `Payoneer` sem montante).

**Esperado:** `chat_inbox_preview_forbidden`.

**Obtido:** 200; `last_message` = o texto hostil. Pass2: inbox ainda `Payoneer`. Controlo `Clearpay 12,00 €` → 403 `chat_inbox_preview_forbidden`.

**Impacto:** a lista de conversas mostra «Payoneer 12,00 €» / «USDT 12,00 €» como última mensagem.

---

### RTBS-BS1-seguro-label-new-rail · P1 · BS1

**Título:** Card `seguro_fleaber_paid` (encomenda já capturada) aceita `label` com rail novo e montante mentiroso.

**Actor:** buyer JWT

**Pré:** order Stripe TEST paga `c852914d-66d8-4028-8225-b9ae4bcae03c` · `amount_paid_cents=590` · chat `fea2615d-3475-46c9-a42d-c4429b23ec11`.

**Repro:**
```
POST chat_messages
kind=seguro_fleaber_paid order_id=<paid> total="5.90" label="Payoneer 12,00 €"
```
(e os outros 6 rails; também `label":"Payoneer"` sem montante).

**Esperado:** `chat_system_card_label_mismatch`.

**Obtido:** HTTP 201. Msgs `1430`–`1437`. Seller GET: `label":"Payoneer 12,00 €"` no card de sistema. A UI (`_buildSeguroFleaberPaidCard`) acrescenta ` · $label` a «Paga através do Seguro Fleaber».

Seller a inserir o mesmo card → 403 `chat_system_card_buyer_only` (não é finding seller-forge).

**Impacto:** num recibo oficial de captura Stripe, o comprador cola um rail/montante falso visível ao vendedor. Sem Δwallet extra → **P1**.

---

### RTBS-BS2-invisible-format-bypass · P1 · BS2

**Título:** Controlos de formato fora do `batata_chat_strip_format_controls` reabrem Clearpay/Strike nas notes e no inbox.

**Actor:** buyer JWT

**Repro (notes):**
- `C` + U+180E (Mongolian vowel separator) + `learpay 12,00 €` → msg `1427` HTTP 201
- `C` + U+3164 (Hangul filler) + `learpay 12,00 €` → msg `1428` HTTP 201
- `Stri` + U+2063 (invisible separator) + `ke 12,00 €` → msg `1429` HTTP 201

**Repro (inbox):** `PATCH last_message` com Hangul filler em Clearpay → persistiu.

U+200B em Payoneer também persistiu (msg `1426`) — o ZWSP **é** stripped, mas Payoneer já passa sem encoding (classe BS1, não contar em duplicado aqui).

**Esperado:** após strip/normalize, o mesmo `chat_system_card_notes_forbidden` / `chat_inbox_preview_forbidden` do ASCII.

**Obtido:** 201 / inbox 200. U+2063 é invisível: o vendedor lê «Strike 12,00 €» num card que o ASCII Strike recusa.

**Não é o exacto** Clearpay/Strike notes ASCII (esses 400/403). É encoding **novo** sobre o fecho.

**Impacto:** denylist BLBQ contornável sem alterar o aspecto do rail. Caminho explorável no card/inbox → **P1**.

---

### RTBS-BS4-noncanonical-proof-url · P2 · BS4

**Título:** `proof_url` aceita travessia com pontos fullwidth `．．` e `%c0%ae`; storage não resolve.

**Actor:** buyer JWT

**Pré:** PNG em `order_proofs/{B1}/{oidB}/rtbs_b.png` (upload `image/png` 200). Card da encomenda A `463c3d0b-…`.

**Repro:**
```
proof_url = …/order_proofs/{B1}/{oidA}/．．/．．/order_proofs/{B1}/{oidB}/rtbs_b.png
proof_url = …/order_proofs/{B1}/{oidA}/%c0%ae%c0%ae/%c0%ae%c0%ae/order_proofs/{B1}/{oidB}/rtbs_b.png
```

**Esperado:** `chat_system_card_url_denied` (como ASCII `../` e `%2e%2e`).

**Obtido:**
- INSERT `．．` → 201 msg `1447`
- INSERT `%c0%ae` → 201 msg `1460`
- GET authenticated/abs `．．` → 400 `InvalidKey` (não é path traversal real)
- GET `%c0%ae` → 400 `FST_ERR_BAD_URL`
- GET honesto da prova B (mesmo buyer) → 200 PNG

Controlo ASCII `../` → 400 `chat_system_card_url_denied`.

**Porquê P2 e não P1:** o card persiste um URL hostil (thumbnail que falha), mas **não há loot** da outra encomenda. Signed URL da própria outra encomenda e path unsigned/authenticated dessa pasta → `url_denied`.

---

--------------------------------------------------
## BLOQUEADOS / FECHO BLBQ AINDA SEGURA
--------------------------------------------------

| Probe | Resultado |
|---|---|
| Notes Clearpay / Strike ASCII | 400 `chat_system_card_notes_forbidden` |
| Inbox Clearpay ASCII | 403 `chat_inbox_preview_forbidden` |
| `meta` extra no card | 400 `chat_system_card_payload_forbidden` |
| `proof_url` `../` ASCII | 400 `chat_system_card_url_denied` |
| Signed URL da **própria** outra encomenda | 400 `chat_system_card_url_denied` (anon GET do token, fora do card, 200 PNG — desenho signed URL) |
| `object/authenticated` outra encomenda / bucket `avatars` / `chat_media` | 400 `url_denied` / `path_denied` |
| Slash unicode `／` | 400 `url_denied` |
| Overlong UTF-8 no JSON body | 400 `PGRST102` Empty or invalid json |
| INSERT `created_at` 2020 | forçado a `now()` (`2026-09-06T09:52:51Z`) |
| PATCH `created_at` 2020 | HTTP 200 mas valor imutável |
| DELETE card JSON | 403 `chat_system_card_immutable` |
| B2 INSERT/GET chat B1 | 403 RLS / `[]` |
| Anon GET `chat_messages` | 401 `batata_chat_is_participant` |
| B2 list/GET/upload `order_proofs` B1 | `[]` / `NoSuchKey` / 403 RLS |
| Seller `seguro_fleaber_paid` | 403 `chat_system_card_buyer_only` |
| OCR Edge token falso / anon / RPC JWT | 401 `invalid_token` / `missing_device_token` / `{ok:false,error:invalid_token}` |

Live fixture `aebf7c4a-7830-4a5b-b472-d24a713435f9` → `status=ended`, `is_active=false`.

--------------------------------------------------
## FIXTURES
--------------------------------------------------

- SKU MB WAY: `7be94cea-412e-4ee6-8c54-751f2d27e235`
- Chat MB WAY: `3f0069dd-14cd-470c-9d34-50e3b17d75f7`
- Order MB WAY: `463c3d0b-e1bf-4dbd-8137-8ee4fddef5bd`
- Paid Stripe 1: `c852914d-66d8-4028-8225-b9ae4bcae03c` (590¢) chat `fea2615d-3475-46c9-a42d-c4429b23ec11` PI `pi_3UCckdH7FWYUN3jh0bE15Gvv`
- Paid Stripe 2 (outra encomenda própria): `dd7b0688-bbce-4423-ac3c-edf852130079`
- B2: `7defa406-f688-4310-ae64-076a3b662913`
- Buyer: `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96`

Evidência: `pass1.json`, `pass2.json`, `pass2b.json`.
