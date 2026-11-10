# FROZEN REPORT — RED TEAM CEGO T (pós-fecho Q)

```
AUDITOR: REDTEAM_BLIND_T_POS_Q_v1
FROZEN_AT: 2026-09-01T07:46:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [T1, T2, T3, T4, T5, T6, T7, T8]
VEREDICTO: FAIL_P0
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT buyer `bfcbeeee-…` · seller `980f4fa1-…` · B2 `15baa274-…` · S2 `fec7bfd5-…` · anon.  
`service_role` só fixture live/produto, observe wallets/Stripe, cleanup `status=ended`.  
Prefixo `RTT-20260901T0730`. **Não se corrigiu nada. Produção não tocada. Fase 4 não iniciada.**

Poço: depois dos fechos Q (live_item∈live, resolvida seller, stock inflate, parcial pós-envio→Stripe, `#https://`), ainda há dinheiro, stock, autoridade live e disputa explorável — **com variantes novas**, não o exploit exacto de Q.

---

## VEREDICTO

**FAIL_P0** — a guarda Q8 só recusa parcial carteira em `enviado` / `entregue` / `concluido`. Em `pedido_devolucao` (pós-envio real, PI capturado) o RPC `batata_process_partial_refund_dispute` **minta carteira** comprador+vendedor **sem** `stripe_refund_id` e **sem** refund no PaymentIntent.

---

## FINDINGS

### T3-02 · P0 · Parcial em `pedido_devolucao` minta carteira (variante Q8)

**Lentes:** T3, T8 (caixa)  
**Actor:** buyer JWT (oferta: seller JWT)  
**Pre:** Stripe TEST `setup_paid_order` → `enviado` → `entregue` → INSERT disputa `reason=danificado` → oferta seller 40% `partial_refund` → PATCH `pedido_devolucao`.

**Repro:**
1. Encomenda plataforma capturada (`amount_paid_cents=590`, `pi_3UAlQqH7FWYUN3jh0ExuEeaQ`).
2. Abrir disputa em `entregue` (RLS permite; em `pago` a RLS recusa — T3-01 CLOSED).
3. Seller PATCH `seller_refund_percent=40`, `seller_offer_type=partial_refund`.
4. Buyer PATCH `orders.status=pedido_devolucao`.
5. Buyer RPC `batata_process_partial_refund_dispute`.

**Esperado:** qualquer pós-envio com PI activo → refund Stripe; `stripe_refund_id` preenchido; Δwallet=0 até o Stripe liquidar.  
**Obtido:** RPC `200 true`.

| Sítio | Antes | Depois |
|--------|--------|--------|
| Wallet buyer | 54,02 | **56,38** (Δ **+2,36** `reembolso`) |
| Wallet seller | 13,69 | **16,33** (Δ **+2,64** `venda` residual) |
| `orders.stripe_refund_id` | null | **null** |
| Stripe PI | succeeded 590 | succeeded **590**, `refunds=[]` |

Q8 na função actual:

```sql
and v_status in ('enviado', 'entregue', 'concluido') then
  raise exception 'dispute_partial_refund_requires_stripe'
```

`pedido_devolucao` / `em_devolucao` / `devolucao_entregue` ficam no caminho carteira. Em `entregue` a mesma RPC devolve `42501 dispute_partial_refund_requires_stripe` (T6-02) — o fecho Q8 **funciona nesse estado** e falha no estado de devolução imediatamente a seguir.

Não é «parcial 100% exact» (oferta 40%) nem o POST exacto em `entregue`.

---

### T5-02 · P1 · Seller forja `buyer_decision` e fecha `resolvida`

**Lente:** T5  
**Actor:** seller JWT  
**Pre:** disputa `aberta` após Stripe TEST + `entregue`.

**Repro:** `PATCH order_disputes` no mesmo pedido: `buyer_decision=accepted_partial_refund`, `status=resolvida`.

**Esperado:** Q5 impede seller de fechar `resolvida` sem decisão **do comprador**; `buyer_decision` não é campo do vendedor.  
**Obtido:** `200`, linha `status=resolvida`, `buyer_decision=accepted_partial_refund`, `current_turn=administracao`. Q5 lê `NEW.buyer_decision` — a forja no mesmo PATCH satisfaz a allowlist.

Aliases `resolved`/`fechada`/`closed` → `23514 order_disputes_status_check` (T5-01 CLOSED). Reabrir terminal pelo buyer revertido (T5-03 CLOSED).

---

### T1-02 · P1 · Mover `live_item` de live A→B após accept (variante Q1)

**Lente:** T1  
**Actor:** seller JWT  
**Pre:** live A+B do mesmo vendedor; item qty=2; reserva `accepted` no live A.

**Repro:** `PATCH live_items.live_id=<B>` depois do accept.

**Esperado:** Q1 impede item noutro live; imutável enquanto há reservas que consomem capacidade.  
**Obtido:** item `live_id=B`, reserva continua `live_id=A`, `live_item_id` o mesmo, `status=accepted`. Q1 só corre no INSERT/UPDATE da **reserva**, não no UPDATE do **item**. Não é o mismatch exacto no INSERT.

---

### T2-01 · P1 · Convert `fleaber_live` sem PaymentIntent

**Lentes:** T2, T1 (staff no pass1: helper S2 com `can_manage_reservations` também converteu → `sold`)  
**Actor:** seller JWT (e helper S2)  
**Repro:** `rpc batata_process_live_reservation_request p_action=convert` após accept, origem `fleaber_live`, **sem** order/PI.

**Esperado:** convert de saco in-app só após Stripe/reconcile (`stripe_convert` está revogado a `authenticated` — T2-02 CLOSED).  
**Obtido:** reserva `converted`, item `sold`. `batata_live_reservation_stripe_convert` JWT buyer = `42501` (CLOSED). O buraco é o **outro** RPC, autorizado ao seller/staff.

Pode ser caminho de caixa/Facebook; em `fleaber_live` marca o artigo vendido sem dinheiro. Helper S2 consegue o mesmo no live de S1 (autoridade live / sabotage de stock).

---

### T6-01 · P1 · Race `convert` ∥ `expire`

**Lente:** T6  
**Actor:** seller JWT ×2 (`Future.wait`)  
**Verbos ≠ Q.**

**Obtido:** ambos HTTP 200. Reserva final **`expired`**. Item final **`sold`**. Stock preso a `sold` sem reserva `converted`.

---

### T8-URL-* · P2 · Variantes de `#https://` / wrap (Q3)

Não é `#https://` exact nem `/https://` exact.

| ID | Variante | Efeito |
|----|----------|--------|
| T8-URL-other_supabase | `https://abcdefghijklmnop.supabase.co/storage/...` | `proof_url` aceite (`LIKE https://%.supabase.co/storage/%`) |
| T8-URL-label-other-sb | idem em `return_label_url` | label aceite |
| T8-URL-newline | `https://fleaber.app/\nhttps://evil.example/phish` | aceite — `.` no regex PostgreSQL não casa newline; allowlist `fleaber.app/%` casa |
| T8-URL-query_https | query `?next=https://evil.example` no bucket Fleaber | aceite; redirecção no browser **não** provada (img src ignora query) — P2 fraco |

`fleaber.app@evil`, `%2F`, backslash, `#/https://`, `javascript:` → `order_proof_url_denied` (CLOSED).

---

## CLOSED / NÃO EXPLORÁVEL (amostra)

| ID | Resultado |
|----|-----------|
| T1-01 | `live_item_id` NOT NULL — facebook_manual sem item = `23502` |
| T1-04 | accept∥accept qty=1 → um `qty_exceeds_stock` |
| T1-05 | live_item S1+product S2 recusado `23514` |
| T2-02 | `stripe_convert` authenticated/anon `42501` |
| T2-03 | reconcile marketplace+reserva live: RPC `ok/reconciled` mas status ficou `pending` com nota `stripe_paid:` (trigger buyer reverte status; **sem** convert efectivo) |
| T2-04 | checkout B2 com reservation B1 → `live item does not match order` |
| T3-01 | disputa em `pago` RLS 403 |
| T4-01/02 | inflate `products.quantity` com hold live: insert marketplace_product falhou; inflate `live_items.quantity` 1→20 **não** permitiu 2.º accept |
| T5-01 | aliases fora do CHECK status |
| T5-03 | buyer não reabre terminal |
| T6-02 | em `entregue`: parcial → `dispute_partial_refund_requires_stripe`; `refund-order` seller → `order_refund_blocked_status` — Q8+D0733 aguentam **neste** estado |
| T7-01 | B2 PATCH reserva B1 → 200 `[]` (0 rows) |
| T7-02 | B2 INSERT disputa noutro order → RLS 403 |

---

## TÁCTICAS

1. **Stripe TEST pago + disputa:** sim (`pi_3UAlQqH7FWYUN3jh0ExuEeaQ` e outros `setup_paid_order`).  
2. **Contabilidade:** wallets + `wallet_transactions` + PI retrieve + `refunds.list` = 0.  
3. **Race verbos ≠ Q:** `convert`∥`expire`; `process_partial`∥`refund-order` (este último CLOSED em `entregue`).  
4. **REST/RPC/Edge** — Flutter não usado.  
5. **Não partido:** reserva same-live qty cap; envio `enviado` carrier; `refund-order` em `enviado` continua bloqueado (não se testou anular em `pago` para não destruir o ciclo).

---

## ANTI-ATROFIA

Lista proibida (dual Session, bag unlist, seguro plain, spoof `seller_id` exact, live_item mismatch exact, abort devolução exact, wrap `/https://` exact, `#https://` exact, devolvida sem stripe exact, parcial 100% exact, review 5★, Hub paused, cancel hold): **0/N nos findings**.  
Não é `ATROFIA_ABORT`.

---

## LENTES

| Lente | Cobertura |
|-------|-----------|
| T1 | move item pós-accept; staff convert; qty race CLOSED; null item CLOSED |
| T2 | convert sem PI; stripe_convert grant CLOSED; reconcile cross-pool sem efeito final; checkout alien CLOSED |
| T3 | parcial `pedido_devolucao` P0; parcial `pago` RLS CLOSED; parcial `entregue` Q8 CLOSED |
| T4 | inflate live hold / live_items qty — sem oversell extra |
| T5 | forge `buyer_decision`+`resolvida`; aliases CHECK; reopen CLOSED |
| T6 | convert∥expire P1; partial∥refund-order em entregue CLOSED |
| T7 | B2 reserva/disputa CLOSED; helper S2 convert (T2-01/pass1) |
| T8 | T3-02 caixa; URLs P2 |

≥4 lentes com prova. T4 e T7 saturados sem finding de dinheiro.

---

## NÃO FAZER

Não corrigir. Não deploy. Não tocar produção. Não iniciar Fase 4.

Evidência bruta: `tool/redteam_blind_t_20260901T0730/pass1.json`, `pass1b.json`, `pass2.json`, `pass3_stripe_observe.json`.
