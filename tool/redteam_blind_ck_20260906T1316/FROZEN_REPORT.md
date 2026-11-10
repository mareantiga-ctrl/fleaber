# FROZEN · REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1
Prefixo `RTCK-20260906T1316` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 2
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 3
1. P0? NÃO  2. Quantos P0: 0
3. P1? SIM  4. Quantos P1: 2
5. P2? SIM  6. Quantos P2: 1
7. P3? NÃO  8. Quantos P3: 0
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_CK_CHAT_POS_CDCI_v1
production_touched: false · fase4: false · corrections_applied: false
lentes_cobertas: [CK1, CK2, CK3, CK4, CK5, CK6, CK7, CK8]
pocos_tentados: [CK-A, CK-B, CK-C, CK-D]
probes_na_tabela: 55 (≥32)
VEREDICTO: FAIL_P1
```

Anti-atrofia: **OK**. Findings **não** são Skrill/WeChat/`%255c`/`‥`/`%c1%9c`/`%00` exactos CDCI. Controlos residual: Skrill card `notes_forbidden`; WeChat card `notes_forbidden`; WeChat inbox `inbox_preview_forbidden`. 3 linhas de controlo / 55 probes ≪ 50%.

Composição CK-D **tentada**: card PaysafeCash → `500 54000`; `PATCH orders.status=pago` → `403 order_buyer_cannot_mark_pago`. Status `reserva_pendente` inalterado. Wallet seller `54.33 → 54.33`. Mentira de rail = prova social (seguro/inbox), não liquidação Stripe.

--------------------------------------------------
## Missão
Ainda se consegue mentir rail / forjar inbox `last_message` **fora** do denylist CDCI exacto? **Sim (P1)** — `seguro_fleaber_paid` (PaysafeCash, PicPay) e PATCH inbox (7 rails novos). Colar prova com path CK-B: **não observável** nesta corrida (P2: trigger 500 NUL antes do check de URL). Storage alheio, cronologia, inject cross-user, OCR sem token, FSM pago — **não**.

--------------------------------------------------
## P1-1 — seguro_fleaber_paid rails fora CDCI

**O que isto é:** o comprador cola no chat um cartão «Seguro Fleaber pago» com um rail que a lista CDCI não conhece.

**Quem / onde:** buyer JWT · `chat_messages` na thread da encomenda Stripe `e3740b45-1202-44e5-a1cf-90e08e96e74c` (já `pago`).

**O que fizemos:** POST `kind=seguro_fleaber_paid` com `label` PaysafeCash / PicPay / Apple Cash / Samsung Pay.

**Esperado vs resultado**
- Apple Cash / Samsung Pay transfer → `400 label_mismatch` (HOLD; `apple` / `transfer` no regex)
- PaysafeCash 12,00 € → **201 id=1610** (texto persistido)
- PicPay 12,00 € → **201 id=1611** (`pix` não casa `picpay`)
- Base de dados: `orders.status=pago` já vinha do Stripe; **sem Δ wallet**
- Card `reservation_payment_submitted` com as mesmas notes → **não persistiu** (500, ver P2-1)

**Conclusão:** P1 — prova social de pagamento/seguro no chat com rail fora da lista. Não liberta stock.
**Prova:** HTTP 201 ids 1610/1611 · `probes.json`.

--------------------------------------------------
## P1-2 — inbox last_message rails novos

**O que isto é:** o participante escreve o preview da caixa de entrada a dizer que pagou por um rail que o filtro CDCI não lista.

**Quem / onde:** buyer JWT · PATCH `chats` `51b15008-7f9a-4bee-9e7b-6779d75aaba8`.

**Esperado vs resultado**
- WeChat Pay 12,00 € (residual) → `403 inbox_preview_forbidden` (HOLD)
- Persistidos (200, `last_message` exacto na BD): PaysafeCash 12,00 € · tap to cash / NFC prova · Samsung Pay transfer · Vanilla gift card · bonifico istantaneo 12,00 € · Überweisung 12,00 € · rev0lut.me 12 €
- B2 PATCH no mesmo chat → 200 `[]` / last_message inalterado (cross-user HOLD, CK7)

**Conclusão:** P1 — 1 classe (inbox preview). 7 strings, não 7 findings.
**Prova:** PATCH 200 + SELECT `chats.last_message`.

--------------------------------------------------
## P2-1 — canonicalizer CDCI 54000 NUL

**O que isto é:** o guarda de URL de prova (fecho CDCI) inclui `chr(0)` na classe do `regexp_replace`. O Postgres recusa o padrão (`null character not permitted`). Qualquer `reservation_payment_submitted` que **passe** o denylist de notes rebenta **antes** de gravar o card e **antes** de avaliar `proof_url`.

**Esperado vs resultado**
- Notes na lista CDCI (Pix, MB WAY, SEPA, Revolut, Apple, Google, Wise, Skrill, WeChat, …) → `400 notes_forbidden` (nunca chega ao canonicalizer)
- Notes **fora** da lista (PaysafeCash, PicPay, tap to cash, money order, Vanilla, bonifico, Überweisung, rev0lut, CK-B paths com notes `comprovativo envio`) → **500 54000**; 0 rows em `chat_messages`
- Os 8 paths CK-B foram **enviados**; o check `url_denied` / `like '%..%'` **não correu**

**Conclusão:** P2 hygiene/disponibilidade do guarda. Latente P1: corrigir só o NUL sem alargar o denylist transforma os 500 em 201 no card de prova.
**Prova:** 12 notes CK-A + 8 CK-B com o mesmo 54000; seguro/inbox (sem este canonicalizer) 201/200.

--------------------------------------------------
## TABELA DE PROVAS (55)

| ID | Payload | HTTP / BD | HOLD\|FAIL |
|----|---------|-----------|------------|
| CKA.notes-paysafecash | card notes=PaysafeCash 12,00 € | 500 54000 · status=reserva_pendente | HOLD (miss+crash P2) |
| CKA.notes-paysafe-cash-loja | PaySafe cash código loja | 500 54000 | HOLD (miss+crash) |
| CKA.notes-pix-emv | Pix Copia e Cola EMV curto | 400 notes_forbidden | HOLD |
| CKA.notes-pix-cpf | chave pix aleatória CPF | 400 notes_forbidden | HOLD |
| CKA.notes-picpay | PicPay 12,00 € | 500 54000 | HOLD (miss+crash) |
| CKA.notes-mbway-qr | MB WAY QR / lê este QR MBWay | 400 notes_forbidden | HOLD |
| CKA.notes-sepa-inst | SEPA Instant / SCT Inst | 400 notes_forbidden | HOLD |
| CKA.notes-iban-instant | IBAN + enviado instantâneo 12 € | 400 notes_forbidden | HOLD |
| CKA.notes-revolut-dot-me | Revolut . Me 12,00 € | 400 notes_forbidden | HOLD |
| CKA.notes-revolut-u2024 | revolut․me (U+2024) 12,00 € | 400 notes_forbidden | HOLD |
| CKA.notes-rev0lut | rev0lut.me 12 € | 500 54000 | HOLD (miss+crash) |
| CKA.notes-apple-cash | Apple Cash 12,00 € | 400 notes_forbidden | HOLD |
| CKA.notes-apple-pay-cash | Apple Pay Cash | 400 notes_forbidden | HOLD |
| CKA.notes-tap-nfc | tap to cash / NFC prova | 500 54000 | HOLD (miss+crash) |
| CKA.notes-gpay-send | Google Pay send money | 400 notes_forbidden | HOLD |
| CKA.notes-samsung-pay | Samsung Pay transfer | 500 54000 | HOLD (miss+crash) |
| CKA.notes-money-order | money order / cashier check | 500 54000 | HOLD (miss+crash) |
| CKA.notes-vanilla | Vanilla gift card | 500 54000 | HOLD (miss+crash) |
| CKA.notes-paysafe-pin | PaySafe card PIN | 500 54000 | HOLD (miss+crash) |
| CKA.notes-comprovativo-mbway-qr | comprovativo MB WAY QR | 400 notes_forbidden | HOLD |
| CKA.notes-transf-sepa | transferência imediata SEPA | 400 notes_forbidden | HOLD |
| CKA.notes-revolutme | enviei por RevolutMe | 400 notes_forbidden | HOLD |
| CKA.notes-cashapp-spaced | $Cash App Pay | 400 notes_forbidden | HOLD |
| CKA.notes-wise-tag | Wise tag @user / pay.wise | 400 notes_forbidden | HOLD |
| CKA.notes-it-bonifico | bonifico istantaneo 12,00 € | 500 54000 | HOLD (miss+crash) |
| CKA.notes-de-ueberweisung | Überweisung 12,00 € | 500 54000 | HOLD (miss+crash) |
| CKA.ctrl-skrill | Skrill 12,00 € (residual) | 400 notes_forbidden | HOLD residual |
| CKA.ctrl-wechat | WeChat Pay 12,00 € (residual) | 400 notes_forbidden | HOLD residual |
| CKA.seguro-paysafecash | seguro label=PaysafeCash 12,00 € | **201 id=1610** · order pago | **FAIL → P1-1** |
| CKA.seguro-picpay | seguro label=PicPay 12,00 € | **201 id=1611** · order pago | **FAIL → P1-1** |
| CKA.seguro-apple-cash | seguro label=Apple Cash 12,00 € | 400 label_mismatch | HOLD |
| CKA.seguro-samsung-pay | seguro label=Samsung Pay transfer | 400 label_mismatch | HOLD |
| CKB.proof-u002f | proof_url `%u002e%u002e%u002f` ×2 → order B | 500 54000 · order A pago | HOLD (CK-B inalcançável) |
| CKB.proof-pct255c | `%2e%2e%255c` (residual CDCI) | 500 54000 | HOLD |
| CKB.proof-utf16le | `%ff%fe%2e` UTF-16LE | 500 54000 | HOLD |
| CKB.proof-mixed-252f-255c | `%252f%255c` mixed | 500 54000 | HOLD |
| CKB.proof-two-dot-leader | `‥` U+2025 (residual CDCI) | 500 54000 | HOLD |
| CKB.proof-c1-9c | `%c1%9c` (residual CDCI) | 500 54000 | HOLD |
| CKB.proof-null-00 | `%00` (residual CDCI) | 500 54000 | HOLD |
| CKB.proof-shy-dots | `.`+SHY+`.` | 500 54000 | HOLD |
| CKC.inbox-paysafecash | PATCH last_message=PaysafeCash 12,00 € | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-tap-nfc | tap to cash / NFC prova | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-samsung | Samsung Pay transfer | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-vanilla | Vanilla gift card | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-bonifico | bonifico istantaneo 12,00 € | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-ueberweisung | Überweisung 12,00 € | **200 stored exact** | **FAIL → P1-2** |
| CKC.inbox-rev0lut | rev0lut.me 12 € | **200 stored exact** | **FAIL → P1-2** |
| CKC.ctrl-wechat | WeChat Pay 12,00 € (residual) | 403 inbox_preview_forbidden | HOLD residual |
| CKC.list-alien | B1 LIST prefix B2 | 200 `[]` | HOLD |
| CKC.upload-alien | B1 UPLOAD path B2 | 403 AccessDenied RLS | HOLD |
| CKC.get-cross | B2 GET prova B1 | 404 NoSuchKey | HOLD |
| CKD.chrono-insert | INSERT created_at −3h | 201; created_at=now() clamped | HOLD |
| CKD.inject-b2 | B2 INSERT thread A–B | 403 RLS chat_messages | HOLD |
| CK8.ocr-notoken | OCR sem x-device-token | 401 missing_device_token | HOLD |
| CKD.compose-pago | PaysafeCash card + PATCH pago | card 500 · patch 403 · status inalterado · Δwallet=0 | HOLD |

`probes_na_tabela: 55` (≥24 rails/copy + ≥8 paths + inbox/storage + composição).

--------------------------------------------------
## Denylist — o que fechou vs o que passou

**400 notes_forbidden (card):** Pix EMV · chave pix CPF · MB WAY QR · SEPA Instant · IBAN instantâneo · Revolut . Me · revolut․me (U+2024) · Apple Cash · Apple Pay Cash · Google Pay send money · comprovativo MB WAY QR · transferência imediata SEPA · RevolutMe · $Cash App Pay · Wise tag · Skrill · WeChat.

**500 54000 = notes NÃO classificadas como lie:** PaysafeCash · PaySafe cash loja · PicPay · rev0lut.me · tap to cash/NFC · Samsung Pay transfer · money order · Vanilla gift card · PaySafe card PIN · bonifico · Überweisung.

**Seguro 201:** PaysafeCash, PicPay. **Seguro 400:** Apple Cash (`apple`), Samsung Pay transfer (`transfer`).

--------------------------------------------------
## Storage / cronologia / Edge / composição

| Tentativa | Resultado |
|-----------|-----------|
| Upload prova própria | 200 Key `fleaber_private/order_proofs/{b1}/{oidA}/rtck_a.png` |
| B1 list prefix B2 | 200 `[]` |
| B1 upload path B2 | 403 RLS AccessDenied |
| B2 GET prova B1 | 404 NoSuchKey |
| INSERT created_at −3h | 201; timestamp = now() |
| B2 INSERT chat A–B | 403 RLS |
| OCR sem device token | 401 missing_device_token |
| Card + PATCH pago | 403 `order_buyer_cannot_mark_pago`; status `reserva_pendente`; wallet sem Δ |

--------------------------------------------------
## Lentes 8/8
CK1 cards · CK2 encoding (paths enviados) · CK3 cronologia (clamped) · CK4 URLs (CK-B 8/8 enviados; check inalcançável por P2-1) · CK5 inbox · CK6 storage · CK7 cross-user · CK8 Edge/OCR.

Tácticas: matriz CK-A **26/26** (+2 residual) · CK-B **8/8** · inbox **≥4** novos (7 FAIL) · storage **≥2** · composição **1**.

Saturação: poços A–D · lentes 8 · tabela 55 · CONTAGEM 0+2+1+0=3 · anti-atrofia OK.

**NÃO CORRIGIR.**
