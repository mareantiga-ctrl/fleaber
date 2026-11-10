AUDITOR: REDTEAM_BLIND_X_LIVE_MANUAL_STAFF_v1
FROZEN_AT: 2026-09-01T13:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [X1, X2, X3, X4, X5, X6, X7, X8]
VEREDICTO: FAIL_P1

Ambiente: staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST não liquidado (poço sem captura) · prefixo `RTX-20260901T1301-`
Actors: buyer · seller · helper/staff · view-helper · seller2 · buyer2
service_role: só fixture (lives, products, users) e SELECT
Pasta: `tool/redteam_blind_x_20260901T1301/`
Probes: `pass1.dart` · `pass2.dart` · `pass3.dart`

--------------------------------------------------
MISSÃO
--------------------------------------------------
No directo (Facebook/manual/staff), consigo marcar vendido sem dinheiro,
roubar stock, ou sabotar a live de outro?

--------------------------------------------------
FINDINGS PROVADOS
--------------------------------------------------

### RTX-X1-fb-convert-no-pi · P1 · X1 / X2 / X8

**Título:** `convert` em `facebook_manual` e `helper_manual` não exige encomenda paga; consome capacidade do artigo live.

**Actor:** seller JWT; helper JWT com `can_manage_reservations`

**Pré:** live `status=live`. Artigo `live_only` qty≥1. Reserva `source=facebook_manual` (ou `helper_manual`) em `accepted` (ou `pending` com stock). Zero `orders` / PI / Δwallet.

**Repro:**
1. Seller (ou helper) POST `live_reservation_requests` `source=facebook_manual` `status=pending`.
2. Trigger força `pending` mesmo se o cliente mandar `accepted`.
3. RPC `batata_process_live_reservation_request` `p_action=accept`.
4. RPC `p_action=convert`.

**Esperado:** `convert_requires_paid_order` também nestes `source`, **ou** convert sem consumir capacidade.

**Obtido:**
- `fleaber_live` convert sem PI → `ok:false convert_requires_paid_order` (controlo).
- `facebook_manual` convert → `ok:true`, `status=converted`. Request `275f205a-36c0-43b1-aa4c-54a571720acf`, item `834fd6af-daa6-4128-85f9-e08585a75ff0`.
- `helper_manual` convert JWT helper → `ok:true`, request `28451b16-3f71-4763-be78-eb0b75bd0334`.
- `orders` ligados ao live_item: **0**. `seller_wallet_delta=0`.
- SQL actual: o gate `convert_requires_paid_order` só corre se `source in ('fleaber_live','')`.

**Impacto:** o staff/vendedor marca unidades **converted** (somadas em `reserved_qty` / `sold_converted_qty`) sem Stripe e sem encomenda. Bloqueia o saco in-app nessas unidades. **Não** mint carteira. SKU marketplace no mesmo fluxo **não** converteu (`live_item_qty_below_reservations` / `qty_exceeds_stock`) — o furo é o canal manual/`live_only`, não o catálogo pago.

**Classe irmã (não contar como P1 extra):** `RTX-X2-helper-convert-fb`, `RTX-X8-helper-manual-convert-no-pi`.

---

### RTX-X2-helper-inflate-qty · P1 · X2 / X3

**Título:** Helper com só `can_manage_reservations` altera `live_items.quantity` (GET confirma).

**Actor:** helper JWT (`seller_helpers` aceite, perms `can_manage_reservations` + `can_view_live_dashboard`)

**Pré:** convite aceite. Artigo `live_only` qty=2, ref `XH3`, live do seller1. Helper **sem** `can_mark_items_sold`.

**Repro:**
1. PATCH `live_items?id=eq.<item>` `{quantity:40}` JWT helper.
2. GET `live_items` (service_role observação).

**Esperado:** RLS só dono da live; `can_manage_reservations` ≠ stock.

**Obtido:** HTTP 200 com representação. Row `c008e232-dd4d-40fb-b433-689ef5f9f8a1` `quantity=40`.
- `batata_mark_live_item_sold` JWT helper → `not_allowed` (perm `can_mark_items_sold` HOLD).
- Trigger `batata_live_items_guard_authority` deixa passar staff com `can_manage_reservations`.

**Impacto:** o assistente **inventa stock** no directo. Composto com X1: depois `accept`/`convert` facebook_manual nessas unidades **sem dinheiro** (provado no dono em pass2: qty 1→8, `available_qty` 1→8, accept qty=5 `ok`). Não é cross-seller: 2.º seller PATCH devolveu `200 []` **sem** mutação (qty 3→3).

---

### RTX-X1-fb-buyer-id-arbitrary · P2 · X1

**Título:** Seller/staff grava `buyer_id` de outro perfil numa reserva `facebook_manual`.

**Actor:** seller JWT

**Pré:** live A activa.

**Repro:** POST `live_reservation_requests` `buyer_id=<seller2>`.

**Obtido:** 201, row `3a30315d-d21d-41f9-8a4d-be50e5905736` `buyer_id=bc4773fe-…` (seller2). Sem convert nesta row.

**Impacto:** identidade walk-in forjada no livro do directo. Sem encomenda/caixa neste passe.

---

### RTX-X3-inflate-then-accept-over-original · P2 · X3

**Título:** Dono PATCH `live_items.quantity` a meio do directo: `total_qty` 1→8 e accept facebook_manual qty=5.

**Actor:** seller JWT (dono)

**Obtido:** `available_qty` 1→8; accept `ok`, `reserved_qty=5`. Item `52e19b4f-9ca6-4bfc-bb2f-a8dcd1934c67`.

**Impacto:** restock do dono (não é roubo alheio). Agrava X2 se o helper fizer o mesmo PATCH. Downgrade vs helper: P2 operacional no dono.

---

### RTX-X3-mark-sold-no-convert · P2 · X3

**Título:** Dono `batata_mark_live_item_sold` sem convert e sem PI.

**Actor:** seller JWT. Buyer JWT → `not_allowed`.

**Obtido:** `ok:true` no item B1 `f9940c6d-31c3-404c-98ea-4d6193a20835`. Ops de estúdio, não caixa.

---

### RTX-X3-convert-from-pending · P2 · X3

**Título:** `convert` a partir de `pending` (sem `accept`) quando ainda há folga de stock.

**Obtido:** request `6eb865c8-5cbb-4169-97d4-c6b02b012a48` → `converted`. Over-qty pending qty=4 em qty=1 → `qty_exceeds_stock` (HOLD). Race dois convert qty=1 → nenhum converted (`live_item_qty_below_reservations`).

---

### RTX-X5-mux-draft-token · P3 · X5

**Título:** Dono obtém token LiveKit publish numa live `draft`.

**Actor:** seller JWT na própria live `7cc8c89d-6a1f-43dc-a0a8-29245e80861a`.

**Não é token alheio.** Buyer / seller2 / helper → 403 `Sem permissão para esta live`. `create-mux-live` buyer → 403 vendedor-only. `complete-mux-live` / `stop_egress` seller2 → 403.

--------------------------------------------------
FALSOS POSITIVOS RETIRADOS
--------------------------------------------------

| ID pass1 | Motivo |
|----------|--------|
| RTX-X7-s2-patch-item-qty P0 | PostgREST `200 []` = 0 rows. GET: qty 3→3. |
| RTX-X8-mkt-still-listed-after-fb-convert P1 | Convert marketplace **falhou** (`qty_exceeds_stock`). Listado porque não converteu. |

--------------------------------------------------
HOLD / BLOQUEADO (amostra)
--------------------------------------------------

- Buyer INSERT `facebook_manual` → RLS 42501.
- INSERT `accepted` forçado a `pending`.
- `live_item_id` NOT NULL.
- Helper não alarga `permissions` (trigger SEC-014).
- Seller2 não se insere como staff da loja A.
- View-helper convert → `not_allowed`.
- Helper INSERT/convert na live seller2 → `reservation_buyer_mismatch` / `not_allowed`.
- PATCH `requested_qty` após accept > stock → `qty_exceeds_stock`.
- `live_item_live_mismatch` / `live_item_live_id_immutable` (não re-auditar classe Q/T).
- Mesmo `product_id` / mesmo `ref_code` em duas lives: segundo convert recusado.
- Seller2 INSERT item na live A → `live_item_not_authorized`.
- Seller1 processa reserva seller2 → `not_allowed`.
- INSERT `orders` `status=pago` após convert → coerido a `reserva_pendente` (sem PI).
- Rifa: `batata_draw_live_raffle_winners` seller2/helper → `not_allowed`. Share seller2 → `join_required`.
- Wallets buyer/seller inalteradas em todos os passes (18.97 / 61.1).

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| X1 facebook_manual | P1 convert sem PI; P2 buyer_id; INSERT buyer/null-item HOLD |
| X2 Staff helper | P1 inflate qty; convert FB = X1; cross-seller HOLD; widen perms HOLD |
| X3 Qty / sold | P2 inflate dono + mark_sold + convert pending; race HOLD |
| X4 Cross-live | mismatch/immutable/pool HOLD |
| X5 Mux / publish | token alheio HOLD; draft dono P3 |
| X6 Rifa / share | caminho exercitado; draw/share foreign HOLD |
| X7 2.º seller | sabotage stock/accept HOLD (P0 pass1 falso) |
| X8 Composição caixa | convert não cria order pago nem Δwallet; helper_manual = X1 |

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Não parou em: spoof `seller_id` exact · `live_item_live_mismatch` exact · `convert_requires_paid_order` exact em `fleaber_live` · `stop_egress` foreign exact.

≥50% findings nessas classes? **NÃO.**

--------------------------------------------------
CHECKLIST
--------------------------------------------------

1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: SIM
4. Quantos P1: 2 (X1 convert manual sem PI · X2 helper inflate qty)
5. Buyer manipula preço autoritativo: NÃO (fora do poço)
6. Buyer manipula qty autoritativa: NÃO COMPROVADO neste poço
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO COMPROVADO (poço sem captura)
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer: NÃO (fora do poço R)
12. Stock=1 duas vendas válidas: NÃO (convert manual ≠ 2 capturas)
13. Stock=1 duas capturas líquidas permanentes: NÃO
14. Bypass capacidade/reserva: SIM / PARCIAL (convert manual consome; inflate helper minta qty)
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO (buyer_id P2 no livro FB)
19. Reviews forjadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: PARCIAL (process convert + PATCH item via staff)
21. RLS crítico quebrado: PARCIAL (helper UPDATE `live_items.quantity`)
22. Edge confia autoridade do cliente no total: NÃO (mux owner-only)
23. Conclusão crítica NÃO COMPROVADA: NÃO (caixa HOLD; inventário P1)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: SIM (pass3 helper inflate — não saturado a 100%)
26. Saturação: NÃO (marketplace convert path ficou recusado por qty; OCR device token não exercitado)
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poço X exercitado: facebook_manual=SIM · staff=SIM · qty=SIM · mux=SIM · 2.º seller=SIM · rifa=SIM · caixa=SIM (sem captura)
ATROFIA: NÃO

VEREDICTO: FAIL_P1

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
