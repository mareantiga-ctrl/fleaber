# FROZEN_REPORT — REDTEAM_BLIND_AU_CHAT_POS_ANAS_v1

AUDITOR: REDTEAM_BLIND_AU_CHAT_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:17:44+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AU1, AU2, AU3, AU4, AU5, AU6, AU7, AU8]
VEREDICTO: FAIL_P2

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 4
P3 aberto: SIM          → quantos: 3  (fora de âmbito salvo pedido)
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 7
```

**VEREDICTO:** P0–P1 fechados + P2 aberto → `FAIL_P2`.

Anti-atrofia: 0 achados = lista exacta AO-P2-01…05 / AI Reembolso-PayPal / NBSP+DELETE / notes HTML / chat_image public. Variantes **novas**: Klarna, Sofort, iDEAL, cartão, Google Pay, Alipay, Twint, Multibanco, homoglyphs ѕ/ο/ｓ/ſ/Κ, Hangul/Braille prefix, `object/authenticated` outro bucket, inbox emoji 💶/💰/💳, PATCH `created_at`.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 4
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 3
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (mint `seguro_fleaber_paid` sem captura 400 `order_not_paid`; PATCH `payment_method`/`amount_paid_cents` 403 `order_money_fields_immutable`). UI/cards **mentem o rail** (P2) sem alterar a encomenda.
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (fora de foco chat)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de foco)
16. Stock=1 duas vendas válidas — NÃO (fora de foco)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 GET thread 200 []; INSERT 403 RLS; PATCH inbox 200 [] sem mutar)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO (não exercido nesta ronda)
25. RLS crítico quebrado — NÃO (chat + storage prefixo alheio 403)
26. Edge confia total do cliente — NÃO (controlo AU8: card pago exige captura)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (8/8 lentes AU; variantes novas além da lista AO/AI)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `pi_3UBFskH7FWYUN3jh1HbeVgVV`, order `a59b6d29-bf9f-4932-a908-3238d356ee6f`, `amount_paid_cents=590`, status `pago`) · JWT buyer/seller + buyer2 admin fixture · `service_role` só fixture/observe/cleanup.

Prefixo: `RTAU-20260902T1608-`.

Chat B1–S1: `ac2902d3-a3ca-4f82-b7de-2532db9cafba`.  
Order reserved (pass2): `e64d67f8-0c78-48d2-b5cc-816b65e58a03` status `reserva_pendente`.  
Inbox restaurado no fim: `last_message=RTAU audit ended`.

Código estudado (não relatórios AO/AI/AF/ANAS): `batata_chat_payment_lie_text`, `batata_chat_messages_guard_image_url`, `batata_chat_messages_assert_json_card`, `batata_chat_is_forged_inbox_preview`, `batata_chat_messages_guard_update/delete`, `lib/chat_page/chat_page_widget.dart` (`labelBit`, notes, display, `_chatImageUrlFromMessage`).

--------------------------------------------------
## ACHADOS P2
--------------------------------------------------

### AU-P2-01 — Card «Seguro Fleaber» aceita label de rail inventado (Klarna / 999 €)

**Lente:** AU1  
**Actor:** buyer JWT  
**Pre:** encomenda **realmente paga** Stripe TEST 5,90 € (`amount_paid_cents=590`). Denylist ANAS do `label` cobre Wise/Revolut/Apple/Venmo/SEPA/MBNet/PayPal/Bizum/MB WAY/PIX/«pago no mb»/transfer — **não** Klarna, Sofort, iDEAL, cartão, Google Pay, Alipay, Twint, Multibanco. O check de `assert_json_card` só valida dígitos do label se bater `(Seguro|PIX|MB WAY|Compra paga|Transferência|Pagamento)`.  
**Repro:** `POST chat_messages` `kind=seguro_fleaber_paid` `order_id=<pago>` `total=5.9` `label=Klarna 999.00€` (e variantes Sofort/iDEAL/Cartão/Google Pay/…).  
**Resultado:** HTTP **201**. Linha persistida id **1289**:

`FLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","order_id":"a59b6d29-…","total":5.9,"label":"Klarna 999.00€"}`

**UI:** `secondaryLine` = «Paga através do Seguro Fleaber · 5,90 € · Klarna 999.00€». O total do card vem do payload (bate com a captura); o **label mente o método e um segundo montante**. Encomenda na BD inalterada (`payment_method=Pagamento na app`).  
**Impacto:** mentira de método/recibo no card oficial de pagamento plataforma. Sem mint.  
**Evidência:** `pass1.json` AU1.seguro.label.*; `pass2.json` nota `p2.klarna999`.

### AU-P2-02 — Observações do comprovativo MB WAY: Klarna/Sofort/iDEAL/cartão

**Lente:** AU1  
**Actor:** buyer JWT  
**Pre:** order `reserva_pendente` `e64d67f8-…` sem captura. `batata_chat_payment_lie_text` exige rails da denylist + montante/confirmado — **Klarna não está na regex**.  
**Repro:** `POST kind=reservation_payment_submitted` `notes=Klarna 50€ confirmado` (também Sofort, iDEAL, «Pago com cartão 18.50€», Google Pay).  
**Resultado:** HTTP **201** ids 1320–1324.  
**UI:** `_buildReservationPaymentSubmittedCard` mostra `Observações: $notes` no card amarelo de «já pagaste».  
**Impacto:** comprovativo de pagamento off-platform com rail e montante forjados.  
**Evidência:** `pass2.json` AU1.notes.*.

### AU-P2-03 — Cancel outcome `display` Klarna 99 €

**Lente:** AU1  
**Actor:** seller JWT  
**Pre:** mesmo order reserved; `outcome=rejected` (estado não cancelado). `display` só é barrado se `payment_lie_text` (sem Klarna).  
**Repro:** `POST kind=cancel_request_outcome` `outcome=rejected` `display=Klarna 99€ confirmado`.  
**Resultado:** HTTP **201** id **1325**.  
**UI:** `_buildCancelOutcomeFromPayload` pinta o `display` como texto do sistema.  
**Impacto:** bolha de sistema a afirmar pagamento/rail que a plataforma não viu.  
**Evidência:** `pass2.json` AU1.cancel.klarna-display.

### AU-P2-04 — Inbox `last_message` Klarna / emoji € sem dígitos

**Lente:** AU5  
**Actor:** buyer JWT (participante)  
**Pre:** `batata_chat_is_forged_inbox_preview` = payment_lie **ou** `(wise|…|pagamento|recebi).{0,40}(confirmado|€|eur|\d)`. «Klarna confirmado» não tem essas keywords. `Recebi 💶` — 💶 ≠ `€`.  
**Repro:** `PATCH chats last_message=Klarna confirmado` (e Sofort feito, iDEAL caiu, cartão aprovado, Google Pay processado, Recebi 💶, Pagamento 💰, Recebi 💳); GET service.  
**Resultado:** last_message **persistiu** cada variante (GET confirmou igualdade). B2 **não** conseguiu (ver lentes).  
**UI:** lista de conversas mostra `chats.last_message` cru.  
**Impacto:** preview da inbox mente pagamento sem card JSON.  
**Evidência:** `pass1.json` AU5.inbox.*; pass2 observou `Recebi 💳` ainda colado antes do restore.

Homoglyph extra (mesma classe que P2-01, não conta à parte): label `Κlarna` (Greek kappa U+039A) também **201**.

--------------------------------------------------
## ACHADOS P3
--------------------------------------------------

### AU-P3-01 — Prefixo Hangul/Braille/Choseong foge ao assert e ao DELETE

**Lente:** AU2 / AU5  
**Actor:** buyer JWT  
**Pre:** `assert_json_card` só trata texto que começa por `FLEABER_JSON_V1:` (após strip Cf/BOM). `strip_unicode_ws` não remove U+3164 / U+2800 / U+115F. `guard_delete` ANAS só traduz NBSP + Zs.  
**Repro:** `POST` text=`U+3164`+`FLEABER_JSON_V1:{seguro…label Klarna}`; depois `DELETE id`.  
**Resultado:** INSERT **201**; DELETE **200** removeu a linha.  
**UI:** `startsWith('FLEABER_JSON_V1:')` falha → não vira card; pode aparecer JSON cru com filler invisível.  
**Impacto:** imutabilidade do card só no prefixo exacto; não é mentira de pagamento na UI de card.  
**Evidência:** pass1 AU2.prefix.* / AU5.delete.hangul-filler-json.

### AU-P3-02 — URL `object/authenticated` de outro bucket + path no query

**Lente:** AU4  
**Actor:** buyer JWT  
**Pre:** ANAS exige `sign/` ou `authenticated/` no host do projecto, **sem** restringir bucket; bypass de path se `position(path in url)>0`.  
**Repro:** `POST chat_image` path=`chat_uploads/{buyer}/{chat}/rtau.png` url=`…/object/authenticated/avatars/rtau.png?p=chat_uploads/…`.  
**Resultado:** **201** id 1312; URL hostil persistida. Bucket `avatars` nem existe (404 no PUT); o texto mesmo assim ficou.  
**UI:** `_chatImageUrlFromMessage` **prefere path** `chat_uploads/` e re-assina `fleaber_private` — a URL avatars **não é mostrada**.  
**Impacto:** hygiene de payload; não prova falsa visível neste cliente.  
**Evidência:** pass1 AU4.image.authenticated-avatars; pass2 `p2.auth-avatars`.  
`sign/avatars` **sem** path no query → 400 `chat_system_card_url_denied` (fecho ANAS aguentou nesse eixo).

### AU-P3-03 — Texto `https://…/recibo-klarna-50eur.png` vira bolha de imagem

**Lente:** AU4  
**Actor:** buyer JWT  
**Pre:** legado `_chatImageUrlFromMessage`: HTTP + extensão `.png` (sem `FLEABER_JSON_V1`).  
**Repro:** `POST text=https://example.com/recibo-klarna-50eur.png`.  
**Resultado:** **201**.  
**UI:** promove a bolha de imagem (qualquer CDN).  
**Impacto:** partilha de link de imagem, não card de sistema; recibo falso possível como foto de chat.  
**Evidência:** pass1 AU4.legacy-http-png-bubble.

--------------------------------------------------
## RETRACTADOS (não entram na CONTAGEM)
--------------------------------------------------

- **AU2.kind.ascii-s-kind** (`\u0073eguro_fleaber_paid`): é o kind real `seguro_fleaber_paid` + order paga + total correcto + label `Pago`. 201 esperado. Não é homoglyph.
- **AU7.b2.patch-inbox** pass1 (P1): PATCH HTTP 200 `[]`. Pass2 GET: `last_message` **não** mudou para o texto B2. Falso positivo.

--------------------------------------------------
## LENTES — O QUE SE PROVOU
--------------------------------------------------

### AU1 Cards vs BD — P2 rail-gap

| Variante nova | Resultado |
|---|---|
| seguro label Klarna / Klarna 999.00€ / Sofort / iDEAL / Cartão / Google Pay / Samsung Pay / Alipay / Giropay / Bancontact / Twint / Multibanco | **201** persistido |
| notes Klarna/Sofort/iDEAL/cartão/Google Pay | **201** |
| cancel display Klarna 99€ | **201** |
| Kind homoglyph ѕ/ο/ｓ/ꜱ/ſ | **403** `kind_denied` |

### AU2 Prefixo / encoding — HOLD no kind; P3 prefixo invisível

Kind allowlist exacta aguentou. Fullwidth/Greek em notes não corridos no reserved do pass1 (fixture 23514); pass2 notes ASCII Klarna já P2. Prefixo Hangul/Braille/Choseong = P3.

### AU3 Cronologia — HOLD

INSERT `created_at=2020` → gravado **2026-09-02T15:15:26Z** (clamped).  
PATCH `created_at=2019` → 200 mas valor inalterado (`NEW.created_at := OLD.created_at`).

### AU4 URLs / provas — HOLD public/sign-sem-query; P3 authenticated+query

`object/public` não retestado (lista AO). `sign/avatars` sem path ⊂ url → denied. `authenticated/avatars`+query → persistido, UI ignora. `proof_url` não retestado no pass2 (reserved chegou tarde; pass1 reserved falhou).

### AU5 Inbox / delete — P2 inbox; P3 DELETE Hangul

Inbox rails novos + emoji € = persistido. DELETE Hangul+JSON = removeu. B2 não apaga/altera inbox alheio.

### AU6 Storage — HOLD

PUT `chat_uploads/{b2}/…` com JWT buyer → 403 RLS.  
B2 sign path do buyer → 404/denied.  
Buckets svc: `chat_media` (public) + `fleaber_private`.

### AU7 Cross-user — HOLD

B2 GET mensagens **200 []**. INSERT 403 RLS. PATCH inbox 200 [] sem mutação (verificado GET).

### AU8 Edge vs chat — HOLD mint

`seguro_fleaber_paid` em order `reserva_pendente` → 400 `chat_system_card_order_not_paid`.  
PATCH order `payment_method=Klarna` `amount_paid_cents=1` → 403 `order_money_fields_immutable`; BD ficou `Pagamento na app` / 590.

--------------------------------------------------
## FALSO POSITIVO EVITADO
--------------------------------------------------

Pass1 `insertReserved` com `is_reservation=true` + `MB WAY` + `aguarda_pagamento` → 400 23514. Pass2 sem esses campos (`reserva_pendente` + `Pagamento na app`) → 201. Notes/cancel/AU8 unpaid só válidos a partir do pass2.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_au_20260902T1608/pass1.dart` + `pass1.json`
- `tool/redteam_blind_au_20260902T1608/pass2.dart` + `pass2.json`
- `tool/redteam_blind_au_20260902T1608/_rtau.dart`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
