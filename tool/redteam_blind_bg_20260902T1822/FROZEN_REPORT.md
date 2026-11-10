## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 4

```
AUDITOR: REDTEAM_BLIND_BG_CHAT_POS_ATBE_v1
FROZEN_AT: 2026-09-02T18:30:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BG1, BG2, BG3, BG4, BG5, BG6, BG7, BG8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT B1/S1/B2/S2 + anon. `service_role` só fixture / observação / cleanup. Prefixo `RTBG-20260902T1822-`. Código **não** corrigido. Produção intocada. Fase 4 não iniciada. Relatórios AU/BA/AO/AI **não** lidos.

Sonda: `dart run scripts/probes/redteam_blind_bg_20260902T1822.dart`  
Artefactos: `findings.json` · `matrix.json` · `notes.json` · `created.json` · este ficheiro.

Anti-atrofia: 0/4 achados = exactos Klarna label · iDEAL notes · `proof_url` order alheio exact path (os três **bloqueados** nesta ronda). Variantes novas: Affirm / Cash App Pay / Pix 💸 / Greek Rho `Ρix` · needle `order_proofs/{buyer}/{order}/` na query string · chave JSON `meta` extra.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 aberto encontrado — NÃO
2. Quantos P0: 0
3. P1 aberto encontrado — SIM
4. Quantos P1: 1
5. Buyer manipula preço autoritativo — NÃO (fora do poço chat; `create-payment-intent` Affirm → 400 `Missing payment metadata.`)
6. Buyer manipula qty autoritativa — NÃO (não exercitado neste poço)
7. Seller falsifica pagamento plataforma — NÃO (seller `seguro_fleaber_paid` → 403 `chat_system_card_buyer_only`)
8. JWT cria saldo/fundos — NÃO
9. Refund excede captura — NÃO (fora de âmbito)
10. Release+refund cria dinheiro líquido — NÃO
11. Payout duplica Transfer — NÃO
12. Stock=1 duas vendas válidas — NÃO
13. Stock=1 duas capturas líquidas permanentes — NÃO
14. Bypass capacidade/reserva — NÃO (`ingest-ocr` 401)
15. Cross-user financeiro — NÃO
16. Cross-user dados sensíveis — NÃO (list `order_proofs/` B2 → `[]`; GET authenticated B1 404/400; path alheio exacto 400)
17. Buyer assume seller/admin — NÃO
18. Seller assume buyer/admin — NÃO
19. Reviews forjadas — NÃO
20. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO
21. RLS crítico quebrado — NÃO (B2 no chat B1 → 403 RLS; anon 401)
22. Edge confia autoridade do cliente no total — NÃO (`ingest-ocr` token inventado → 401 `invalid_token`)
23. Conclusão crítica NÃO COMPROVADA — NÃO (P1 inbox reproduzido com estado final na row `chats`)
24. Regressão funcional (código alterado por ti) — NÃO
25. Último passe nova classe P0/P1 — SIM (inbox Affirm/Cash App/Pix-emoji/Rho; Klarna exacto continua bloqueado)
26. Saturação — SIM nas 8 lentes; P1 ainda aberto
27. Produção tocada — NÃO
28. Fase 4 iniciada — NÃO

Poços exercitados: cards=SIM · encoding=SIM · cronologia=SIM · URLs=SIM · inbox/delete=SIM · storage=SIM · cross-user=SIM · Edge OCR/checkout=SIM  
ATROFIA (só redescobriu exactos Klarna/iDEAL/path alheio): NÃO

VEREDICTO: FAIL_P1

--------------------------------------------------
## ACHADOS (abertos — consolidados)
--------------------------------------------------

### BG-20260902T1822-P1-01 · P1 · BG5 — Inbox `last_message` aceita rails novos (Affirm / Cash App / Pix emoji / Greek Rho)

**Actor:** buyer JWT (participante)  
**Pré:** chat B1–S1 `aec764a5-6a44-4262-a9bd-b8baf79f5943`; denylist ATBE bloqueia Klarna exacto.  
**Repro:** `PATCH /rest/v1/chats?id=eq.<chat>` body `last_message`.  
**Obtido:**

| payload | HTTP | `chats.last_message` |
|---------|------|----------------------|
| `Affirm settled 12,00 €` | 200 | persistiu |
| `Cash App Pay 12,00 €` | 200 | persistiu |
| `Pix 💸` | 200 | persistiu |
| `Ρix 12,00 €` (U+03A1) | 200 | persistiu |
| `Klarna confirmado 12,00 €` (exacto BA/AU) | 403 `chat_inbox_preview_forbidden` | inalterado |

**Impacto:** a lista de conversas mostra um preview de pagamento que **não** corresponde a mensagem/order. Mentira de pagamento na inbox. Não mexe em `orders.status` nem em saldo — caminho explorável de engenharia social na superfície que o fecho ATBE pretendia tapar. **P1** (não P0: sem dinheiro).  
**Porque é variante nova:** não é Klarna label / iDEAL notes; são rails e encoding fora da denylist alargada.

### BG-20260902T1822-P2-01 · P2 · BG1/BG2 — Cards oficiais aceitam Affirm / Cash App / Pix 💸 / `Ρix` (label + notes)

**Actor:** buyer JWT  
**Pré:** order paga fixture `e6eb74b3-eeaa-408a-b844-5c43b3980f75` (`amount_paid_cents=1200`) e order MB WAY `d7be622e-d36e-4ec5-a6fb-e68ac1c8c722`.  
**Repro:** `POST chat_messages` `FLEABER_JSON_V1` kinds `seguro_fleaber_paid` / `reservation_payment_submitted`.  
**Obtido (201):**

- `seguro_fleaber_paid` `label=Affirm` · `Cash App Pay` · `Affirm 999,00 €` (msg 1328–1330)
- `label=Pix 💸` / `💸 Pix` → **400** `chat_system_card_label_mismatch` (HOLD parcial no token `pix` do label)
- notes `Affirm settled 12,00 €` · `Cash App Pay 12,00 €` · `Pix 💸` · `Ρix settled 12,00 €` (msg 1333–1335, 1346)
- notes exacto `pago via Klarna 12 €` → **400** `chat_system_card_notes_forbidden` (não contar)

Flutter pinta label no card «Compra paga através do Seguro Fleaber · 12,00 € · Affirm» e notes no card amarelo «Observações: …».  
**Impacto:** mentira de **rail/montante extra** em card de sistema. A encomenda Seguro está mesmo paga (fixture); MB WAY continua a exigir confirmação do vendedor. Sem captura extra → **P2**.  
**Plain chat** (`Cash App Pay 12,00 €`, homoglyphs, etc.) também 201 — **não contado**: o INSERT de texto livre **não** passa por `batata_chat_payment_lie_text` (só cards JSON + inbox). Utilizadores falam de pagamentos; não é o poço de cards/inbox.

### BG-20260902T1822-P2-02 · P2 · BG4 — `proof_url` amarra por substring: needle na query string

**Actor:** buyer JWT  
**Pré:** ATBE exige `order_proofs/{buyer}/{order_id}/` dentro da URL + prefixo `object/fleaber_private`.  
**Repro:**  
`proof_url=https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/chat_uploads/{buyer}/x.jpg?x=order_proofs/{buyer}/{order}/`  
**Obtido:** HTTP **201**, msg 1353.  
**Controlos HOLD (não contar):**

- path exacto de **outra** order B2 → 400 `chat_system_card_url_denied`
- `/object/authenticated/avatars?q=needle` → 400
- `/object/public/…` → 400
- host `evil.example` → 400
- UUID compacto no path → 400

**Impacto:** o bind ATBE é `position(needle in v_url)`; a query satisfaz o needle sem o objecto estar em `order_proofs/{buyer}/{order}/`. O card aponta para `chat_uploads/…` (ficheiro do próprio, não prova da encomenda). Não é prova **alheia**; é prova **no sítio errado**. Flutter `_openProofImageDialog(proofUrl)`. **P2**.  
`/object/sign/fleaber_private/order_proofs/…?token=expired` também 201 — formato **oficial** `createSignedUrl` (`lib/utils/fleaber_private_storage.dart`). Não é finding (HOLD / token morto no próprio path = P3 residual, não aberto).

### BG-20260902T1822-P3-01 · P3 · BG1 — JSON card aceita chave `meta` extra

**Actor:** buyer JWT  
**Repro:** `reservation_payment_submitted` + `"meta":{"rail":"Affirm","verified":true,"amount":999}`  
**Obtido:** 201 msg 1337. Flutter não lê `meta`. Higiene / parser futuro. **P3**.

--------------------------------------------------
## LENTES (8/8)
--------------------------------------------------

### BG1 cards
- Label Affirm / Cash App / Affirm 999€ → **P2-01**. Pix no label → bloqueado.
- Notes Affirm / Cash App / Pix 💸 → **P2-01**. Klarna exacto → bloqueado.
- `meta` extra → **P3-01**.
- PATCH text de card JSON → 403 `chat_system_card_immutable`.

### BG2 encoding
- Greek Alpha `Αffirm`, Rho `Ρix`, fullwidth, ZWJ, Hangul filler, Cash App, Pix 💸/💵 em **plain** → 201 (texto livre; não aberto).
- Notes `Ρix settled 12,00 €` no card → **P2-01**.
- Normalize ATBE só cirílico `еаорсхуі` + NBSP; Rho grego / fullwidth / 💸 não mapeados.

### BG3 cronologia
- INSERT `created_at=2020` → selado `now()` 2026-09-02T17:28:21Z.
- PATCH `created_at=2019` → selado.
- DELETE card JSON real → 403 `chat_system_card_immutable`.
- INSERT `\u200bFLEABER_JSON_V1:…` → 201 como plain (assert não vê prefixo); DELETE 200. Flutter `startsWith(FLEABER_JSON_V1)` **não** pinta card. Residual, não aberto (coberto por texto livre).

### BG4 URLs
- Needle na query → **P2-02**.
- authenticated bucket errado / public / host / compact / order alheia exacta → 400.
- Upload prova `octet-stream` → 415 `invalid_mime_type` (TTL signed 1s não chegou a objecto).

### BG5 inbox/delete
- **P1-01**. Klarna inbox exacto 403.
- Cleanup devolveu `last_message` para `RTBG-20260902T1822- done`.

### BG6 storage
- `POST /storage/v1/object/list/fleaber_private` prefix `order_proofs/` · `order_proofs/{B1}/` · `…/{order}/` como B2 → HTTP 200 **`[]`**. HOLD.
- GET authenticated path B1 como B2 → 400/404 (ficheiro nem chegou a existir por 415).
- Upload B2 no path B1 → 415 mime (não 403): **NÃO COMPROVADO** write cross-user; list vazio é a prova de listagem.

### BG7 cross-user
- B2 INSERT no chat B1–S1 → 403 RLS.
- B2 card da order B1 → 400 `chat_system_card_order_chat_mismatch`.
- anon INSERT → 401 `permission denied for function batata_chat_is_participant`.
- seller `seguro_fleaber_paid` → 403 `chat_system_card_buyer_only`.

### BG8 Edge OCR/checkout
- `ingest-ocr-reservation` buyer sem token → 401 `missing_device_token`.
- token inventado + linha Affirm → 401 `invalid_token`.
- anon → 401 `missing_device_token`.
- `create-payment-intent` `payment_method=Affirm` em order MB WAY → 400 `Missing payment metadata.` (fail-closed, não rail mentiroso).

--------------------------------------------------
## NÃO CONTADO (anti-atrofia / HOLD)
--------------------------------------------------

- Klarna label / notes / inbox exactos — bloqueados.
- `proof_url` path exacto de outra order — 400.
- Plain «paguei X €» — sem guard de lie_text no INSERT (desenho).
- `/object/sign/fleaber_private/order_proofs/{próprio}/…` — formato Flutter oficial.
- `/object/fleaber_private/order_proofs/{próprio}/{order}/legit.jpg` — path contratado ATBE.

--------------------------------------------------
## FIXTURES
--------------------------------------------------

- product `f01fb586-354b-4430-a88d-fe492978570e`
- chat `aec764a5-6a44-4262-a9bd-b8baf79f5943`
- order MB WAY `d7be622e-d36e-4ec5-a6fb-e68ac1c8c722`
- order pago fixture `e6eb74b3-eeaa-408a-b844-5c43b3980f75`
- B2 `da283dca-8d67-4fef-843c-cbad63314e2f` · S2 `e1749ce7-ecc4-4117-93b9-26fb3217f688`
- Orders/produtos de laboratório marcados `cancelado` / `is_sold` no cleanup.
