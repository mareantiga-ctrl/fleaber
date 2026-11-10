# FROZEN · REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1
Prefixo `RTCE-20260906T1227` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 50
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 50
1. P0? NÃO  2. Quantos P0: 0
3. P1? SIM  4. Quantos P1: 50
5. P2? NÃO  6. Quantos P2: 0
7. P3? NÃO  8. Quantos P3: 0
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_CE_CHAT_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
lentes_cobertas: [CE1, CE2, CE3, CE4, CE5, CE6, CE7, CE8]
pocos_tentados: [CE-A, CE-B, CE-C, CE-D, CE-E]
VEREDICTO: FAIL_P1
```

Anti-atrofia: **OK**. Nenhum finding conta Skrill / Neteller / Paysafecard / MoneyGram / GCash / Perfect Money / «enviado MB» / Clearpay+U+206A / `%252e` / Payoneer. Controlos exactos BXCC foram recusados (`notes_forbidden` / `inbox_preview_forbidden`). ≥50% dos P1 são rails/encodings **fora** desse conjunto (WeChat, UPI, $cashtag, UnionPay, wallets regionais, MB-WAY com hífen, homógrafos, triple-encode, U+2025, overlong-4, `%u002e`).

Composição CE-E **tentada**: card WeChat 201 + `PATCH orders.status=pago` → `403 order_buyer_cannot_mark_pago`. FSM e wallet **não** mudaram. Mentira de rail = prova social no chat/inbox, não liquidação Stripe.

--------------------------------------------------
## Missão
Ainda se consegue mentir rail, colar prova com path não canónico BXCC, ou forjar inbox — **sim (P1)**. Ler/escrever storage alheio, partir cronologia, injectar cross-user, OCR sem token, ou libertar stock/pago sem Stripe — **não** nesta corrida.

--------------------------------------------------
## POÇO CE-A — rails / copy (matriz)

FAIL do poço = aceite como card de prova / muda FSM. FSM não mudou. Cards `reservation_payment_submitted` e `seguro_fleaber_paid` **aceites** (HTTP 201) = prova de pagamento no chat.

### Passaram o denylist (card persistiu) — P1-1…P1-25, P1-26…P1-34, P1-35…P1-41

| String | Card notes | Seguro label | Inbox |
|--------|------------|--------------|-------|
| WeChat Pay 12,00 € | 201 P1-1 | 201 P1-26 | 201 P1-42 |
| 微信支付 12,00 € | 201 P1-2 | — | — |
| 支付宝 12,00 € | 201 P1-3 | — | — |
| UPI 12,00 € | 201 P1-4 | 201 P1-27 | 201 P1-43 |
| $cashtag 12,00 € | 201 P1-5 | 201 P1-28 | 201 P1-44 |
| envia para esta wallet 12,00 € | 201 P1-6 | — | — |
| já transferi MB 12,00 € | 201 P1-7 | 400 label_mismatch | 403 inbox_forbidden |
| pago por transferência (sem montante) | 201 P1-8 | — | — |
| UnionPay / M-Pesa / Swish / KakaoPay / LINE Pay / GrabPay / Blik / Vipps / PayNow / PayID / Osko / Dana / MoMo / Touch n Go | 201 P1-9…P1-22 | UnionPay P1-29 | — |
| MB-WAY 12,00 € (hífen; `mb\s*way` não cobre) | 201 P1-23 | 201 P1-30 | 201 P1-45 |
| Pay Pal 12,00 € (espaço) | 201 P1-24 | — | — |
| PayPaI 12,00 € (I latino vs l) | 201 P1-25 | — | — |
| МB WAY (Cyrillic U+041C) | 201 P1-31 | — | — |
| MВ WAY (Cyrillic U+0412) | 201 P1-32 | — | — |
| Сlearpay (Cyrillic U+0421) | 201 P1-33 | — | 201 P1-46 |
| 𝖯𝖺𝗒𝖯𝖺𝗅 (math sans-serif) | 201 P1-34 | — | — |
| WeChat + Hangul filler / U+2064 / Braille / Khmer / SHY | 201 P1-35…P1-37, P1-40, P1-41 | — | — |
| UPI + EN QUAD / ideographic space | 201 P1-38, P1-39 | — | — |

### Falharam o denylist (recusados — não contar)

CashApp Pay · Venmo Business · Revolut Me · Wise link · Interac e-Transfer · USDT TRC20 · BTC wallet · comprovativo multibanco · enviei por MBWay · pago por transferência **12,00 €** · Skrill · enviado MB · Payoneer.

Pedido da matriz coberto: Venmo/Cash App (bloqueados na forma canónica; CashApp one-word bloqueado) · WeChat/UPI/cashtag (abertos) · Revolut Me/Wise/Zelle/Interac (bloqueados via rail já listado) · USDT/BTC canónicos bloqueados; «envia para esta wallet» aberto · PT «já transferi MB» aberto no card, fechado no inbox · homógrafos MB WAY / Clearpay / PayPal abertos.

Estado BD dos cards: `orders.status` manteve-se `reserva_pendente` (P1-1 evidence). Não há Δwallet.

--------------------------------------------------
## POÇO CE-B — encoding / URL / path

Canonical BXCC cobre `%c0%ae`, `%2e%2e%2f`, fullwidth `．．`, RLO, `javascript:`, `data:`, host não-Supabase, `file://`, path `order_disputes/` alheio, proof de outro order. **Recusados** (`chat_system_card_url_denied`).

**Abertos (card 201, URL persistida no `chat_messages.text`):**

- **P1-47** `%25252e%25252e` triple-encode `../` — msg id 1565. Canonical só faz 3 passes de `%252e`/`%2e`; `%25252e` não colapsa.
- **P1-48** TWO DOT LEADER U+2025 `‥/‥/` — msg id 1567. Não está no replace de `․`/`．`.
- **P1-49** overlong 4-byte `%f0%80%80%ae` — msg id 1568. Só há 2-byte `%c0%ae` e 3-byte `%e0%80%ae`.
- **P1-50** IIS `%u002e%u002e` — msg id 1569.

Prefixo `fleaber_private/order_proofs/{buyer}/{orderA}/` continua no URL; o resto aponta a `orderB`. Storage S3 **não** foi observado a resolver estas sequências como `..` (não se leu o objecto de B). Risco: card de prova aceite com path fora do objecto da encomenda se um cliente/proxy decodificar mais agressivamente. Sem FSM pago.

`%252e` exacto BXCC **não** foi o payload (triple é `%25252e`).

--------------------------------------------------
## POÇO CE-C — storage / OCR / Edge

| Tentativa | Resultado |
|-----------|-----------|
| Upload prova própria | 200 Key `fleaber_private/order_proofs/{b1}/{oidA}/rtce_a.png` |
| B1 list prefix B2 | 200 `[]` |
| B1 upload path B2 | 403 RLS `AccessDenied` |
| B2 overwrite prova B1 | 403 RLS |
| B2 GET prova B1 | 404 `NoSuchKey` (não revelou corpo) |
| OCR sem `x-device-token` | 401 `missing_device_token` |
| OCR token inventado (buyer) | 401 `invalid_token` |
| OCR token inventado (seller / replay) | 401 `invalid_token` |

Edge **não** confirma pagamento só com texto OCR: ingest cria reserva live, não marca `orders.status=pago`. Sem P0/P1 aqui.

--------------------------------------------------
## POÇO CE-D — cronologia / inbox / cross-user

| Tentativa | Resultado |
|-----------|-----------|
| INSERT `created_at` −3h | 201; `created_at` = now() (clamped) |
| PATCH `created_at` passado | 200 representação; timestamp inalterado |
| B2 INSERT no chat A–B | 403 RLS `chat_messages` |
| B2 SELECT thread A–B | 200 `[]` |
| B2 PATCH `last_message` chat A–B | 200 `[]` (0 rows) |

Inbox **participante** com rails novos: P1-42…P1-46 (já em CE-A). Push payload hostil: sem endpoint de push autenticável nesta corrida; não saturado como finding.

--------------------------------------------------
## POÇO CE-E — composição

Card WeChat em thread de encomenda **já paga Stripe** (201 id 1581) + PATCH `pago` pelo buyer na reserva pendente → **403 `order_buyer_cannot_mark_pago`**. Status `reserva_pendente` inalterado. Wallet seller sem Δ nesta composição. Mentira de rail **não** liberta stock nem marca pago.

--------------------------------------------------
## IDs P1-1 … P1-50

Ver `findings_numbered.json`. Soma = 50 = CONTAGEM.

--------------------------------------------------
## Lentes
CE1 cards · CE2 encoding rails · CE3 cronologia (tentada, bloqueada) · CE4 URLs · CE5 inbox · CE6 storage (tentada, bloqueada) · CE7 cross-user (tentada, bloqueada) · CE8 Edge/OCR (tentada, bloqueada). **8/8.**

Tácticas mínimas: ≥8 strings CE-A **sim** · ≥1 path encoding **sim** · ≥1 storage/OCR **sim** · ≥1 cross-user **sim** · evidência HTTP+BD **sim**.

Saturação: poços A–E · lentes 8 · tácticas 1–4 · CONTAGEM coerente · anti-atrofia OK.

**NÃO CORRIGIR.**
