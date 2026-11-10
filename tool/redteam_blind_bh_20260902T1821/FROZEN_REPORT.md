# FROZEN_REPORT — RED TEAM CEGO BH

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 4

```
AUDITOR: REDTEAM_BLIND_BH_LIVE_POS_ATBE_v1
FROZEN_AT: 2026-09-02T17:40:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BH1, BH2, BH3, BH4, BH5, BH6, BH7, BH8]
VEREDICTO: FAIL_P2
prefix: RTBH-20260902T1821
staging: fxdknzrqjenzqcvnwqqq
```

Exactos AV/BB **não contados** (HOLD): `system_message` body «✅ … comprou» → `purchase_announce_via_broadcast_only`; `batata_live_purchase_broadcast` sem order paga → `false`.

---

## Missão

Depois do fecho ATBE residual, ainda se anuncia compra falsa, converte sem PI, ou se reabre ended e se revive a fila?

---

## Findings abertos

### BH-P2-01 — system_message FOMO por sinónimo / zero-width / leet (não «comprou»)

- **Sev:** P2 · **Lente:** BH1/BH2 · **Actor:** seller JWT e helper `can_manage_chat`
- **Pré:** live no ar; filtro ATBE só `(comprou|compraram|purchased|bought)` ou `✅`+`compr`
- **Repro:** `POST /rest/v1/rpc/batata_live_system_message` com body `🛒 Ana levou o casaco` / `✅ Ana sold the jacket` / `Ana esgotou a última unidade` / `✅ Ana com\u200bprou o casaco` / `✅ Ana c0mprou o casaco` / `🛒 vendido agora mesmo`
- **Esperado:** `purchase_announce_via_broadcast_only` (só `batata_live_purchase_broadcast` com order paga)
- **Obtido:** `{"ok": true}` e rows `live_messages` kind=system persistidas. Homoglyph cirílico `comprоu` **bloqueado** (ainda casa `compr` com `✅`). INSERT REST `kind=system` **403 RLS**. Chat REST com o mesmo texto persiste como `kind=chat` (não imita system).
- **Impacto:** prova social falsa no chat do directo sem pagamento. Sem Δ wallet / sem convert.
- **Prova:** `pass1.json` BH1-02, BH2-02; live `7a93ee52-2268-4a66-b27b-e17e0d805a7c`

### BH-P2-02 — reconcile MB WAY `aguarda_confirmacao` insere fila fantasma `stripe_paid_direct`

- **Sev:** P2 · **Lente:** BH8 · **Actor:** buyer JWT
- **Pré:** order `status=aguarda_confirmacao`, `amount_paid_cents=0`, PI vazio, `live_id`+`live_item_id` (fixture service — JWT INSERT no marketplace item falha por BH-P3-02)
- **Repro:** `POST /rest/v1/rpc/batata_live_reconcile_stripe_order` `{p_order_id}`
- **Esperado:** `order_not_paid` / sem INSERT reservation
- **Obtido:** buyer `{"ok": true, "direct_insert": true}`; seller `convert_requires_paid_order`; reservation `status=pending` notes=`stripe_paid_direct:<order_id>`. **Não consome** capacidade (pending). Δ wallet = 0. Anon 401; seller2 `not_allowed`.
- **Impacto:** fila / notas mentem «pago Stripe» sem captura. Mentira operacional, não mint.
- **Prova:** `pass3c.json` BH8-02; order `b37ea5d9-2031-447a-b485-771d4af525d3`; res `f914cb30-e1a8-44e9-a76a-6bb9c639151e`

### BH-P3-01 — `batata_live_item_total_qty` JWT buyer em live ended

- **Sev:** P3 · **Lente:** BH3 · **Actor:** buyer JWT
- **Pré:** live `status=ended` `is_active=false` (PATCH service). `batata_live_item_stock` anon/buyer já devolve `live_item_not_found`.
- **Repro:** `rpc batata_live_item_total_qty` JWT buyer
- **Esperado:** 0 / 403 / not_found (alinhado ao stock gate)
- **Obtido:** anon 401 GRANT; buyer `200 2` (qty real do live_only)
- **Impacto:** oráculo de capacidade pós-ended, sem Hub discovery (grelha vazia).
- **Prova:** `pass1.json` BH3-07

### BH-P3-02 — stock gate esconde `marketplace_product` (quantity NULL) a buyer/anon com live no ar

- **Sev:** P3 · **Lente:** BH3 · **Actor:** buyer JWT / anon
- **Pré:** `item_kind=marketplace_product`, `quantity` NULL (constraint), live broadcasting
- **Repro:** `rpc batata_live_item_stock`; JWT `INSERT orders` com `live_item_id` → `order_live_item_exhausted`
- **Esperado:** `available_qty` do produto para vitrine/checkout JWT
- **Obtido:** buyer/anon `live_item_not_found`; seller `ok: true`. Fail-closed (não mint). Checkout in-app pode ir pela Edge.
- **Prova:** `pass3c.json` BH3-08; `pass3b.json` SKIP order JWT

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Exact comprou / broadcast unpaid | BH1 | `purchase_announce_via_broadcast_only` / `false` |
| Broadcast order cancelada+PI | BH1 | `false` |
| PATCH/INSERT converted sem PI | BH1 | `convert_requires_paid_order`; INSERT cai a `pending` |
| `stripe_convert` JWT | BH1 | `permission denied for function` |
| Helper chat mark_sold / accept / qty | BH2 | `not_allowed` / `200 []` / `live_item_not_authorized` |
| Helper view/mark/res perms cruzadas | BH2 | `not_allowed` |
| Hitch checkout alheio INSERT/PATCH | BH4 | `live_item_checkout_product_seller_mismatch` |
| Hitch SKU extra próprio + mark_sold sem PI | BH4 | RPC ok no item; SKU `is_sold=false` `list_on_marketplace=true` |
| Buyer/seller2 mark_sold | BH4 | `not_allowed` |
| INSERT/PATCH status=sold | BH4 | `live_item_status_sold_rpc_only` |
| Upsert marketplace SKU alheio | BH4 | `not_allowed` |
| Dono/helper infla qty live_only | BH5 | `live_item_qty_increase_not_allowed` |
| Mover item live A→B / live_id mismatch | BH5 | `live_item_not_authorized` / `live_item_live_mismatch` |
| Qty reserva 99 | BH5 | cap 2 |
| Accept/INSERT após ended **real** (service) | BH6 | `live_ended` |
| Seller JWT PATCH lives end/reopen | BH6 | `permission denied for table lives` (GRANT) — atacante JWT **não** reabre |
| Race service-end ∥ accept | BH6 | res ficou `pending`, live `ended` |
| Mux cruzado complete/publish | BH7 | 403 `Sem permissão para esta live` |
| Anon stream_key REST | BH7 | 401 table lives |
| resolve-mux-playback draft | BH7 | 404 `live_not_public` |
| Buyer create-mux-live | BH7 | 403 só vendedor |
| Reconcile anon / seller2 | BH8 | 401 / `not_allowed` |
| Δ wallet reconcile pending | BH8 | 0 |

**Não é finding:** reopen via `service_role` + accept (pass2b BH6-03) — actor não é JWT atacante; live volta a broadcasting e accept é o happy path.

**Falsos positivos descartados:** pass2 BH6-01/02 (seller JWT não consegue `ended`; live continuava `live`; PATCH/INSERT 200/201 em broadcasting). pass1 BH2-04 `200 []` (RLS 0 rows).

---

## Lentes 8/8

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| BH1 convert/broadcast | SIM | P2 FOMO (não convert) |
| BH2 staff/FOMO | SIM | mesmo P2 (helper «levou») |
| BH3 stock/Hub | SIM | P3×2 |
| BH4 mark_sold/hitch | SIM | HOLD |
| BH5 live_id/qty | SIM | HOLD |
| BH6 race/reopen | SIM | HOLD JWT; race HOLD |
| BH7 Mux/sabotage | SIM | HOLD |
| BH8 caixa | SIM | P2 ghost pending; Δwallet 0 |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (fora do poço live; não demonstrado)
10. Buyer manipula qty autoritativa — NÃO (qty 99 capada a 2)
11. Seller falsifica pagamento plataforma — NÃO (convert exige pago; broadcast unpaid false). Parcial: notes `stripe_paid_direct` em pending sem captura (P2)
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO (poço sem refund)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (fora poço)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO (sem pagar TEST neste poço)
18. Bypass capacidade/reserva — NÃO (pending ghost não consome; ended bloqueia accept/INSERT)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (stream keys 401; Mux 403)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora poço)
24. RPC SECURITY DEFINER perigoso executável — PARCIAL: reconcile JWT buyer faz direct_insert pending com nota falsa (P2); convert pago continua bloqueado
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (complete-mux-live / livekit-mux-publish owner check)
27. Regressão funcional (happy path partido) — PARCIAL: JWT INSERT order em live_item marketplace → `order_live_item_exhausted` (P3 gate quantity NULL)
28. Saturação atingida — SIM nas 8 lentes; último passe sem classe nova P0/P1

ATROFIA (só exactos fechados): NÃO  
Poço Stripe TEST pago: NÃO (não exigido — findings sem captura)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
