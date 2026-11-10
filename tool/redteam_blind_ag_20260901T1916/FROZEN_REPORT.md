# RED TEAM CEGO AG — PÓS-FECHO ABACAD · LIVE MANUAL / STAFF

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 4
P3 aberto: SIM          → quantos: 3
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AG_LIVE_POS_ABACAD_v1
FROZEN_AT: 2026-09-01T18:30:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AG1, AG2, AG3, AG4, AG5, AG6, AG7, AG8]
VEREDICTO: FAIL_P2
```

Staging: `fxdknzrqjenzqcvnwqqq`. Stripe TEST só via e2e `setup_paid_order` (fixture). `service_role` só fixture. Prefixo `RTAG-20260901T1916-`.

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 4
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 3
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO (PATCH qty/live_item_id revertido)
11. Seller falsifica pagamento plataforma — NÃO (Stripe/platform bloqueado); SIM em MB WAY sem prova → P2-AG8
12. JWT cria saldo/fundos — NÃO (wallet 18.97 inalterada)
13. Refund excede captura — NÃO COMPROVADO (fora da lente)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO (RPC accept com 2 pending falha; PATCH accept 1 unidade)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO COMPROVADO como oversell pago; accept facebook_manual consome sem PI (desenho FB)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (mux_stream_key SELECT 403)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora da lente)
24. RPC SECURITY DEFINER perigoso executável — NÃO (stripe_convert JWT 42501; reconcile recusa order_not_paid)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (create-mux-live com live_id alheio criou live **própria** do caller, não hijack)
27. Regressão funcional (happy path partido) — SIM (mark_sold RPC + process accept com waitlist)
28. Saturação atingida — NÃO (P2 abertos; convert-sem-PI saturado)

---

## Poço (missão)

**Convert / mark_sold sem PaymentIntent:** convert PATCH/RPC exige order com `amount_paid_cents>0` ou PI — mesmo depois de o vendedor carimbar `status=pago` sem cêntimos. `batata_live_reservation_stripe_convert` revogado a `authenticated`. INSERT `converted` / aliases de status não passam.

**Hub / discovery fantasma:** `hub_live_items_public` e `hub_live_items_discovery_public` escondem o item com `available_qty=0`. FOMO devolve `items: []`. REST `live_items` **ainda** devolve a linha (`quantity=1`, `status=reserved_full`) ao comprador — P2-AG3.

**Sabotar live alheia:** PATCH ended, INSERT item, SELECT stream key — bloqueados. Edge Mux não reutilizou o `live_id` vítima.

**Facebook/manual consome stock sem dinheiro:** SIM, via `accepted` (não `converted`). PATCH `facebook_manual` pending→accepted → `available_qty=0`, `reserved_accepted_qty=1`, sem PI. Convert a seguir: `convert_requires_paid_order`. Isto é o poço de produto (venda FB fora da app); o fecho ABACAD segura o **converted**, não o hold `accepted`.

Exactos AD/AA (controlos, **não** findings): accepted→PATCH converted, helper pending/accepted→converted, INSERT fleaber_live converted, discovery exhausted, PATCH `status=sold`, hub qty=0 — todos bloqueados ou filtrados.

---

## Findings (variantes novas)

### P2-AG4 — `batata_mark_live_item_sold` inútil para JWT

**Lente:** AG4 (também AG2).  
**Variante:** não é o PATCH `status=sold` exacto AD3; é o RPC canónico a bater no trigger novo.

JWT vendedor (e helper com `can_change_current_item`) → RPC `batata_mark_live_item_sold` → `42501 live_item_status_sold_rpc_only`. O UPDATE interno corre como `authenticated`, o guard ABACAD recusa `status=sold` excepto `service_role`. Transacção reverte: produto marketplace **não** é deslistado (hitch `checkout_product_id` em live_only também falhou).

**Impacto:** vendedor Facebook/manual **não consegue** marcar artigo vendido pela via oficial. Happy path partido.  
**Prova:** `probes_pass2.json` `AG4-seller-mark-sold-rpc`; pass1 `AG4-mark-sold-live-only-checkout-product`, `AG2-change-current-item-mark-sold`.

### P2-AG6 — RPC accept parte quando a waitlist > stock

**Lente:** AG6 / AG1.  
**Variante:** não é race de dois converted; é `pending` a contar no chão de `live_items.quantity`.

`qty=1` + 2 `pending` → `batata_process_live_reservation_request(accept)` → `42501 live_item_qty_below_reservations` (o recompute faz UPDATE em `live_items`; o guard soma pending+accepted+converted).  
PATCH directo `status=accepted` **funciona** e consome 1 unidade.

**Impacto:** a UI que só chama o RPC não consegue aceitar o primeiro da fila se já houver lista de espera.  
**Prova:** `probes_pass3.json` `AG6-waitlist-freeze-accept` (rpc 403, patch 200 accepted); pass2 `AG6-sequential-accept-stock1`.

### P2-AG3 — REST `live_items` fantasma vs Hub

**Lente:** AG3.  
**Variante:** não é `hub_live_items_discovery_public` a mostrar esgotado (isso está fechado).

Após accept (fleaber ou facebook_manual): `batata_live_item_stock.available_qty=0`. Hub público 0 linhas. Discovery 0. FOMO `items:[]`. Comprador `GET live_items?id=eq.…` → 1 linha, `quantity=1`, `is_active=true`, `status=reserved_full`.

Checkout: `batata_ensure_checkout_product` buyer 403; `create-payment-intent` 400 metadata. Não houve 2.ª captura.  
**Impacto:** superfície de catálogo do player (tabela crua) ≠ Hub. Risco de UI mostrar artigo ainda “lá” se não tratar `reserved_full`.  
**Prova:** pass1 `AG3-rest-live-items-vs-hub-after-accept`.

### P2-AG8 — ciclo pago→enviado→entregue sem cêntimos (MB WAY)

**Lente:** AG8 / AG1.  
**Variante:** não é convert sem order; é order **sem PI/cêntimos** a parecer paga.

Buyer INSERT `reserva_pendente` (mbway, `live_item_id` de artigo já `accepted`). Seller PATCH `status=pago` **200** (`amount_paid_cents` e PI continuam null). PATCH PI/cêntimos → `order_money_fields_immutable`. Convert da reserva facebook_manual **ainda** `convert_requires_paid_order`. Wallet `18.97` inalterada.

A seguir: seller `enviado` 200; buyer `entregue` 200; `shipped_at` preenchido. Sem `stock_units_applied`, sem PI.

**Impacto:** encomenda “paga/enviada/entregue” sem dinheiro de plataforma. Não cria saldo. Não destrava `converted`. Hygiene / falso ledger para MB WAY sem prova. Pagamento Stripe/platform **não** foi falsificado (money cols + paid_status).  
**Prova:** pass2 `AG8-seller-stamp-pago-pi`; pass3 convert-after-fake-pago; pass4 ship chain.

---

### P3-AG5 — inflacionar `quantity` live_only

Seller JWT PATCH live_only `quantity` 2→99 **200**. Marketplace_product: inflar `live_items.quantity` bloqueado (`live_item_qty_exceeds_product`); inflar `products.quantity` 2→99 **200** (sem hold de order nesse SKU). Catálogo próprio, não oversell pago.  
**Prova:** pass1 `AG5-inflate-qty`; pass2 `AG5-inflate-marketplace-product-and-live-item`.

### P3-AG3 — buyer INSERT order em item esgotado

`POST orders` com `live_item_id` reserved_full → 201 `reserva_pendente`. PI recusado. Sem captura.  
**Prova:** pass2 `AG3-buyer-insert-order-reserved-full`.

### P3-AG2 — `can_change_current_item` entra no RPC mark_sold

Authz do RPC trata `can_change_current_item` como suficiente para mark_sold. O trigger ABACAD aborta depois. Privilege confusion residual. Self-escalate de permissões no accept do convite: HTTP 200 mas **permissions ficam** view-only (não há escalate real).  
**Prova:** pass1 `AG2-helper-self-escalate`, `AG2-change-current-item-mark-sold`.

---

## Controlos saturados (não findings)

| Variante | Resultado |
|----------|-----------|
| JWT `stripe_convert` | 403 permission denied for function |
| Rebind `live_item_id` em order paga (JWT) | 200 no-op; coluna não muda |
| 1 PI → 2 converts | `convert_requires_paid_order` |
| reconcile `aguarda_confirmacao` | INSERT cai em `reserva_pendente`; reconcile `order_not_paid` |
| Aliases Converted/sold/vendido na reserva | 400/403; status intacto |
| RPC convert facebook_manual | `convert_requires_paid_order` |
| Source whatsapp/staff INSERT accepted | RLS 403 |
| Helper view-only convert | `not_allowed` |
| PATCH status=Sold no live_item | 403 rpc_only |
| Mover live_id para live de seller2 | `live_item_not_authorized` |
| PATCH item de outro seller | 200 `[]` (0 rows) |
| Buyer hijack live_item_id/qty | revertido |
| Seller2 end live / insert item | 403 |
| SELECT mux_stream_key | 403 |
| create-mux-live com live_id vítima | 200 mas **nova** live do caller (`d37677a1-…`, ended na pass3) |

---

## Caixa

Wallet vendedor `balance=18.97` antes e depois de fake pago / enviado / entregue. Sem Δ. Sem PI Stripe extra além do e2e `setup_paid_order` (não reutilizado para convert).

---

## Anti-atrofia

Findings P2/P3 são caminhos **novos** (RPC mark_sold vs trigger sold; waitlist vs recompute; REST vs view; MB WAY pago sem cêntimos). Exactos AD/AA usados só como controlo. Não ATROFIA_ABORT.

---

## Fixtures

- Helper: `8b819c94-67b2-4faf-9616-175d56b3fae1`
- Seller2: `111685bd-b584-4d7a-8aed-7044505d48ed`
- Lives RTAG criadas: ended (`status=ended`, `is_active=false`) na medida do possível.
- Mux leftover `d37677a1-3436-4cee-b838-02142e2737fa` ended.

Probes: `probes.json`, `probes_pass2.json`, `probes_pass3.json`, `probes_pass4.json`. Scripts: `tool/redteam_blind_ag_20260901T1916.dart` + `_pass2/_pass3/_pass4.dart`.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
