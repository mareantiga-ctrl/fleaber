# FLEABER — RED TEAM CEGO AP
## Auditor independente · PÓS-FECHO AHAM · LIVE MANUAL / STAFF · v1

```
P0 aberto: NÃO         → quantos: 0
P1 aberto: NÃO         → quantos: 0
P2 aberto: SIM         → quantos: 1
P3 aberto: SIM         → quantos: 1
P4 aberto: NÃO         → quantos: 0  (fora de âmbito)
```

```
AUDITOR: REDTEAM_BLIND_AP_LIVE_POS_AHAM_v1
FROZEN_AT: 2026-09-02T10:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AP1, AP2, AP3, AP4, AP5, AP6, AP7, AP8]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq`. Stripe TEST não usado (caixa não exigiu captura).  
Prefixo fixtures: `RTAP-20260902T1006`.  
Actors JWT: seller · buyer · buyer2 · seller2 · helper. `service_role` só fixture/observe/cleanup.

Provas: `tool/redteam_blind_ap_20260902T1006/` (`pass1.dart`…`pass3.dart`, `pass1.json`…`pass3.json`).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — **não**
2. Quantos P0: **0**
3. P1 caminho explorável encontrado — **não**
4. Quantos P1: **0**
5. P2 hygiene encontrado — **sim**
6. Quantos P2: **1** (classe `batata_live_purchase_broadcast` sem PI/authz)
7. P3 baixo risco encontrado — **sim**
8. Quantos P3: **1** (pending em live `ended`)
9. Buyer manipula preço autoritativo — **não**
10. Buyer manipula qty autoritativa — **não**
11. Seller falsifica pagamento plataforma — **não** (PATCH PI/buyer_id em order paga → `order_money_fields_immutable`)
12. JWT cria saldo/fundos — **não** (Δ wallet do pass1 −2 € **não reproduzido**; pass2 fixture pago Δ=0; broadcast Δ=0)
13. Refund excede captura — **não exercido** (fora do poço)
14. Release+refund cria dinheiro líquido — **não**
15. Payout duplica Transfer — **não exercido**
16. Stock=1 duas vendas válidas — **não** (race accept: 1 accepted + `qty_exceeds_stock`; 2.º live_item no mesmo SKU também `qty_exceeds_stock`)
17. Stock=1 duas capturas líquidas permanentes — **não**
18. Bypass capacidade/reserva — **não** enquanto a live está `ended` (accept → `live_ended`); pending não consome
19. Cross-user financeiro — **não**
20. Cross-user dados sensíveis — **não** (stream_key REST 403; anon `live_items` 401)
21. Buyer assume seller/admin — **não**
22. Seller assume buyer/admin — **não**
23. Reviews forjadas — **não exercido**
24. RPC SECURITY DEFINER perigoso executável — **sim, P2**: `batata_live_purchase_broadcast` autenticado, sem dono nem PI
25. RLS crítico quebrado — **não** (lives/live_items/helpers HOLD)
26. Edge confia total do cliente — **não** (`complete-mux-live` / `livekit-mux-publish` 403 owner; OCR sem device token 401)
27. Regressão funcional (happy path partido) — **não observada**
28. Saturação atingida — **sim** no poço convert/mark_sold/hitch/staff/Mux/race/caixa JWT

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### AP-P2-01 — Buyer injeta system «comprou» sem pagamento (live própria e alheia)

**Lentes:** AP1, AP7, AP8 (caixa intacta)  
**Severidade:** P2  
**Actor:** buyer JWT (e leitura por buyer2 JWT)

**Pré:** live broadcasting (ou já `ended`); **sem** order paga, **sem** convert.

**Repro:**
1. `POST /rest/v1/rpc/batata_live_purchase_broadcast`  
   `{ p_live_id, p_buyer_id: self, p_live_item_id }` com JWT comprador.
2. Função SECURITY DEFINER faz INSERT `live_messages` kind=`system`  
   body `✅ {nome} comprou {título}`.
3. Qualquer autenticado lê o chat (`live_messages_select_scoped`: kind system + channel fleaber/hub, live ou ended).

**Prova LIVE:**
- Pass2 `AP1-11b`: RPC `200 true`, mensagem `13bff377-…` live `64acdcb0-…`  
  body `✅ Maestro Buyer comprou RTAP-20260902T1006 p2 itemA`. Wallet Δ=0.
- Pass2 `AP7-09`: mesma RPC na live do **seller2** `cd7bc171-…` → mensagem `e12ea67b-…`.
- Pass3 `AP7-09b` / `AP1-11d`: **buyer2** GET `live_messages` vê as duas frases. Anon 401.

**Impacto:** prova social falsa no directo (próprio ou de outro vendedor). Não marca `converted`, não deslista SKU, não mexe wallet. Pode induzir staff/seller a tratar o artigo como vendido.

**Não é** o exacto AJ4-02 / AG4 / AD1 (convert/mark_sold). Classe nova neste poço: RPC de broadcast de compra concedida a `authenticated` sem cheque de dono nem PI.

---

### AP-P3-01 — Fila pending em live `ended`

**Lentes:** AP3  
**Severidade:** P3  
**Actor:** buyer JWT (INSERT); seller JWT (accept só depois de reabrir)

**Pré:** `lives.status=ended`, `is_active=false`; live_item `live_only` qty=1 (fixture service_role).

**Repro:**
1. Buyer `POST live_reservation_requests` → **201** status `pending` (não dispara `live_ended` porque pending **não** consome capacidade).
2. Enquanto ended: seller `process accept` → **403 `live_ended`**. Convert sem PI → `convert_requires_paid_order`. Hub/REST buyer do item ended → `200 []`.
3. Fixture reabre `status=live`. Seller accept da **mesma** pending → accepted / `reserved_full` (pass2 `AP3-06e`).

**Impacto:** comprador entra na fila com o directo já fechado; o vendedor **tem** de aceitar depois de reabrir. Sem oversell autónomo. Hygiene de estados, não caixa.

--------------------------------------------------
## HOLD (amostra — não é finding)
--------------------------------------------------

| ID | Lente | Ataque | Resultado |
|----|-------|--------|-----------|
| AP1-02/03 | AP1 | PATCH/RPC convert sem PI | `convert_requires_paid_order` |
| AP1-05 | AP1 | hitch `orders.live_item_id` em pago marketplace | 200 sem persistir hitch (campo não cola) |
| AP1-07 | AP1 | convert item A com PI do item B | `convert_requires_paid_order` |
| AP1-08 | AP1 | PATCH `buyer_id` de order paga | `order_money_fields_immutable` |
| AP1-10 | AP1 | INSERT `helper_manual` converted | forçado a `pending` |
| AP2-01 | AP2 | helper alarga `permissions` ao aceitar | permissions ficam view-only |
| AP2-02 | AP2 | helper `can_change_current_item` mark_sold | `not_allowed` (AHAM) |
| AP2-04/05 | AP2 | helper INSERT/invite na loja | RLS / `not_allowed` |
| AP4-01/02 | AP4 | hitch `product_id` / `checkout_product_id` alheio | `*_seller_mismatch` |
| AP4-03 | AP4 | mark_sold live_only hitch SKU extra **sem PI** | SKU extra continua listado |
| AP4-04/06 | AP4 | PATCH/INSERT `SOLD`/`sold` | `live_item_status_sold_rpc_only` |
| AP4-05 | AP4 | seller2 mark_sold live A | `not_allowed` |
| AP5-01/04 | AP5 | mover live_id / INSERT item alheio | RLS 0 rows / `live_item_not_authorized` |
| AP5-02 | AP5 | qty live_only → 99 | `live_item_qty_increase_not_allowed` |
| AP5-03 | AP5 | dois live_items no mesmo SKU qty=1 | ambos `qty_exceeds_stock` |
| AP6-01 | AP6 | race accept stock=1 | 1 accepted + 1 `qty_exceeds_stock` |
| AP3-01/02/04/05 | AP3 | Hub/REST reserved_full e ended | `200 []` |
| AP7-01…08 | AP7 | PATCH/DELETE live, Mux, stream_key, OCR | 403/401 |
| AP8 | AP8 | JWT PI/pago; wallet após broadcast | bloqueado / Δ=0 |

Pass1 `AP8-01-seller` (−2 € 26.97→24.97) **descartado**: conta seller partilhada; pass2 insertPaidOrder service_role Δ=0; `wallet_transactions` sem linhas no filtro usado; broadcast Δ=0. **Não** é P0.

--------------------------------------------------
## INVARIANTES (poço live)
--------------------------------------------------

| | Invariante | Estado |
|-|------------|--------|
| Convert | `converted` exige order paga no **mesmo** live_item+buyer | **HOLD** |
| mark_sold | não deslista checkout/product alheio nem sem PI | **HOLD** |
| hitch | `product_id` / `checkout_product_id` seller = dono da live | **HOLD** |
| Staff | view-only ≠ mark_sold / convert / convite | **HOLD** |
| Hub/REST | reserved_full e ended ocultos a não-owner | **HOLD** |
| Race | stock=1 → no máximo 1 accepted | **HOLD** |
| Mux/lives | JWT alheio não termina / não lê stream_key | **HOLD** |
| Caixa | JWT não minta saldo neste poço | **HOLD** |
| Chat live | «comprou» só após convert pago | **FALHA (P2)** |
| Ended | não aceitar reservas off-air | **HOLD** no accept; **FALHA (P3)** no INSERT pending |

--------------------------------------------------
## LENTES
--------------------------------------------------

- **AP1 Convert bypass** — HOLD nos caminhos de estado/RPC/hitch; P2 colateral no broadcast de compra.
- **AP2 Staff/helper** — HOLD escalate, mark_sold, invite.
- **AP3 Stock/Hub/REST** — Hub/REST HOLD; P3 pending em ended; anon stock GRANT devolve `available_qty=0` em reserved_full/ended.
- **AP4 mark_sold/hitch** — HOLD (UPDATE alheio e sem PI).
- **AP5 live_id/qty/cross-seller** — HOLD.
- **AP6 Race accept/convert** — HOLD.
- **AP7 Sabotar live/Mux** — REST/Edge HOLD; P2 via broadcast na live alheia (mesmo RPC).
- **AP8 Caixa** — HOLD (sem mint; Δ pass1 não causal).

--------------------------------------------------
## SATURAÇÃO · ANTI-ATROFIA
--------------------------------------------------

Não se repetiram como finding os exactos excluídos (mark_sold foreign checkout INSERT, Hub anon 401 stock GRANT, INSERT status=sold, RPC mark_sold partido, waitlist, REST ghost, accepted→converted, PATCH sold). Esses saíram **BLOCKED**.

Findings deste freeze: 1 classe P2 nova (broadcast) + 1 P3 de fila ended. **&lt;50% exactos** → sem `ATROFIA_ABORT`.

Poço convert/mark_sold/hitch/staff/Mux/oversell/caixa: saturado para P0/P1. Residual P2 é mentira de compra no chat, não caixa.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
