## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 3
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 5

AUDITOR: REDTEAM_BLIND_BM_CHAT_POS_BFBK_v1
FROZEN_AT: 2026-09-02T20:10:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BM1, BM2, BM3, BM4, BM5, BM6, BM7, BM8]
VEREDICTO: FAIL_P1

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTBM-20260902T1905-`
Actors: anon · buyer JWT · seller JWT · B2
service_role: só fixture/observação (`setup_paid_order`, SELECT, live fixture)
Pasta: `tool/redteam_blind_bm_20260902T1905/`

--------------------------------------------------
MISSÃO
--------------------------------------------------
Ainda colo prova alheia ou minto rail depois do denylist BFBK (Affirm/Cash App/Pix;
`proof_url` needle só no path; inbox forge alargado) — com variantes **novas**.

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### RTBM-BM1-notes-off-denylist · P1 · BM1/BM2

**Título:** O card «o comprador confirmou o pagamento» aceita notas Clearpay / Shop Pay / Strike / Sezzle / Bancontact / Zelle — rails fora da denylist BFBK.

**Actor:** buyer JWT

**Pré:** order MB WAY `7fe460e8-d13b-42d3-bea2-a690cb8c0373` · chat `dd403563-7dc5-436b-a465-d684986024bd`.

**Repro:**
```
POST /rest/v1/chat_messages
text = FLEABER_JSON_V1:{"kind":"reservation_payment_submitted","order_id":"<oid>","notes":"Clearpay 12,00 €"}
```
O mesmo com `Shop Pay 12,00 €`, `Strike 12,00 €`, `Sezzle 12,00 €`, `Bancontact 12,00 €`, `Zelle 12,00 € received`.

**Esperado:** `chat_system_card_notes_forbidden` (como Affirm / Cash App).

**Obtido (pass1 + pass2):** HTTP 201. Texto persistido, p.ex. msg `1365` Zelle; pass2 Clearpay/Shop Pay/Strike/Sezzle/Bancontact.

A UI (`_buildReservationPaymentSubmittedCard`) pinta `Observações: $notes` no card amarelo oficial.

Com `confirmado` / `aprovado` / `pago` a seguir ao montante, a denylist genérica **recusa** (Clearpay+confirmado → 400). Sem esses verbos, o rail novo passa.

**Encoding (BM2, mesma falha):** `Ѕhop Pay 12,00 €` (U+0405) e `Ｃｌｅａｒｐａｙ 12,00 €` (fullwidth) persistiram. `batata_chat_normalize_lie_text` não mapeia Dze cirílico nem fullwidth; e estes rails nem estão na lista.

**Não é o exacto BFBK** Affirm label / Cash App notes.

**Impacto:** o vendedor vê um card de sistema a afirmar pagamento + rail BNPL/crypto falso. Caminho para confirmar MB WAY / marcar pago. Sem captura Stripe neste fio → **P1**, não P0.

---

### RTBM-BM5-inbox-off-denylist · P1 · BM5

**Título:** `chats.last_message` aceita o mesmo conjunto de rails novos.

**Actor:** buyer JWT

**Repro:** `PATCH chats?id=eq.{chat}` `{"last_message":"Strike 12,00 €"}` (também Clearpay / Shop Pay / Zelle received, **sem** confirmado/aprovado).

**Esperado:** `chat_inbox_preview_forbidden`.

**Obtido:** 200; `last_message` = o texto hostil. Controlo Affirm settled → 403. `Clearpay confirmado 12,00 €` (verbo+montante) também 403 — a falha é o rail **sem** o padrão `confirmado/aprovado/pago`.

**Impacto:** a lista de conversas mostra «Strike 12,00 €» / «Clearpay 12,00 €» como última mensagem.

---

### RTBM-BM4-proof-url-dotdot · P1 · BM4

**Título:** `proof_url` com `../` passa o needle `order_proofs/{buyer}/{order}/` (substring no path cru); o cliente resolve para outro objecto; o vendedor lê a imagem falsa.

**Actor:** buyer JWT (upload + card) · seller JWT (GET)

**Pré:** JPEG em `chat_uploads/{buyer}/{chat}/rtbm_fake.jpg` (22 bytes). Needle BFBK: `split_part` tira `?` e `#`, depois `position(v_needle in v_path)`.

**Repro:**
1. Upload JPEG autenticado em `chat_uploads/{B}/{chat}/rtbm_fake.jpg`.
2. POST card `reservation_payment_submitted` com
   `proof_url=https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/fleaber_private/order_proofs/{B}/{oid}/../../../chat_uploads/{B}/{chat}/rtbm_fake.jpg`

**Esperado:** `chat_system_card_url_denied` (path canónico ≠ `order_proofs/{buyer}/{order}/…`; `..` recusado).

**Obtido:**
| | Valor |
|---|--------|
| Card | 201 · `../` no texto (pass2b) |
| `Uri.parse` (Dart / Flutter) | `…/fleaber_private/chat_uploads/{B}/{chat}/rtbm_fake.jpg` |
| GET object buyer | **200** 22 b |
| GET object **seller** | **200** 22 b |
| GET authenticated seller | **200** 22 b |

A app usa `BatataCachedNetworkImage(imageUrl: proofUrl)` — o mesmo parse.

**Variante (não contada à parte):** prefixo extra `…/fleaber_private/other/{uid}/order_proofs/{buyer}/{oid}/x.jpg` também 201 — o needle é substring, não prefixo canónico.

**Exactos BFBK não regressaram:** needle só na query `?order_proofs=` → 400; fragmento `#order_proofs/…` → 400; signed noutro bucket → 400.

**Impacto:** o vendedor vê no card de prova um ficheiro que **não** está em `order_proofs/{buyer}/{order}/`. É prova alheia ao prefixo da encomenda (chat_uploads do próprio comprador, visível ao vendedor pela policy de counterpart). **P1**.

---

### RTBM-BM1-seguro-label-clearpay · P2 · BM1

**Título:** Card `seguro_fleaber_paid` numa compra Stripe real aceita `label: Clearpay 999,00 €` (e `Shop Pay`).

**Actor:** buyer JWT

**Pré:** `setup_paid_order` `54f71515-a916-4413-8959-4a30ceafe0d9` · `amount_paid_cents=590` · PI `pi_3UBIVxH7FWYUN3jh1gBwnzKH` succeeded.

**Repro:**
```
kind=seguro_fleaber_paid, order_id=<pago>, total="5.90", label="Clearpay 999,00 €"
```

**Esperado:** `chat_system_card_label_mismatch` (Affirm neste sítio → 400).

**Obtido:** 201. Texto: `label":"Clearpay 999,00 €"`. A UI acrescenta ` · $label` a «Paga através do Seguro Fleaber · 5,90 €».

O `total` bate com a captura; o label **não** entra na regex de rails (Clearpay/Shop Pay ausentes) nem em `payment_lie_text` (sem confirmado/pago a seguir ao 999).

**Impacto:** recibo verdadeiro de 5,90 € com rail e montante 999 mentiroso no mesmo card. Não cria dinheiro → **P2**.

---

### RTBM-BM7-meta-extra · P3 · BM7

**Título:** Chave JSON `meta` extra (rail Clearpay) persiste no card.

**Actor:** buyer JWT

**Repro:** `notes=ok` + `"meta":{"rail":"Clearpay","amount":"12.00","status":"paid"}`.

**Obtido:** 201. A UI do card **não** lê `meta` (só `notes` / `proof_url`). Higiene / payload solto → **P3**.

--------------------------------------------------
FALSOS POSITIVOS (retraídos)
--------------------------------------------------
- Texto **plain** `Clearpay confirmado 12,00 €` no chat: INSERT não passa por `payment_lie_text` (só JSON + inbox). Utilizador pode escrever; não é card de sistema. Não contar.
- `Αffirm 12,00 €` plain persistiu — exacto de encoding noutro sítio; **não contar**.
- Clearpay/Shop Pay/Strike **notes** com confirmado/aprovado/pago: 400 (denylist genérica). Não é bypass.
- Inbox `Clearpay confirmado…` / `Shop Pay … aprovado`: 403. Não contar.
- PATCH/INSERT `created_at` e DELETE de card JSON: bloqueados.
- Storage list/GET/upload B2 no prefixo `order_proofs/B1`: vazio / 404 / 403.

--------------------------------------------------
DEFESAS QUE AGUENTARAM (variantes novas + lentes)
--------------------------------------------------
**BM1 cards:** Affirm label no seguro → `label_mismatch`. Cash App notes → `notes_forbidden`. Clearpay+confirmado notes → 400.

**BM2 encoding:** lunate `Ϲlearpay confirmado` recusado (verbo+€). ZWSP `St<ZWSP>rike … confirmado` recusado após strip.

**BM3 cronologia:** INSERT `created_at` 40 dias → gravado `now()`. PATCH `created_at=2020` → valor inalterado. DELETE JSON → `chat_system_card_immutable`. DELETE plain permitido.

**BM4 URLs:** fragmento `#` e query `?order_proofs=` recusados (fecho BFBK). Signed `avatars` recusado. UUID compacto no path recusado. Host/bucket certos exigidos pelo assert.

**BM5 inbox:** Affirm settled → 403. Rails listados + confirmado → 403.

**BM6 storage:** JPEG B1 upload 200. B2 list `[]`, GET 404, upload 403 RLS.

**BM7 cross-user:** B2 INSERT no chat B1–seller → RLS 403.

**BM8 Edge OCR:** `x-device-token` falso → 401 `invalid_token`. RPC `batata_ingest_ocr_reservation_v2` JWT → `{"ok":false,"error":"invalid_token"}`.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Stripe TEST `setup_paid_order` pago 590 cêntimos (seguro label).
2. Order MB WAY + chat para cards de prova.
3. Notes/inbox **sem** confirmado/aprovado/pago (os verbos mascaram o rail novo).
4. `../` ×3 no `proof_url` → `Uri.parse` + GET vendedor 200 no JPEG de chat_uploads.
5. OCR Edge com token inventado.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Exactos BFBK **não contados:** Affirm label · Cash App notes · proof `?order_proofs=` query.
0/3 exactos persistiram nos sítios fechados (query/fragment/Affirm card/Cash App notes).
Variantes novas: rails Clearpay/Shop Pay/Strike/Zelle; `../` no path; `meta` extra.
Não ATROFIA_ABORT.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------
1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (Stripe). Buyer **mente rail** em card/inbox/prova — P1 acima
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora do poço)
16. Stock=1 duas vendas válidas — NÃO (fora do poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 storage/chat recusados). Prova **deslocada** via ../ no mesmo par B–V — P1 BM4
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO
24. RPC SECURITY DEFINER perigoso executável — NÃO (OCR JWT invalid_token)
25. RLS crítico quebrado — NÃO (B2 chat/storage)
26. Edge confia total do cliente — NÃO no OCR token. Card JSON `proof_url`/`notes`/`label` sim nos P1/P2
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — NÃO (P1 abertos; 8/8 lentes exercidas)

--------------------------------------------------
NÃO FEITO / LIMITES
--------------------------------------------------
- Não se induziu o vendedor a PATCH `status=pago` depois do card mentiroso (por isso P1, não P0).
- Produção não tocada. Fase 4 não iniciada. Código de produto **não** corrigido.
- Live de fixture OCR `897f51cc-4da7-4455-81cd-ee6b69258850` encerrada após a ronda.

Evidência: `pass1.json`, `pass2.json`, `pass2b.json`, este ficheiro.
