# FROZEN REPORT — RED TEAM CEGO AO
## Auditor independente · PÓS-FECHO AHAM · CHAT / PROVAS / UI · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 5
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AO_CHAT_POS_AHAM_v1
FROZEN_AT: 2026-09-02T09:20:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AO1, AO2, AO3, AO4, AO5, AO6, AO7, AO8]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT buyer `bfcbeeee-…` · seller `980f4fa1-…` · buyer2 `8280a8cd-…`.  
`service_role` só fixture (`setup_paid_order`, GET evidência, cleanup mensagens). Prefixo `RTAO-20260902T1005-`.  
Provas: `pass1.json`, `pass2.json`. Repro: `dart run tool/redteam_blind_ao_20260902T1005/pass1.dart` (+ `pass2.dart`).

**Missão.** Depois do fecho AHAM no chat, ainda forjo recibo, mento MB WAY/disputa/cancel/review/oferta, ou injecto URL/prova falsa — sem mint directo?

**Resposta.** Sim, no poço de higiene: o denylist de «mentira de pagamento» cobre Reembolso/PayPal/PIX/MB WAY+€, mas o vendedor grava um card de cancelamento com `display: "Refund 50 EUR processed"` e o comprador grava `notes: "Wise 50€ já caiu"` / label `Wise` no card Seguro / preview da inbox `Wise 50€`. O cliente mostra esses campos. `chat_image.url` aceita qualquer path `…supabase.co/storage/%` (bucket public). Dinheiro e estado da encomenda não se mexeram (`status=pago`, `amount_paid_cents=590`, sem refund).

Controlos exactos AHAM (display Reembolso, notes Reembolso, inbox PayPal 50€, ZWSP intra-keyword, signed `/storage/v1/object/sign/fleaber_private/`) **bloqueados**. Não é ATROFIA_ABORT (0/7 classes = payloads exactos da lista AI/AF/Z).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 5
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (fora do poço; não re-provado)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (card Seguro exige `amount_paid_cents` alinhado; label/notes mentem na UI sem mint)
12. JWT cria saldo/fundos — NÃO (`status`/`amount_paid_cents` iguais após INSERTs; wallets tabela sem linha lab)
13. Refund excede captura — NÃO COMPROVADO (fora da lente)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 GET `chat_messages` 200 []; B2 PATCH inbox 200 [] sem mutar; B2 INSERT 403; B2 signed prova B1 404)
21. Buyer assume seller/admin — NÃO (`cancel_request_outcome` seller-only 403)
22. Seller assume buyer/admin — NÃO (`seguro_fleaber_paid` buyer-only 403)
23. Reviews forjadas — NÃO (`kind` allowlist; `order_review_submitted` não exercitado com stars fake — classe já saturada noutros poços)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO (poço chat)
25. RLS crítico quebrado — NÃO (mensagens/notificações/storage path alheio)
26. Edge confia total do cliente — NÃO (`chat_text` no checkout 400 status pago)
27. Regressão funcional (happy path partido) — NÃO (notes benignas 201; signed proof correcto 201; setup_paid_order 200)
28. Saturação atingida — NÃO (P2 abertos; rails Venmo/SEPA/MbNet não esgotados; `chat_image` render/image não aprofundado)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P2 · AO1-01 cancel display keyword-gap

**Lentes:** AO1  
**Actor:** seller JWT  
**Msgs:** `1200`–`1205` (GET `1200` no pass2)

**O quê:** `cancel_request_outcome` + `outcome=rejected` (encomenda continua `pago`) aceita `display` com mentira de dinheiro desde que a keyword **não** esteja no denylist AHAM. O Flutter (`_buildCancelOutcomeFromPayload`) mostra `display` tal como veio.

Payloads 201: `Refund 50 EUR processed` · `Estorno 50€ feito` · `Devolução 50,00 € na conta` · `Remboursement 50 €` · `Chargeback 50 EUR` · `Rеembolso 50 EUR` (U+0435 cirílico).

Controlo exacto `Reembolso 4321 EUR processado` → `chat_system_card_display_forbidden`.

**Não é** o P2-01 exacto AHAM. Sem mint (`stripe_refund_id` null, status `pago`).

---

### P2 · AO1-02 notes rail-gap

**Lentes:** AO1  
**Actor:** buyer JWT  
**Msg:** `1206` persistida

**O quê:** `reservation_payment_submitted.notes` aceita comprovativo mentiroso em rails fora do regex (`Wise 50€ já caiu`, `Revolut 12,00 € confirmado`, `Apple Pay 20€`, `MВ WAY 50€` com В cirílico). Flutter mostra «Observações: …».

`Multibanco 50€ pago` foi **bloqueado** (live). Controlo `Reembolso 4321 €` → `notes_forbidden`.

---

### P2 · AO1-03 seguro label-gap

**Lentes:** AO1  
**Actor:** buyer JWT  
**Msg:** `1212` / `1213`

**O quê:** `seguro_fleaber_paid` com `total` igual ao pago (5,90 €) aceita `label: "Wise"` e `label: "Pago no MB"`. O card acrescenta ` · $label` à linha «Paga através do Seguro Fleaber». AHAM só recusa label com keywords Seguro/PIX/MB WAY/… sem dígitos (ou com montante errado).

Ordem **está** paga — a mentira é o **método** no card, não um Seguro inventado do zero.

---

### P2 · AO4-01 chat_image public URL

**Lentes:** AO4  
**Actor:** buyer JWT  
**Msg:** `1238` persistida

**O quê:** `kind=chat_image` exige `path` em `chat_uploads/{sender}/…` mas `url` só precisa `https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%`. Gravado:

`url=https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/public/avatars/x.png`

O cliente (`_chatImageUrlFromMessage`) usa `url` se começar por `http`. `javascript:` e `..` no path recusados. Signed `fleaber_private` no formato `/storage/v1/object/sign/…` aceite (AHAM HOLD).

---

### P2 · AO5-01 inbox preview keyword-gap

**Lentes:** AO5  
**Actor:** buyer JWT (participante)

**O quê:** `PATCH chats.last_message` recusa `PayPal 50€` (`chat_inbox_preview_forbidden`) mas aceita e persiste: `Wise 50€` · `Revolut 12€ confirmado` · `MB WAY aprovado` (sem dígitos; 2.º regex pede confirmado|banco|recebido) · `Pagamento recebido` · `Transferência confirmada` · `Recebi no Wise`. GET pass2: `last_message=Recebi no Wise` (depois restaurado na cleanup).

B2 no mesmo chat: PATCH 200 `[]` — **sem** mutação (não é P1).

---

### P3 · AO5-02 DELETE bolha NBSP+prefixo

**Lentes:** AO5 · AO2  
**Actor:** seller JWT

**O quê:** texto `U+00A0 + FLEABER_JSON_V1:{…}` grava-se como bolha (cliente não faz parse — `startsWith` exacto). `guard_delete` só imutabiliza `like FLEABER_JSON_V1:%` ou `btrim {`. DELETE JWT removeu a linha. Não é card oficial; é apagar JSON «quase-sistema».

Prefixos Zs/tab/fullwidth/lower: bolha crua, não card. Newline/BOM após prefixo: JSON válido benigno (não counted P2).

---

### P3 · AO4-02 notes HTML

**Lentes:** AO4  
**Actor:** buyer JWT  
**Msg:** `1241`

**O quê:** `notes: "<img src=x onerror=alert(1)> ver comprovativo"` 201. Flutter `Text()` não executa HTML. Persistência em card de sistema, sem XSS.

--------------------------------------------------
## HOLD / FALSO POSITIVO (não counted)
--------------------------------------------------

| ID | Notas |
|----|--------|
| CTRL display/notes/inbox exactos | 400/403 como AHAM |
| ZWSP intra `Reembolso` | strip Cf → `display_forbidden` / `notes_forbidden` |
| signed URL correcto | 201 |
| `created_at=2020` INSERT | forçado `now()` |
| PATCH `created_at` | **200 silencioso**, BD continua 2026-09-02 |
| B2 INSERT/GET thread | 403 / 200 `[]` |
| B2 PATCH inbox | 200 `[]`, last_message inalterado |
| B2 sign/upload path alheio | 403/404 |
| upsert prova | 403 RLS |
| seller→seguro / buyer→cancel outcome | 403 role |
| `kind` fora allowlist | 403 |
| Unicode pad + «Compra paga através do Seguro Fleaber» | 403 `chat_seguro_legacy_plain_forbidden` (live mais apertado que `^\s*` no SQL de repo) |
| `kind=\u0073eguro_fleaber_paid` | 201 em encomenda **já paga** — card legítimo, não forge |
| livros | `pago` / 590 ¢ / refund null depois de todos os INSERTs |
| Edge `chat_text` | 400 cannot start payment |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| AO1 Cards vs BD | **FALHA P2** display/notes/label |
| AO2 Prefixo / encoding | HOLD no Cf; P3 bolha+DELETE; Zs não vira card |
| AO3 Cronologia | HOLD (clamp / now()); PATCH 200 sem mutar |
| AO4 URLs / provas | **FALHA P2** chat_image public; proof_url hostil HOLD; signed HOLD |
| AO5 Inbox / delete | **FALHA P2** preview; JSON card imutável HOLD; DELETE NBSP P3 |
| AO6 Storage | HOLD path/upsert/sign cruzado |
| AO7 Cross-user | HOLD RLS mensagens; PATCH 200 vazio |
| AO8 Edge vs chat | HOLD sem mint |

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Lista exacta proibida (cancel display Reembolso, PIX sem dígitos, notes Reembolso, inbox PayPal/Bizum, signed denied, product_ids decoy, ZWSP+prefix, FF/VT/Ogham, raw `{`, fleaber.app): **0** findings. Controlos dessa lista foram BLOCKED. Variantes = rails/keywords/campos novos e `chat_image.url` public.

--------------------------------------------------
## FIXTURES
--------------------------------------------------

- Order pago `2a975658-318c-4482-9ea5-25e37e37f42a` PI `pi_3UBAFJH7FWYUN3jh0yafuU3k` 590 ¢ — deixada `pago` (sem refund).
- Chat lab `ac2902d3-a3ca-4f82-b7de-2532db9cafba` — mensagens RTAO apagadas no cleanup; `last_message` = `RTAO audit ended`.
- Buyer2 `8280a8cd-…` conta descartável.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
