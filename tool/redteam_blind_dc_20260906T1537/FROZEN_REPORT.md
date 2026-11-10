# FROZEN · REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1
Prefixo `RTDC-20260906T1537` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 0
1. P0 dinheiro irreversível? NÃO
2. Quantos P0: 0
3. P1 caminho explorável? NÃO
4. Quantos P1: 0
5. P2 hygiene? NÃO
6. Quantos P2: 0
7. P3 baixo risco? NÃO
8. Quantos P3: 0
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_DC_CHAT_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 38
VEREDICTO: PASS_CEGO_SATURADO
```

Anti-atrofia: **OK**. Residual exacto CQ na tabela: `12,00` · `doze euros` — ambos **400 `notes_forbidden`** (HOLD, não contar). 2/38 ≪ 50%. Sem PaysafeCash/PicPay.

Positivos A1–A3: **OK** (vazio, `stripe_paid_direct`, `obrigado`, `já enviei` → 201).  
B* não-canónico → deny. P0–P2 = 0 → `PASS_CEGO_SATURADO`.

Composição C3 **tentada**: card notes=`pago` → **201 id=1764**; `PATCH orders.status=pago` → `403 order_buyer_cannot_mark_pago`. Status `reserva_pendente` inalterado. Wallet seller `43.0 → 40.0` (ruído concorrente no mesmo vendedor; o PATCH desta encomenda foi 403 e o estado não mudou — não é finding).

--------------------------------------------------
## Missão
Canónicos OK. Tudo o resto deny. Bypass residual fino (case/ZWSP/homoglyph **em canónico**, type coercion, inbox) pós-CW saturado?

**Resposta:** **Não.** `lower(trim)` aceita o mesmo token em maiúsculas (`Paguei`) — contrato, não furo. ZWSP prefix / word-joiner / soft-hyphen / NBSP / ZWNJ / cirílico `а` / NFD / small-caps / TAG / FSI / RLO / sufixo / texto livre / boolean / array → **400 `notes_forbidden`**. Inbox não-canónico → **403 `chat_inbox_preview_forbidden`**. Label Seguro hostil / homoglyph → `label_mismatch`. JSON truncado → `invalid_json`. Chave `rail` → `payload_forbidden`. Storage alheio → RLS 403 + `url_denied`. FSM pago sem Stripe → 403. Residual CQ (`12,00` / `doze euros`) fechado.

--------------------------------------------------
## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

--------------------------------------------------
## HOLD (não contar como finding)

- Case fold canónico `Paguei` → 201 (`lower()`)
- `notes: null` JSON → coalesce vazio → 201 (A1)
- Encoding novo em canónico (ZWSP prefix, WJ, SHY, NBSP, ZWNJ, TAG, FSI, RLO, NFD, cirílico, small-caps) → 400
- Type coercion boolean / array → 400
- Inbox hostil / homoglyph / sufixo / TAG → 403
- Seguro label hostil / canónico `compra paga` → `label_mismatch` / `total_mismatch`
- Card `comprovativo envio` → 400 · `rail=mbway` → `payload_forbidden` · JSON truncado → `invalid_json`
- FSM `PATCH pago` sem Stripe → 403 · status inalterado
- Upload path B2 → 400/403 RLS · proof_url B2 → `url_denied`
- OCR Edge sem device token → 401
- Residual CQ 12,00 / doze euros → 400

Lentes cobertas: DC1 allowlist · DC2 encoding · DC3 inbox · DC4 seguro · DC5 card · DC6 FSM · DC7 Edge (7/7).

--------------------------------------------------
## TABELA DE PROVAS (38 LIVE)

| probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD\|FAIL\|SKIP |
|---|---|---|---|---|---|
| DCA.A1-empty | DC-A notes | (vazio) | 201 id=1734 | status=pago persistido | PASS |
| DCA.A2-stripe | DC-A notes | stripe_paid_direct | 201 id=1735 | status=pago persistido | PASS |
| DCA.A3-obrigado | DC-A notes | obrigado | 201 id=1736 | status=pago persistido | PASS |
| DCA.A3b-ja-enviei | DC-A notes | já enviei | 201 id=1737 | status=pago persistido | PASS |
| DCB.B1-zwsp-prefix | DC-B encoding | ZWSP + paguei | 400 notes_forbidden | recusado | HOLD |
| DCB.B1-wj-mid | DC-B encoding | pa WJ guei | 400 notes_forbidden | recusado | HOLD |
| DCB.B1b-shy-mid | DC-B encoding | pa SHY guei | 400 notes_forbidden | recusado | HOLD |
| DCB.B1c-nbsp-ok | DC-B encoding | o NBSP k | 400 notes_forbidden | recusado | HOLD |
| DCB.B1d-zwnj | DC-B encoding | pa ZWNJ guei | 400 notes_forbidden | recusado | HOLD |
| DCB.B2-case-Paguei | DC-B case | Paguei | 201 id=1743 | persistido (lower→paguei) | HOLD |
| DCB.B2b-homoglyph-cyrA | DC-B homoglyph | p + Cyrillic а + guei | 400 notes_forbidden | recusado | HOLD |
| DCB.B2c-nfd-ja | DC-B homoglyph | já enviei NFD (a+U+0301) | 400 notes_forbidden | recusado | HOLD |
| DCB.B2d-smallcaps | DC-B homoglyph | small-caps paguei | 400 notes_forbidden | recusado | HOLD |
| DCB.B3-suffix-ok | DC-B suffix | ok por favor | 400 notes_forbidden | recusado | HOLD |
| DCB.B4-tudo-bem | DC-B free text | tudo bem | 400 notes_forbidden | recusado | HOLD |
| DCB.B5-notes-bool | DC-B json | notes=true (JSON boolean) | 400 notes_forbidden | recusado | HOLD |
| DCB.B5b-notes-array | DC-B json | notes=["ok"] (JSON array) | 400 notes_forbidden | recusado | HOLD |
| DCB.B5c-notes-null | DC-B json | notes=null | 201 id=1751 | coalesce vazio = canónico | HOLD |
| DCB.B6-rtl | DC-B encoding | RLO + paguei | 400 notes_forbidden | recusado | HOLD |
| DCB.B6b-tags-wrap | DC-B encoding | TAG-a + paguei | 400 notes_forbidden | recusado | HOLD |
| DCB.B6c-tags-only | DC-B encoding | só TAG U+E0061 ×3 | 400 notes_forbidden | recusado | HOLD |
| DCB.B6d-fsi | DC-B encoding | FSI + paguei | 400 notes_forbidden | recusado | HOLD |
| DCB.B7-inbox-tudo-bem | DC-B inbox | tudo bem | PATCH 403 preview_forbidden | last_message=null | HOLD |
| DCB.B7b-inbox-homoglyph | DC-B inbox | p + Cyrillic а + guei | PATCH 403 preview_forbidden | last_message=null | HOLD |
| DCB.B7c-inbox-suffix | DC-B inbox | ok por favor | PATCH 403 preview_forbidden | last_message=null | HOLD |
| DCB.B7d-inbox-tags | DC-B inbox | TAG-a + paguei | PATCH 403 preview_forbidden | last_message=null | HOLD |
| DCB.R-12comma | DC-B residual | 12,00 | 400 notes_forbidden | recusado | HOLD (residual, não contar) |
| DCB.R-doze | DC-B residual | doze euros | 400 notes_forbidden | recusado | HOLD (residual, não contar) |
| DCC.C1-seguro-hostile | DC-C seguro | compra paga 12,00 € | 400 label_mismatch | recusado | HOLD |
| DCC.C1b-canonical | DC-C seguro | compra paga | 400 total_mismatch | recusado (guarda total) | HOLD |
| DCC.C1c-homoglyph | DC-C seguro | c + Cyrillic а + mpra paga | 400 label_mismatch | recusado | HOLD |
| DCC.C2-card-hostile | DC-C card | comprovativo envio | 400 notes_forbidden | recusado | HOLD |
| DCC.C2b-payload-rail | DC-C card | notes=ok + rail=mbway | 400 payload_forbidden | recusado | HOLD |
| DCC.C2c-malformed-json | DC-C card | FLEABER_JSON_V1 truncado | 400 invalid_json | recusado | HOLD |
| DCC.C3-compose-pago | DC-C composição | card notes=pago + PATCH pago | card 201 id=1764 · patch 403 | reserva_pendente | HOLD |
| DCC.C4-upload-alien | DC-C storage | B1 UPLOAD path B2 | 400/403 RLS | sem objecto | HOLD |
| DCC.C4b-proof-alien | DC-C storage | proof_url path B2 | 400 url_denied | recusado | HOLD |
| DC7.ocr-notoken | DC7 Edge | OCR sem token ocr_raw=paguei | 401 missing_device_token | sem ingest | HOLD |

Quota ≥14: **38**. Residual exacto CQ HOLD: **2** (`12,00` · `doze euros`; anti-atrofia; não findings). Sem lista de rails.

Chat `bf97c7f3-f237-42aa-8fe3-9da6c77c17d5` · encomenda Stripe `d499a6e2-f34f-4a82-b13b-0711cb0c2ae9` (`pago`, PI `pi_3UChHVH7FWYUN3jh1mC6KuX1` succeeded) · pendente C3 `60974553-68cb-47c6-a3a1-2d3c00c39e06` inalterada.

**NÃO CORRIGIR.**
