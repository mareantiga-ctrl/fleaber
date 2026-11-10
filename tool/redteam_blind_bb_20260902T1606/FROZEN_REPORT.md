# FLEABER — RED TEAM CEGO BB
## Auditor independente · PÓS-FECHO ANAS · LIVE MANUAL / STAFF · v1 (ronda nova)

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: NÃO          → quantos: 0
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 2
```

```
AUDITOR: REDTEAM_BLIND_BB_LIVE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:25:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BB1, BB2, BB3, BB4, BB5, BB6, BB7, BB8]
VEREDICTO: FAIL_P3
```

Staging `fxdknzrqjenzqcvnwqqq`. Stripe TEST não usado (caixa não exigiu captura).  
Prefixo fixtures: `RTBB2-20260902T1606`.  
Actors JWT: seller · buyer · buyer2 · seller2 · helper. `service_role` só fixture/observe/cleanup.

Provas: `tool/redteam_blind_bb_20260902T1606/` (`pass1.dart`…`pass3b.dart`, `pass1.json`…`pass3b.json`).

Baseline ANAS (não relida como relatório AV): `batata_live_purchase_broadcast` exige order paga do item; INSERT reserva em live não-broadcasting → `live_ended`.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — **não**
2. Quantos P0: **0**
3. P1 caminho explorável encontrado — **não**
4. Quantos P1: **0**
5. P2 hygiene encontrado — **não** (mentira de compra ficou P3: actor é staff autorizado da loja)
6. Quantos P2: **0**
7. P3 baixo risco encontrado — **sim**
8. Quantos P3: **2** (system_message «comprou» sem PI; reconcile MB WAY cria pending com `ok: true`)
9. Buyer manipula preço autoritativo — **não**
10. Buyer manipula qty autoritativa — **não** (`requested_qty=50` INSERT 201 mas qty não persiste > stock; inflate live_item `live_item_qty_increase_not_allowed`)
11. Seller falsifica pagamento plataforma — **não**
12. JWT cria saldo/fundos — **não** (PATCH wallet `200 []` Δ=0; pass3 Δ=0)
13. Refund excede captura — **não exercido** (fora do poço)
14. Release+refund cria dinheiro líquido — **não**
15. Payout duplica Transfer — **não exercido**
16. Stock=1 duas vendas válidas — **não** (2.º accept → `qty_exceeds_stock`)
17. Stock=1 duas capturas líquidas permanentes — **não**
18. Bypass capacidade/reserva — **não** em converted; pending fantasma via reconcile não consome (item `available`)
19. Cross-user financeiro — **não**
20. Cross-user dados sensíveis — **não** (stream_key 403; Mux alheio 403)
21. Buyer assume seller/admin — **não**
22. Seller assume buyer/admin — **não**
23. Reviews forjadas — **não exercido**
24. RPC SECURITY DEFINER perigoso executável — **parcial P3**: `batata_live_system_message` (seller/staff chat) e `batata_live_reconcile_stripe_order` (direct_insert mente `ok`)
25. RLS crítico quebrado — **não**
26. Edge confia total do cliente — **não** (`complete-mux-live` / `livekit-mux-publish` 403 owner; OCR sem device token 401)
27. Regressão funcional (happy path partido) — **não**: broadcast com order paga → `200 true`
28. Saturação atingida — **sim** no poço convert/mark_sold/broadcast/staff/Mux/race/caixa JWT; residual só P3

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### BB-P3-01 — Helper `can_manage_chat` anuncia «comprou» sem pagamento (kind=system, visível no Hub)

**Lentes:** BB1, BB2, BB7 (alheia HOLD)  
**Severidade:** P3  
**Actor:** helper JWT com só `can_manage_chat`; leitura buyer2 JWT **e** Hub anónimo

**Pré:** live broadcasting; **sem** order paga; ANAS bloqueia `batata_live_purchase_broadcast` sem PI (`200 false`). Buyer `system_message` → `not_allowed`. Helper **sem** `can_manage_chat` → `not_allowed`. Live do seller2 → `not_allowed`.

**Repro:**
1. Staff aceite, `active=true`, permissions só `can_manage_chat`.
2. `POST /rest/v1/rpc/batata_live_system_message`  
   `{ p_live_id, p_body: "✅ Comprador fantasma comprou …", p_sender_label: "Sistema" }` com JWT helper.
3. GET `live_messages` (outro comprador) e `hub_live_messages_public` (anon).

**Prova LIVE:**
- Pass2 `BB1-04`: RPC `200 {"ok": true}`; mensagem `kind=system` visível ao buyer2.
- Pass3 `BB1-04.hub`: Hub auth **e anon** `200` body `✅ HubLie comprou RTBB2-P3-HUB-BB480482` (`03c09a2f-…`, live `a739ab0b-…`).
- Pass1 `BB1-01`: `purchase_broadcast` sem PI continua `200 false` (fecho ANAS intacto).
- Pass1 `BB1-06`/`BB1-08`: INSERT REST kind=system e PATCH chat→system bloqueados.

**Impacto:** prova social falsa no directo e no Hub público, indistinguível do anúncio de compra pago (`kind=system` + «comprou»). Não marca `converted`, não deslista SKU, Δ wallet = 0. Só quem o vendedor autorizou a gerir o chat (ou o próprio vendedor — canal intencional, HOLD).

**Não é** o exacto AP-P2-01 (buyer `purchase_broadcast` em qualquer live). Classe residual: RPC de sistema de chat, pós-ANAS, ainda texto livre.

---

### BB-P3-02 — `batata_live_reconcile_stripe_order` com MB WAY pendente devolve sucesso e cria fila `pending`

**Lentes:** BB1, BB8 (caixa intacta)  
**Severidade:** P3  
**Actor:** buyer JWT

**Pré:** order fixture `status=aguarda_confirmacao` (sem `amount_paid_cents`, sem PI) hitchada a `live_item` marketplace.

**Repro:**
1. Order `aguarda_confirmacao` no item.
2. `POST /rest/v1/rpc/batata_live_reconcile_stripe_order` `{ p_order_id }` JWT comprador.
3. Função SECURITY DEFINER trata `aguarda_confirmacao` como paga o suficiente e faz `direct_insert` `status=converted`.
4. Trigger `force_pending` rebaixa para `pending`. RPC mesmo assim `ok: true`.

**Prova LIVE (pass3b):**
- RPC `200 {"ok": true, "direct_insert": true, "live_item_id": "6a1e1f3e-…"}`
- Reserva `ff6a1009-…` `status=pending` notes `stripe_paid_direct:aa239768-…` (mentira: order **não** paga)
- Item continua `available`; order continua `aguarda_confirmacao`; wallets Δ=0
- Pass3 seller no mesmo caminho: `403 convert_requires_paid_order` (UPDATE convert falha; o INSERT já tinha sido forçado a pending)

**Impacto:** o cliente pode mostrar «reconciliado»; entra na fila do directo sem captura. Seller ainda tem de aceitar. Não há oversell autónomo nem dinheiro. Hygiene de RPC + nota `stripe_paid_direct` falsa.

**Não é** convert sem PI (AD1/AP) nem INSERT pending em live ended (AP-P3-01 — esse caminho agora `live_ended`).

--------------------------------------------------
## HOLD (amostra — não é finding)
--------------------------------------------------

| ID | Lente | Ataque | Resultado |
|----|-------|--------|-----------|
| BB1-01 | BB1 | purchase_broadcast sem PI | `200 false` (ANAS) |
| BB1-02 | BB1 | buyer system_message | `not_allowed` |
| BB1-03 | BB1 | seller system_message texto livre | **HOLD produto** (dono do canal) |
| BB1-05 / BB1-04b | BB7 | system_message live alheia | `not_allowed` |
| BB1-10 | BB1 | broadcast order cancelada + PI vivo | `200 false` |
| BB1-11/12/13 | BB1 | convert fleaber/facebook / PATCH converted | `convert_requires_paid_order` |
| BB1-16 | BB1 | INSERT reservation converted | forçado a pending |
| BB1-17 | BB1 | broadcast item A com PI do A2 | `200 false` |
| BB1-09b | BB8 | JWT INSERT `premio_rifa` | 201 mas status **não** fica `premio_rifa` |
| BB2-01…04 | BB2 | helper mark_sold / accept / escalate / invite s2 | `not_allowed` / RLS |
| BB2-05 | BB4 | helper mark_sold sem PI deslista SKU | `live_item_not_authorized` / SKU intacto |
| BB3-01…03 | BB3 | reserva scheduled/draft/idle/ended | `live_ended` |
| BB3-04/05 | BB3 | REST/Hub item ended | `200 []` |
| BB4-01/02 | BB4 | hitch SKU alheio / extra + mark_sold | não deslista sem PI |
| BB4-03…06 | BB4/7 | PATCH/INSERT sold; buyer/s2 mark_sold | RLS / `sold_rpc_only` / `not_allowed` |
| BB5-01…04 | BB5/7 | mover live_id, qty 99, item na live B, mismatch | `not_authorized` / `qty_increase` / `live_mismatch` |
| BB6-01/02 | BB6 | UPDATE pending→accepted após ended; accept ended | `200 []` / `live_ended` |
| BB6-03 | BB6 | 2 accept qty=1 | 1 accepted + `qty_exceeds_stock` |
| BB7-01…09 | BB7 | PATCH lives, Mux, stream_key, OCR, raffle, tips | 403/401 |
| BB8-01…03 | BB8 | INSERT/PATCH pago; PATCH wallet | falha / `200 []` Δ=0 |

--------------------------------------------------
## INVARIANTES (poço live)
--------------------------------------------------

| | Invariante | Estado |
|-|------------|--------|
| Convert | `converted` exige order paga no mesmo live_item | **HOLD** |
| purchase_broadcast | exige order paga do item (ANAS) | **HOLD** |
| system_message | só seller/staff `can_manage_chat`; texto livre | **FALHA (P3)** conteúdo tipo compra |
| mark_sold | não deslista alheio nem sem PI | **HOLD** |
| Staff | chat-only ≠ mark_sold / convert / escalate | **HOLD** ops; **FALHA (P3)** no texto system |
| Hub/REST | ended oculto; stock anon sem item | **HOLD** |
| Race | stock=1 → no máximo 1 accepted | **HOLD** |
| Mux/lives | JWT alheio não termina / não lê stream_key | **HOLD** |
| Caixa | JWT não minta saldo | **HOLD** |
| Ended | INSERT reserva off-air | **HOLD** (`live_ended`) |
| Reconcile | não converter sem captura | **HOLD** no estado; **FALHA (P3)** RPC `ok` + pending |

--------------------------------------------------
## LENTES
--------------------------------------------------

- **BB1 Convert bypass** — HOLD convert/broadcast pago; P3 system_message + reconcile pending.
- **BB2 Staff/helper** — HOLD escalate/mark_sold/accept; P3 system_message com `can_manage_chat`.
- **BB3 Stock/Hub/REST** — HOLD scheduled/draft/idle/ended; Hub ended `[]`.
- **BB4 mark_sold/hitch** — HOLD.
- **BB5 live_id/qty/cross-seller** — HOLD.
- **BB6 Race accept/convert/ended** — HOLD (UPDATE pending pós-ended não cola; accept `live_ended`).
- **BB7 Sabotar live/Mux** — HOLD; helper não escreve system na live alheia.
- **BB8 Caixa** — HOLD (sem mint; PATCH wallet não persiste).

--------------------------------------------------
## SATURAÇÃO · ANTI-ATROFIA
--------------------------------------------------

Não se repetiram como finding os exactos AP/AJ: `purchase_broadcast` sem PI (agora BLOCKED), INSERT pending em ended (agora `live_ended`), mark_sold foreign checkout, INSERT sold, convert sem PI.

Variantes novas: `system_message` staff, reconcile `aguarda_confirmacao`, broadcast com PI de outro item, UPDATE pending pós-ended, live `scheduled`/`draft`/`idle`, facebook_manual convert, Hub anon da mentira.

Findings: 2× P3. **&lt;50% exactos** → sem `ATROFIA_ABORT`.

Poço convert/mark_sold/hitch/staff/Mux/oversell/caixa: saturado para P0–P2. Residual P3 = prova social no chat (staff) + RPC reconcile mentiroso.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
