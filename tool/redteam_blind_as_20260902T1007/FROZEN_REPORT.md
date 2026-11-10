# FROZEN_REPORT — RED TEAM CEGO AS

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 3
P2 aberto: SIM          → quantos: 3
P3 aberto: SIM          → quantos: 1  (fora de âmbito salvo pedido: NÃO — P3 documentado)
P4 aberto: NÃO          → quantos: 0
```

**VEREDICTO:** `FAIL_P1`

```
AUDITOR: REDTEAM_BLIND_AS_DISPUTA_POS_AHAM_v1
FROZEN_AT: 2026-09-02T10:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AS1, AS2, AS3, AS4, AS5, AS6, AS7, AS8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢; refund-order Edge executou refund TEST real; 2.ª Session após refund legítimo) · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Prefixo `RTAS-20260902T1007-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO (seller JWT sozinho não minta; o +5,00 € exigiu RPC de release com JWT do comprador, ou cron 48 h não esperado nesta ronda)
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 3
5. P2 hygiene encontrado — SIM
6. Quantos P2: 3
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (falsifica **receção/conclusão**, não a captura)
12. JWT cria saldo/fundos — SIM (RPC `batata_release_seller_wallet_for_order` JWT buyer após estado `concluido` forjado pelo seller: Δseller +5,00 €)
13. Refund excede captura — NÃO
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de poço)
16. Stock=1 duas vendas válidas — NÃO como exploit (2.ª Session só **depois** de refund Stripe real — caminho AHAM intencional)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (stock preso em `devolvida` até `stripe_refund_id`)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — SIM (order_proofs raso B1 lido por S1 e S2)
21. Buyer assume seller/admin — NÃO (`batata_admin_resolve_dispute` → «Apenas administradores»)
22. Seller assume buyer/admin — SIM no FSM (marca `entregue` / `concluido`); NÃO em disputa `resolvida`/`recusada`
23. Reviews forjadas — NÃO COMPROVADO (cron auto-feedback 48 h após `completed_at` — relógio arrancado, não esperado)
24. RPC SECURITY DEFINER perigoso executável — NÃO (admin / partial seller recusados)
25. RLS crítico quebrado — SIM (SELECT storage `order_proofs/{buyer}/ficheiro` sem `order_id`)
26. Edge confia total do cliente — NÃO (`refund-order` seller-only; gate `em_devolucao` 403)
27. Regressão funcional (happy path partido) — SIM (refund em `devolvida` reescreve status `cancelado`)
28. Saturação atingida — NÃO (cron 48 h não esperado; 2.ª captura 4242 não clicada — Session após refund é o caminho feliz)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Exactos AM/O da lista — **bloqueados / fechados AHAM**, não redescobertos como findings.

| Clássico AM/O | Resultado |
|---------------|-----------|
| seller `devolvida` → stock restore sem refund (AM3) | BLOCKED — qty 0, `stock_units_applied=1`, PI vivo |
| refund blocked shipped on `devolvida` (AM4) | FECHADO — `refund-order` 200, refund Stripe TEST `re_3UBAIb…` / `re_3UBAFs…` |
| S1 lê provas disputa B1–S2 (AM7) | BLOCKED — S1 404, S2 200 no path com `order_id` |
| `proof_photos` javascript: (AM7-P2) | BLOCKED em replies (`dispute_proof_url_denied`); INSERT disputa `javascript:` não retestado (já fechado) |
| INSERT disputa `resolvida` (AM3-P3) | BLOCKED em `pago` (RLS); trigger força `aberta` se chegasse a INSERT |
| seller PATCH disputa `resolvida` clássico | BLOCKED — status não muda |
| `pago`→`concluido` **directo** sem enviado | não usado como finding (anti-lista); o finding AS é o **degrau** `entregue` |
| OCR kick 1442 | não exercido |

Atrofia da lista: **0 / 8**. Não `ATROFIA_ABORT`.

AHAM confirmado no LIVE staging: stock não restaura em `devolvida` com captura viva; restaura quando chega `stripe_refund_id` (qty 0→1); refund-order em `devolvida` permitido; storage disputa exige `order_id`; INSERT `resolvida` não persiste em `pago`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P1-AS2 — Seller `pago`→`entregue` sem `enviado` (shipped_at null)

**Lentes:** AS2, AS1, AS8

**O que é:** `shipping_method` vazio **não** é mão (`batata_shipping_method_is_hand('')=false`). O comprador **não** pode `pago`→`concluido` em transportadora. O **vendedor JWT** faz `PATCH status=entregue` a partir de `pago`. Persistido. `shipped_at` continua null. A RLS de disputa (`entregue`/`concluido`) abre: buyer `POST order_disputes` → 201.

**Actor:** seller JWT (hop) · buyer JWT (disputa)

**Pré:** `setup_paid_order` Stripe TEST → `pago`, 590¢, shipping vazio.

**Repro (REST, Flutter não é fronteira):**
1. Seller `PATCH orders status=entregue` (a partir de `pago`)
2. Buyer `POST order_disputes`

**Esperado:** `entregue` só a partir de `enviado` (e pelo comprador); disputa só após envio real.

**Obtido:**
- pass1 `fa6f6531-…` status=`entregue`, `shipped_at` null, HTTP 200
- pass2 `2885467a-…` disputa `73061701-…` 201 com `shipped_at` null
- pass3 `0f4a4af7-…` o mesmo hop, depois `concluido`

**Porque P1:** caminho explorável para mentir a cronologia (nunca enviou) e abrir o poço disputa/conclusão. Não é o exacto `pago`→`concluido` clássico — usa `entregue` como degrau.

---

### P1-AS5/AS8 — Seller marca `concluido` (enviado **ou** sem envio) e o release credita 5,00 €

**Lentes:** AS5, AS8, AS2

**O que é:** O guard de seller **não** impede `PATCH status=concluido` a partir de `enviado` nem a partir de `entregue`. `completed_at` é selado (relógio de auto-feedback 48 h). `batata_release_seller_wallet_for_order` com JWT do **comprador** devolve `true` e credita a carteira do vendedor (+5,00 €; captura 5,90 €). O seller JWT sozinho **não** chama o release (a função exige `auth.uid()=buyer`). Flutter chama o RPC no fecho de disputa; cron `batata-auto-feedback-48h` (job `* * * * *`, filtro 48 h) também faz `perform` release se não houver disputa aberta.

**Actor:** seller JWT (estado) · buyer JWT (release nesta prova)

**Repro A (com envio):**
1. Seller `PATCH enviado` · `PATCH concluido`
2. Buyer `rpc batata_release_seller_wallet_for_order`

**Repro B (sem envio — composição AS2):**
1. Seller `PATCH entregue` · `PATCH concluido` (nunca `enviado`)
2. Buyer `rpc` release

**Esperado:** só o comprador confirma receção; sem `shipped_at` o release recusa.

**Obtido:**
| Order | Caminho | shipped_at | release | Δseller |
|-------|---------|------------|---------|---------|
| `a054d574-…` | enviado→concluido | set | `200 true` | **+5,00 €** |
| `0f4a4af7-…` | pago→entregue→concluido | **null** | `200 true` | **+5,00 €** (28,97→33,97) |
| `2885467a-…` | mesmo salto **com disputa aberta** | null | `200 false` | 0 |

PI pass3 `pi_3UBAKBH7FWYUN3jh1jxv2EsN` capturado 590¢, `stripe_refund_id` null após o crédito.

Após o release em `a054d574-…`, `POST order_disputes` do buyer → **403 RLS** (`wallet_release_processed_at` deixa de ser null). Quem perde a corrida da disputa fica sem via JWT.

**Porque P1 não P0:** o mint imediato usou JWT do comprador (auditor). Seller sozinho fica com estado `concluido` + `completed_at`; o dinheiro às 48 h via cron **não foi esperado**. Caminho explorável a dinheiro, não roubo instantâneo só-seller.

---

### P1-AS7 — Qualquer vendedor com histórico com B1 lê `order_proofs/{B1}/ficheiro` raso

**Lente:** AS7

**O que é:** A policy `fleaber_private_select_order_counterparty` ainda tem o ramo:

`order_proofs/{buyer_id}/%` **e** `NOT like …/{buyer}/%/%`

Ficheiros a **um** nível (sem `order_id`) são legíveis por **qualquer** seller que tenha uma order não cancelada com esse buyer. AHAM amarrou `order_disputes/…/{order_id}` — **não** este ramo de `order_proofs`.

**Não é o exacto AM7** (S1 a ler PNG de disputa B1–S2 com `order_id`). Deep path `order_proofs/{B1}/{orderS2}/…`: S1 404. Disputa com `order_id`: S1 404, S2 200.

**Actor:** seller JWT S1 · seller2 JWT S2

**Pré:** B1–S1 e B1–S2 têm orders. B1 `POST` `order_proofs/{B1}/rtas-p2-shallow.png`

**Repro:** `GET /storage/v1/object/fleaber_private/order_proofs/{B1}/rtas-p2-shallow.png`

**Esperado:** 403 — só o vendedor **da encomenda** do path.

**Obtido:** S1 **200** `binary:70b` · S2 **200** `binary:70b` · B2 404. Upload 200 `Id fad4ff3c-…`.

---

### P2-AS3 — Seller salta `em_devolucao` / `devolucao_entregue`

**Lente:** AS3

**O que é:** De `pedido_devolucao` o seller faz `disputa_devolucao_vendedor` → `devolvida` (200). O guard só exige `devolvida` a partir desses dois estados; não exige hops de envio de volta. Stock **não** restaura (AHAM OK). Depois `refund-order` funciona.

**Order:** `e67739cc-…` / `f09e0ba2-…` qty 0 applied 1 até refund.

**Porque P2:** FSM/prova de devolução; não oversell (stock preso até refund real).

---

### P2-AS4 — `refund-order` em `devolvida` reescreve `cancelado`

**Lente:** AS4

**O que é:** `batata_finalize_stripe_order_refund` faz `status='cancelado'` mesmo partindo de `devolvida`. Refund Stripe TEST sucede (`re_3UBAIbH7FWYUN3jh04BoQyKk`, 590¢). Stock restaura qty 0→**1** (não duplica). 2.ª Session B2 `cs_test_a1lvryTj…` 200 — caminho feliz pós-refund, não finding de oversell.

**Esperado:** terminal de devolução permanece `devolvida` (ou `reembolsada`).

**Obtido:** status `cancelado`, `already_refunded:true` no mesmo request (persistência cedo do `stripe_refund_id` + ramo idempotente).

**Porque P2:** ledger Stripe/stock coerentes; a UI/histórico mente (devolução vira cancelamento).

---

### P2-AS7 — `proof_photos` allowlist só exige prefixo `…/storage/%`

**Lente:** AS7

**O que é:** O trigger AHAM bloqueia `javascript:` / `data:` / URL externa. Aceita qualquer `https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/…`:

- INSERT `proof_photos=["https://…/storage/x\" onerror=\"alert(1)"]` → **201** (`0ab0ccca-…`)
- PATCH `…/storage/v1/object/public/chat_media/rtas.png` → **200**

**Porque P2:** XSS/phishing se a UI interpolar a URL; Flutter `Image.network` não executa JS. Não é dinheiro.

---

### P3-AS5 — Seller grava `return_delivered_at` sem prova

**Lente:** AS5

PATCH JWT seller `return_delivered_at=now()` → persistido (`dfc6edc0-…`). Sem trigger de hop de encomenda. Higiene.

--------------------------------------------------
## BLOQUEADO (defesa a funcionar / AHAM)
--------------------------------------------------

- JWT alheio / seller / anon insert disputa · disputa em `pago` e `enviado`
- `batata_admin_resolve_dispute` buyer → P0001
- INSERT 2.ª disputa após `recusada` → `dispute_already_exists_for_order` (design D1)
- Buyer `resolvida` com `buyer_decision` fake — status **não** fica `resolvida` se já `recusada`
- Seller `current_turn=administracao` revertido
- `seller_refund_percent=200` não persiste >100
- `return_label_url` public/chat_media recusada
- Fake `stripe_refund_id` / limpar PI → `order_money_fields_immutable`
- `refund-order` em `em_devolucao` → 403 `order_refund_blocked_shipped`
- Buyer `refund-order` → 403 Sem permissão
- Partial refund seller → `not_allowed`
- Release com disputa **aberta** → `false`, Δ 0
- `enviado` sem captura → `order_status_requires_capture`
- `shipping_method` pós-pago → `order_shipping_frozen_after_payment`
- Cancel pós-pago → `order_cancel_denied_post_pay`
- Replies `javascript:` → `dispute_proof_url_denied`
- AM7 disputa com `order_id` no path: S1 404 / S2 200
- AM3 stock em `devolvida` sem refund: qty 0

Buyer `PATCH recusada` é **design** (comentário D1: terminal só buyer JWT) — não finding.

--------------------------------------------------
## CONTABILIDADE (amostras)
--------------------------------------------------

| Sítio | Antes | Depois |
|-------|--------|--------|
| `0f4a4af7-…` pass3 | `pago` 590¢ shipped null | `concluido` shipped null · release true · seller 28,97→**33,97** |
| `a054d574-…` pass2 | `enviado` | `concluido` · release true · Δseller **+5,00** |
| `63fb8fac-…` refund | `devolvida` qty 0 applied 1 PI vivo | `cancelado` qty **1** applied null · `re_3UBAIb…` 590¢ · B2 Session 200 |
| `e67739cc-…` shortcut | `pedido_devolucao` | `devolvida` qty 0 applied 1 (AHAM) |

Wallets B1 estáveis ~61,10 excepto onde o release vendedor correu.

--------------------------------------------------
## TÁCTICAS
--------------------------------------------------

1. ≥1 order Stripe TEST paga: SIM (PI `succeeded` 590¢ × várias)
2. Envio → disputa → devolução: SIM (`enviado` → `entregue` → disputa → `pedido_devolucao` → `devolvida` → refund)
3. Contabilidade wallets + stock + status: SIM
4. Flutter ≠ fronteira: SIM (REST/Edge/RPC/Storage)

Lentes AS1–AS8 cobertas (≥4).
