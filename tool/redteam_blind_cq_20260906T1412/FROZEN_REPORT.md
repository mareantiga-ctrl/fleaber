# FROZEN · REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1
Prefixo `RTCQ-20260906T1412` · staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST  
`production_touched: false` · `fase4: false` · `corrections_applied: false`

--------------------------------------------------
## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1
1. P0? NÃO  2. Quantos P0: 0
3. P1? SIM  4. Quantos P1: 1
5. P2? NÃO  6. Quantos P2: 0
7. P3? NÃO  8. Quantos P3: 0
--------------------------------------------------

```
AUDITOR: REDTEAM_BLIND_CQ_CHAT_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: 34
VEREDICTO: FAIL_P1
```

Anti-atrofia: **OK**. 1 linha residual PaysafeCash exacto (HOLD `notes_forbidden`). 0 PicPay. 1/34 ≪ 50%. Findings **não** são PaysafeCash/PicPay/esaurito/Coptic/follow unpublished.

Positivos A1–A3: **OK** (vazio, `stripe_paid_direct`, «obrigado», «já enviei» → 201).  
P0–P2 ≠ 0 → não `PASS_CEGO_SATURADO`.

Composição C5 **tentada**: card notes=`12,00` → **201**; `PATCH orders.status=pago` → `403 order_buyer_cannot_mark_pago`. Status `reserva_pendente` inalterado. Wallet seller `61.0 → 61.0`. Mentira de montante = prova social, não liquidação Stripe.

--------------------------------------------------
## Missão
O que **não** está na lista branca de notes/label/inbox passa? **Sim (P1)** — o terceiro ramo de `batata_chat_client_notes_allowed` aceita qualquer texto ≤120 sem `[€$£¥]`, sem `\d+ €|eur|euros` e sem `payment_lie_text`. Montante nu, glifos/entidades, «doze euros», JSON e inbox herdam o furo. Label Seguro canónico/hostil e FSM pago **não** abrem.

--------------------------------------------------
## P1-1 — allowlist notes é denylist disfarçada (card + inbox)

**O que isto é:** o comprador cola um cartão «pagamento submetido» ou altera o preview da caixa de entrada com um montante/símbolo de dinheiro que a lista branca não nomeia — e o texto grava-se.

**Quem / onde:** buyer JWT · `chat_messages` no chat `8cb954ab-ca90-4c0a-bb2f-5b99de5fc167` · encomenda Stripe `38ca021b-9d33-40e0-b27e-d5fa73a76c60` (já `pago`) e encomenda pendente `orders` do SKU RTCQ.

**O que fizemos:** POST `kind=reservation_payment_submitted` com notes fora dos 6 canónicos; PATCH `chats.last_message` com os mesmos textos.

**Esperado vs resultado**
- € U+20AC, `12.00 EUR`, NFKC `１２．００ ＥＵＲ`, ZWSP+€, soft-hyphen+EUR, PaysafeCash exacto → **400 `notes_forbidden`** (HOLD)
- Persistidos (201): `12,00` · `12,50` · `doze euros` · `enviado 12 💶` · `obrigado ￥ 12` · `12,00 ϵ` · `12 ₠` · `paguei &#8364; 12` · `12 &euro;` · `["12,00"]` · `{"paid":12.00}` · notes JSON number `12.00` · texto longo com `12,00` no meio · `pago 12 usd`
- Inbox PATCH 200 stored exact: `12,00` · `12 &euro;` · `enviado 12 💶` · `doze euros`
- Base de dados: `orders.status` Stripe permanece `pago`; encomenda pendente permanece `reserva_pendente`; **Δ wallet = 0**
- Label Seguro hostil → `400 label_mismatch` (HOLD). Label canónico `compra paga` → `400 total_mismatch` (outro guarda, não allowlist — HOLD)

**Conclusão:** P1 — prova social de montante/moeda no card e no preview da inbox. Uma classe (ramo 3 da allowlist), duas superfícies. Não liberta stock nem marca pago.
**Prova:** HTTP 201 ids 1644–1659, 1664–1666 · PATCH 200 `last_message` · `probes.json`.

--------------------------------------------------
## HOLD (não contar como finding)

- Storage upload path B2 → 400/403 RLS
- OCR Edge sem device token → 401 `missing_device_token`
- FSM `PATCH pago` sem Stripe → 403
- € literal, `EUR` ASCII, fullwidth NFKC, residual PaysafeCash
- Seguro label hostil / `paguei` como label

Lentes cobertas: CQ1 notes · CQ2 encoding · CQ3 €/amount · CQ4 seguro/label · CQ5 inbox · CQ6 card · CQ7 Edge (7/7).

--------------------------------------------------
## TABELA DE PROVAS (34 LIVE)

| probe_id | superfície | payload | HTTP/RPC | BD/inbox | HOLD\|FAIL\|SKIP |
|---|---|---|---|---|---|
| CQA.A1-empty | CQ-A notes | (vazio) | 201 id=1639 | status=pago persistido | PASS |
| CQA.A2-stripe | CQ-A notes | stripe_paid_direct | 201 id=1640 | status=pago persistido | PASS |
| CQA.A3-obrigado | CQ-A notes | obrigado | 201 id=1641 | status=pago persistido | PASS |
| CQA.A3b-ja-enviei | CQ-A notes | já enviei | 201 id=1642 | status=pago persistido | PASS |
| CQB.B1-euro-unicode | CQ-B encoding | obrigado € | 400 notes_forbidden | recusado | HOLD |
| CQB.B1b-yen-fullwidth | CQ-B encoding | obrigado ￥ 12 | 201 id=1644 | persistido | FAIL → P1-1 |
| CQB.B1c-euro-emoji | CQ-B encoding | enviado 12 💶 | 201 id=1645 | persistido | FAIL → P1-1 |
| CQB.B2-amount-no-rail | CQ-B amount | 12,00 | 201 id=1646 | persistido | FAIL → P1-1 |
| CQB.B2b-dot-eur | CQ-B amount | 12.00 EUR | 400 notes_forbidden | recusado | HOLD |
| CQB.B2c-doze-euros | CQ-B amount | doze euros | 201 id=1648 | persistido | FAIL → P1-1 |
| CQB.B3-zwsp-amount | CQ-B encoding | 12 ZWSP ,00 € | 400 notes_forbidden | recusado | HOLD |
| CQB.B3b-shy-amount | CQ-B encoding | 12 SHY ,00 EUR | 400 notes_forbidden | recusado | HOLD |
| CQB.B4-homoglyph-eps | CQ-B encoding | 12,00 ϵ | 201 id=1651 | persistido | FAIL → P1-1 |
| CQB.B4b-euro-currency-sign | CQ-B encoding | 12 ₠ | 201 id=1652 | persistido | FAIL → P1-1 |
| CQB.B4c-fullwidth-eur | CQ-B encoding | １２．００ ＥＵＲ | 400 notes_forbidden | recusado (NFKC) | HOLD |
| CQB.B5-digits-comma | CQ-B amount | 12,50 | 201 id=1654 | persistido | FAIL → P1-1 |
| CQB.B6-html-entity | CQ-B encoding | paguei &#8364; 12 | 201 id=1655 | persistido | FAIL → P1-1 |
| CQB.B6b-amp-euro | CQ-B encoding | 12 &euro; | 201 id=1656 | persistido | FAIL → P1-1 |
| CQB.B7-json-array | CQ-B json | ["12,00"] | 201 id=1657 | persistido | FAIL → P1-1 |
| CQB.B7b-json-object | CQ-B json | {"paid":12.00} | 201 id=1658 | persistido | FAIL → P1-1 |
| CQB.B7c-notes-number | CQ-B json | notes=12.00 (JSON number) | 201 id=1666 | persistido | FAIL → P1-1 |
| CQB.B8-long-mid-amount | CQ-B amount | texto longo + 12,00 no meio | 201 id=1659 | persistido | FAIL → P1-1 |
| CQB.R-paysafecash | CQ-B residual | PaysafeCash 12,00 € | 400 notes_forbidden | recusado | HOLD (residual, não contar) |
| CQC.C1-seguro-hostile | CQ-C seguro | compra paga 12,00 € | 400 label_mismatch | recusado | HOLD |
| CQC.C1b-paguei-as-label | CQ-C seguro | paguei | 400 label_mismatch | recusado | HOLD |
| CQC.C1c-canonical | CQ-C seguro | compra paga | 400 total_mismatch | recusado (guarda total, não allowlist) | HOLD |
| CQC.C2-inbox-amount | CQ-C inbox | 12,00 | PATCH 200 | last_message exact | FAIL → P1-1 |
| CQC.C2b-inbox-entity | CQ-C inbox | 12 &euro; | PATCH 200 | last_message exact | FAIL → P1-1 |
| CQC.C2c-inbox-emoji | CQ-C inbox | enviado 12 💶 | PATCH 200 | last_message exact | FAIL → P1-1 |
| CQC.C2d-inbox-doze | CQ-C inbox | doze euros | PATCH 200 | last_message exact | FAIL → P1-1 |
| CQC.C3-card-hostile | CQ-C card | pago 12 usd | 201 id=1664 | persistido | FAIL → P1-1 |
| CQC.C4-upload-alien | CQ-C storage | B1 UPLOAD path B2 | 400/403 RLS | sem objecto | HOLD |
| CQC.C5-compose-pago | CQ-C composição | card 12,00 + PATCH pago | card 201 id=1665 · patch 403 | reserva_pendente · Δwallet=0 | HOLD |
| CQ7.ocr-notoken | CQ7 Edge | OCR 12,00 confirmado sem token | 401 missing_device_token | sem ingest | HOLD |

Quota ≥16: **34**. Controlos residual exactos: **1** (≤2, ≠ ≥50%). Sem lista de 24 marcas.

**NÃO CORRIGIR.**
