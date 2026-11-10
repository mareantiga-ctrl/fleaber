# FROZEN_REPORT — REDTEAM_BLIND_BA_CHAT_POS_ANAS_v1

AUDITOR: REDTEAM_BLIND_BA_CHAT_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BA1, BA2, BA3, BA4, BA5, BA6, BA7, BA8]
VEREDICTO: FAIL_P1

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 6
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 8
```

**VEREDICTO:** `FAIL_P1` — `proof_url` de cartão `reservation_payment_submitted` aceita URL `object/sign/fleaber_private` de **outra** encomenda/utilizador; o vendedor do chat (e anon) lê os bytes.

Anti-atrofia: variantes **novas** (Klarna, iDEAL, Twint, Afterpay, Google Pay, 💶, Hangul/Braille filler, sign path alheio). Não exactos AO/AU/AI (PayPal 50€, Wise/Revolut/Apple Pay, `/object/public/`, NBSP). Relatório AU **não lido**.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 6
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (order unpaid não virou `pago`; label/display mentem método)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (`refund-order` 403 «Sem permissão.»)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (fora de âmbito chat)
16. Stock=1 duas vendas válidas — NÃO (fora de âmbito)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — SIM (sign `order_proofs` B2 no card B1; GET 200 PNG por S1 e anon)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO (storage GET directo path B2 → 403/404; sign vítima como B1 → 404)
26. Edge confia total do cliente — NÃO (`create-payment-intent` 400 metadata; OCR 401)
27. Regressão funcional (happy path partido) — NÃO (`chat_image` sign próprio 201)
28. Saturação atingida — SIM (8/8 lentes; rails extra Afterpay/GPay mesma classe)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (sem captura paga nesta ronda; PI fixture só para cards `seguro_*`) · JWT buyer/seller lab + B2/S2 criados por admin (fixture) · `service_role` só fixture/observe/cleanup.

Prefixo: `RTBA-20260902T1608-`.

Código estudado: `batata_chat_payment_lie_text` / `normalize_lie_text` / `guard_image_url` / `guard_delete` (ANAS), `assert_json_card` (notes + `proof_url`), RLS `chat_messages`/`chats`, storage `fleaber_private`, Flutter `_buildReservationPaymentSubmittedCard`. Relatórios AU/AO/AI **não lidos**.

--------------------------------------------------
## ACHADO P1
--------------------------------------------------

### BA-P1-01 — `proof_url` sign de `order_proofs` alheio cola no cartão de prova

**Lente:** BA4 (+ BA8 UI)  
**Actor:** buyer JWT (URL assinada obtida com JWT B2 — colisão / token roubado; B1 **não** consegue mintar o sign sozinho)  
**Pre:** order B1 `reserva_pendente`; B2 tem ficheiro `order_proofs/{B2}/{orderB2}/rtba-b2-secret.png`; B2 `POST /object/sign/...`.  
**Repro:** `POST chat_messages` kind `reservation_payment_submitted` `order_id`=order B1 `proof_url`=signed URL de B2.  
**Resultado:** HTTP 201 id=1281. Texto persiste com a URL. `GET` da URL: **S1 200 PNG 70 bytes · B1 200 · anon 200**. `GET` object **sem** sign com JWT S1 → 404/RLS. Order B1 continua `reserva_pendente` / `amount_paid_cents` null.  
**UI:** `_buildReservationPaymentSubmittedCard` mostra `Observações` + `BatataCachedNetworkImage(imageUrl: proofUrl)` / tap abre o diálogo — o vendedor **vê o comprovativo de outra pessoa**.  
**Impacto:** prova falsa no cartão de pagamento + publicação de ficheiro privado (sign = bearer, TTL app 7 dias). Não minta dinheiro.  
**Causa:** `assert_json_card` aceita qualquer `.../object/sign/fleaber_private/%` (ou `object/fleaber_private/%`); **não** exige `order_proofs/{buyer}/{order_id}/`.  
**Evidência:** `pass1.json` BA4.proof_url.sign_alheio; `pass2.json` p2.fetch.*; msg 1281.

--------------------------------------------------
## ACHADOS P2
--------------------------------------------------

### BA-P2-01 — Denylist de notes fura em rails novos / ordem valor→keyword / emoji €

**Lente:** BA1, BA2  
**Actor:** buyer JWT  
**Repro:** `reservation_payment_submitted.notes` = `Klarna 12,00 € confirmado` | `iDEAL 15 EUR aprovado` | `Twint pago 12 EUR` | `Klarna confirmado 12 💶` | `Afterpay 12,00 € confirmado` | `Google Pay 9 EUR aprovado`.  
**Resultado:** 201 (ids 1259, 1260, 1262, 1272 + pass2 Afterpay/GPay). Persistido.  
**Bloqueados (HOLD):** `Klarna confirmado 12,00 €` (keyword `confirmado` *depois* + `€`); `Bancontact recebido 9€` (`recebi`+€); `Multibanco 12€ pago` (substring `iban`); `Κlarna confirmado 12€` (mesmo `confirmado`+€).  
**Impacto:** cartão amarelo «O comprador confirmou o pagamento» + observações mentirosas. Order **não** passa a pago.  
**Evidência:** pass1 BA1.notes.* / BA2.notes.emoji_euro; pass2 p2.msg.*.

### BA-P2-02 — `seguro_fleaber_paid` label `Klarna` (rail gap)

**Lente:** BA1  
**Actor:** buyer JWT · order **paga** fixture (total 12.00 bate com `amount_paid_cents`)  
**Repro:** kind `seguro_fleaber_paid` `label=Klarna`.  
**Resultado:** 201 id=1264. Denylist de label ANAS (Wise/Revolut/Apple/…/MB WAY) **não** inclui Klarna. Recibo real da plataforma com método mentiroso.  
**Evidência:** pass1 BA1.seguro.label.klarna; pass2 p2.msg.1264.

### BA-P2-03 — `cancel_request_outcome.display` iDEAL

**Lente:** BA1  
**Actor:** seller JWT · outcome `rejected` em order paga  
**Repro:** `display=iDEAL 12 EUR aprovado — pedido recusado`.  
**Resultado:** 201 id=1265. `payment_lie_text` não pega iDEAL com valor **antes** de `aprovado`.  
**Evidência:** pass1 BA1.cancel.display.ideal; pass2 p2.msg.1265.

### BA-P2-04 — Inbox `last_message` Klarna / iDEAL / 💶 / Twint

**Lente:** BA5  
**Actor:** buyer JWT  
**Repro:** `PATCH chats last_message`.  
**Resultado:** cola `Klarna 12,00 € confirmado`, `iDEAL 15 EUR aprovado`, `Klarna confirmado 12 💶`, `Twint 9,99 € pago`.  
**HOLD:** `Κlarna confirmado 12€`; `Bancontact recebido 12 EUR`.  
**Impacto:** preview da lista de conversas mente pagamento.  
**Evidência:** pass1 BA5.inbox.*.

### BA-P2-05 — DELETE de cartão JSON com prefixo Hangul / Braille / ZWSP

**Lente:** BA5  
**Actor:** buyer JWT  
**Pre:** INSERT `\u3164` / `\u2800` / `\u200B` + `FLEABER_JSON_V1:{chat_image…}` — assert valida (strip Cf no check, **não** reescreve `NEW.text`). BOM é removido no INSERT; ZWSP fica.  
**Repro:** DELETE da própria row.  
**Resultado:** 200; row 1283/1284/1285 desaparecem. Guard de delete só faz `ltrim`+translate Zs/NBSP e `like 'FLEABER_JSON_V1:%'`.  
**Impacto:** cartão de sistema apagável se o prefixo visível ≠ `FLEABER_JSON_V1:`. Flutter `startsWith` também falha — a UI pode mostrar texto cru em vez do card; o furo é imutabilidade.  
**Evidência:** pass1 BA5.del.*; pass2 p2.del.1283=null.

### BA-P2-06 — `proof_url` `object/fleaber_private` path B2 (B1 sozinho, sem sign)

**Lente:** BA4  
**Actor:** buyer JWT  
**Repro:** URL `.../object/fleaber_private/order_proofs/{B2}/{orderB2}/…` sem token.  
**Resultado:** 201 no card. S1 GET object → 404. Cartão com link morto / prova unbound; **sem** leak de bytes.  
**Evidência:** pass2 BA4.p2.unsigned_object_alheio; BA6.p2.seller_get_unsigned_b2 BLOCKED.

--------------------------------------------------
## ACHADO P3
--------------------------------------------------

### BA-P3-01 — Plain text no thread (Klarna/iDEAL/💶/homoglyph/fullwidth/ZWJ)

**Lente:** BA2  
**Actor:** buyer JWT  
**Resultado:** INSERT 201. `payment_lie_text` **não** corre em texto plano (só notes/display/inbox + `forged_seguro_plain` exact «Compra paga através do Seguro Fleaber»).  
**Impacto:** bolha de chat, não cartão sistema. Higiene / mentira social.  
**Evidência:** pass1 BA2.plain.*.

--------------------------------------------------
## LENTES — O QUE SE PROVOU
--------------------------------------------------

### BA1 Cards — FALHA parcial (P2); kinds novos HOLD

| Variante | Resultado |
|---|---|
| kind `klarna_receipt` / `ideal_paid` | 403 `kind_denied` |
| kind `order_paid` JWT | 403 `server_only` |
| notes Klarna/iDEAL/Twint/Afterpay/GPay / 💶 | **201 P2** |
| notes Bancontact / Multibanco / Klarna+confirmado+€ | 400 `notes_forbidden` |
| `seguro_fleaber_paid` label Klarna | **201 P2** |
| `cancel_request_outcome` display iDEAL | **201 P2** |
| order unpaid após cards | continua `reserva_pendente` |

### BA2 Encoding — FALHA P2 notes emoji; P3 plain; homoglyph+€ HOLD

Greek Kappa + `confirmado 12€` bloqueado (regex ainda vê `confirmado`+€). 💶 fura. Fullwidth/ZWJ/dotless-i só em plain (P3).

### BA3 Cronologia — HOLD

`created_at` cliente → `now()`. PATCH `created_at` imutável. `last_message_time=2035` clamp.

### BA4 URLs — FALHA P1 sign alheio; resto HOLD

`chat_image` path alheio `path_denied`; path próprio + sign alheio `url_denied`; host `.evil` e `/render/image/sign/` `url_denied`; happy sign próprio 201. `authenticated/` alheio `url_denied`. Sign mint B1→path B2 404.

### BA5 Inbox/delete — FALHA P2

Preview rails novos; DELETE prefixos exóticos. NBSP exact **não** retestado (anti-atrofia).

### BA6 Storage — HOLD (directo)

Upload path B2 403 RLS. GET object B2 404. Insert own chat/proof 200.

### BA7 Cross-user chat — HOLD

INSERT/SELECT/PATCH/DELETE chat alheio 403 ou 200 [].

### BA8 Edge — HOLD

`ingest-ocr-reservation` 401 `missing_device_token`. `refund-order` 403. `create-payment-intent` `amount=1` + inject `order_paid` → 400 metadata (sem Session barata).

--------------------------------------------------
## CHECKLIST GPT (invariantes chat)
--------------------------------------------------

Poços: cards=SIM · encoding=SIM · cronologia=SIM · URLs=SIM · inbox/delete=SIM · storage=SIM · cross-user=SIM · Edge=SIM  
ATROFIA (só redescobriu núcleo fechado): NÃO

VEREDICTO: FAIL_P1
