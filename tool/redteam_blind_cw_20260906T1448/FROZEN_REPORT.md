# FROZEN · REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1
Prefixo `RTCW-20260906T1448` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0
1. P0? NÃO  2. Quantos P0: 0
3. P1? NÃO  4. Quantos P1: 0
5. P2? NÃO  6. Quantos P2: 0
7. P3? NÃO  8. Quantos P3: 0
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_CW_CHAT_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 35
VEREDICTO: PASS_CEGO_SATURADO
```

Anti-atrofia: **OK**. Residual exacto CQ na tabela: `12,00` · `doze euros` · `enviado 12 💶` — todos **400 `notes_forbidden`** (HOLD, não contar). 3/35 ≪ 50%. Sem PaysafeCash/PicPay.

Positivos A1–A4: **OK** (vazio, `stripe_paid_direct`, `obrigado`, `já enviei`, `comprovativo anexo`, frase longa → 201). Inbox canónico `ok` → PATCH 200.  
B* não-canónico → deny. P0–P2 = 0 → `PASS_CEGO_SATURADO`.

Composição C4 **tentada**: card notes=`pago` → **201**; `PATCH orders.status=pago` → `403 order_buyer_cannot_mark_pago`. Status `reserva_pendente` inalterado. Wallet seller `56.0 → 56.0`.

--------------------------------------------------
## Missão
Bypass da allowlist estrita (só tokens canónicos; resto deny mesmo sem €) via case / ZWSP / NFKC / JSON / type coercion?

**Resposta:** **Não.** `lower(trim)` aceita o mesmo token em maiúsculas (`Paguei`, `OBRIGADO`) — contrato CPCU, não furo. ZWSP/NBSP/fullwidth/acento/sufixo/texto livre/JSON/number/HTML/RLO/ZWSP-only → **400 `notes_forbidden`**. Inbox não-canónico → **403 `chat_inbox_preview_forbidden`**. Label Seguro hostil → `label_mismatch`. FSM pago sem Stripe → 403. Residual CQ (`12,00` / `doze euros` / 💶) fechado.

--------------------------------------------------
## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

--------------------------------------------------
## HOLD (não contar como finding)

- Case fold canónico `Paguei` / `OBRIGADO` → 201 (`lower()`)
- Espaços-only → trim vazio → 201 (A1)
- Extra key `amount:12` com notes=`ok` → 201 no JSON; **UI só renderiza `notes`/`proof_url`** (`_buildReservationPaymentSubmittedCard`); o cliente legítimo já manda `v:1`. Não é prova social nem bypass de notes.
- Seguro label hostil / canónico `compra paga` → `label_mismatch` / `total_mismatch`
- FSM `PATCH pago` sem Stripe → 403 · Δwallet=0
- OCR Edge sem device token → 401
- Residual CQ 12,00 / doze euros / 💶 → 400

Lentes cobertas: CW1 allowlist · CW2 encoding · CW3 inbox · CW4 seguro · CW5 card · CW6 FSM · CW7 Edge (7/7).

--------------------------------------------------
## TABELA DE PROVAS (35 LIVE)

| probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD\|FAIL\|SKIP |
|---|---|---|---|---|---|
| CWA.A1-empty | CW-A notes | (vazio) | 201 id=1691 | status=pago persistido | PASS |
| CWA.A2-stripe | CW-A notes | stripe_paid_direct | 201 id=1692 | status=pago persistido | PASS |
| CWA.A3-obrigado | CW-A notes | obrigado | 201 id=1693 | status=pago persistido | PASS |
| CWA.A3b-ja-enviei | CW-A notes | já enviei | 201 id=1694 | status=pago persistido | PASS |
| CWA.A4-comprovativo-anexo | CW-A notes | comprovativo anexo | 201 id=1695 | status=pago persistido | PASS |
| CWA.A4b-frase-longa | CW-A notes | segue o comprovativo anexo por favor | 201 id=1696 | status=pago persistido | PASS |
| CWB.B1-case-Paguei | CW-B case | Paguei | 201 id=1697 | persistido (lower→paguei) | HOLD |
| CWB.B1b-case-OBRIGADO | CW-B case | OBRIGADO | 201 id=1698 | persistido (lower→obrigado) | HOLD |
| CWB.B1c-accent-Págo | CW-B case | Págo | 400 notes_forbidden | recusado | HOLD |
| CWB.B2-zwsp-mid | CW-B encoding | pa ZWSP guei | 400 notes_forbidden | recusado | HOLD |
| CWB.B2b-nbsp-mid | CW-B encoding | já NBSP enviei | 400 notes_forbidden | recusado | HOLD |
| CWB.B2c-zwsp-trail | CW-B encoding | paguei + ZWSP trailing | 400 notes_forbidden | recusado | HOLD |
| CWB.B2d-nfkc-fullwidth | CW-B encoding | fullwidth ｐａｇｕｅｉ | 400 notes_forbidden | recusado | HOLD |
| CWB.B3-suffix-ok | CW-B suffix | ok por favor | 400 notes_forbidden | recusado | HOLD |
| CWB.B4-tudo-bem | CW-B free text | tudo bem | 400 notes_forbidden | recusado | HOLD |
| CWB.B4b-enviei-agora | CW-B free text | enviei agora | 400 notes_forbidden | recusado | HOLD |
| CWB.B5-json-array | CW-B json | ["ok"] | 400 notes_forbidden | recusado | HOLD |
| CWB.B5b-json-object | CW-B json | {"paid":true} | 400 notes_forbidden | recusado | HOLD |
| CWB.B6-html-euro | CW-B encoding | paguei &euro; | 400 notes_forbidden | recusado | HOLD |
| CWB.B6b-rtl | CW-B encoding | paguei + RLO + x | 400 notes_forbidden | recusado | HOLD |
| CWB.B7-spaces | CW-B empty-ish | (só espaços) | 201 id=1711 | trim vazio = canónico | PASS |
| CWB.B7b-zwsp-only | CW-B empty-ish | (só ZWSP) | 400 notes_forbidden | recusado | HOLD |
| CWB.B8-notes-number | CW-B json | notes=12.00 (JSON number) | 400 notes_forbidden | recusado | HOLD |
| CWB.B8b-extra-amount-key | CW-B json | notes=ok + amount:12 | 201 id=1714 | JSON tem amount; UI ignora | HOLD |
| CWB.R-12comma | CW-B residual | 12,00 | 400 notes_forbidden | recusado | HOLD (residual, não contar) |
| CWB.R-doze | CW-B residual | doze euros | 400 notes_forbidden | recusado | HOLD (residual, não contar) |
| CWC.C1-seguro-hostile | CW-C seguro | compra paga 12,00 € | 400 label_mismatch | recusado | HOLD |
| CWC.C1b-canonical | CW-C seguro | compra paga | 400 total_mismatch | recusado (guarda total) | HOLD |
| CWC.C2-inbox-tudo-bem | CW-C inbox | tudo bem | PATCH 403 preview_forbidden | last_message=null | HOLD |
| CWC.C2b-inbox-json | CW-C inbox | {"paid":true} | PATCH 403 preview_forbidden | last_message=null | HOLD |
| CWC.C2c-inbox-ok | CW-C inbox | ok | PATCH 200 | last_message stored exact | PASS |
| CWC.C3-card-hostile | CW-C card | comprovativo envio | 400 notes_forbidden | recusado | HOLD |
| CWC.C4-compose-pago | CW-C composição | card notes=pago + PATCH pago | card 201 id=1720 · patch 403 | reserva_pendente · Δwallet=0 | HOLD |
| CW7.ocr-notoken | CW7 Edge | OCR paguei confirmado sem token | 401 missing_device_token | sem ingest | HOLD |
| CWB.R-emoji | CW-B residual | enviado 12 💶 | 400 notes_forbidden | recusado | HOLD (residual, não contar) |

Quota ≥16: **35**. Residual exacto CQ HOLD: **3** (12,00 · doze euros · 💶; anti-atrofia lista os três; não findings). Sem lista de rails.

Chat `b9396886-07b7-4e12-9b89-9d02ac66486c` · encomenda Stripe `771d4ffd-66df-4f8c-a52e-3f6c91ce90d9` (`pago`) · pendente C4 inalterada.

**NÃO CORRIGIR.**
