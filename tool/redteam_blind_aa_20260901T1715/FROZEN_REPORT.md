# FROZEN_REPORT — REDTEAM_BLIND_AA_LIVE_POS_X_v1

```
AUDITOR: REDTEAM_BLIND_AA_LIVE_POS_X_v1
FROZEN_AT: 2026-09-01T16:28:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AA1, AA2, AA3, AA4, AA5, AA6, AA7, AA8]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST não usado (finding não exigiu captura) · fixtures `RTAA-20260901T1715-`  
Pasta: `tool/redteam_blind_aa_20260901T1715/`  
**Não corrigi. Não toquei produção. FASE 4 não iniciada.**

Actors: buyer `bfcbeeee-…7c96` · seller `980f4fa1-…9588` · buyer2 `22380a8f-…1be9` · seller2 (RTAA) · helper `f74a6afa-…943b`  
Carteiras 61,10 / 18,97 **inalteradas** em toda a ronda.

Lentes: **AA1 AA2 AA3 AA4 AA5 AA6 AA7 AA8** (8/8).

--------------------------------------------------
MISSÃO
--------------------------------------------------
Sim: depois do fecho «convert exige order paga», **JWT seller e helper ainda marcam reservas `converted` por PATCH directo** — sem PaymentIntent, sem order, sem RPC `convert`. Consome capacidade (`sold_converted_qty` 0→5 num live_only qty=5).  
Não: RPC `convert` sem PI (`convert_requires_paid_order`); helper **não** infla qty; 2.º seller **não** termina live / token Mux / accept alheio; PATCH wallet é no-op `200 []`; Δ carteira = 0.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibidos como paragem única — **nenhum foi o finding principal**:

| Exact | Resultado nesta ronda |
|---|---|
| fb convert sem PI exact | RPC recusado `convert_requires_paid_order` — não foi o stop |
| helper qty 1→40 exact | `live_item_qty_increase_not_allowed` |
| spoof seller_id exact | guard força `seller_id` = dono da live |
| live_item mismatch exact | INSERT mismatch recusado; não foi o stop |
| stop_egress foreign exact | não usei `stop_egress`; `complete-mux-live` foreign = 403 |

≥50%? **Não.** `ATROFIA_ABORT` não aplica.

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO         → quantos: 0
P1 aberto: SIM         → quantos: 4
P2 aberto: SIM         → quantos: 3
P3 aberto: SIM         → quantos: 1
```

--------------------------------------------------
P1
--------------------------------------------------

Raiz única: **RLS `live_reservation_requests_update` + guard de capacidade permitem `status=converted` no PATCH JWT.** O RPC `batata_process_live_reservation_request` action=`convert` exige order paga; o UPDATE REST **não**.

### RTAA-AA1-patch-converted — seller PATCH facebook_manual → converted sem PI
**Lente AA1.** Actor: seller JWT.  
Pré: live_only qty=5; facebook_manual `pending`; zero PI / zero order.  
Repro: `PATCH live_reservation_requests?id=eq.…` body `{status: converted}`.  
Obtido: 200; row `1fb1874f-…` `status=converted` `source=facebook_manual` `buyer_id=buyer2`.  
Esperado: trigger recusa ou restaura `pending` (paridade com RPC).

### RTAA-AA1-fleaber-patch-converted — seller PATCH fleaber_live → converted sem pagamento
**Lente AA1.** Actor: seller JWT.  
Pré: comprador INSERT `fleaber_live` pending no item qty=1.  
Repro: mesmo PATCH `status=converted`.  
Obtido: row `ce1455a6-…` `source=fleaber_live` `status=converted`. Race posterior de dois PATCH converted no mesmo item → ambos `qty_exceeds_stock` (a unidade já estava consumida).  
Impacto: reserva in-app marcada vendida **sem** o comprador pagar.

### RTAA-AA2-helper-patch-converted — helper PATCH facebook_manual → converted sem PI
**Lente AA2.** Actor: helper JWT (`can_manage_reservations`, **sem** `can_mark_items_sold`).  
Pré: helper aceite+activo na loja 1.  
Repro: `PATCH` status=converted.  
Obtido: row `cc5edb5e-…` converted; stock `sold_converted_qty=1` `available_qty=4`.  
Helper **não** infla qty (403) e **não** `mark_sold` (`not_allowed`); o furo é o PATCH da reserva.

### RTAA-AA3-patch-qty-and-converted — PATCH qty=4 + converted na mesma chamada
**Lente AA3.** Actor: seller JWT.  
Pré: facebook_manual pending `requested_qty=1`; item qty=5 (já 1 converted do helper).  
Repro: `PATCH {requested_qty: 4, status: converted}`.  
Obtido: row `5a609669-…` `requested_qty=4` `status=converted`; stock `sold_converted_qty=5` `available_qty=0`.  
Zero Stripe, Δ wallet 0. Capacidade esgotada sem dinheiro.

INSERT `status=converted` **não** fura: 201 mas o guard canonicaliza para `pending`. Só o **UPDATE** fura.

--------------------------------------------------
P2
--------------------------------------------------

### RTAA-AA3-hub-converted-still-listed — Hub / `live_items.status` não acompanham PATCH converted
**Lente AA3.** Item qty=1 após PATCH converted: stock `available_qty=0` `sold_converted_qty=1`; `live_items.status` continua `available`; `hub_live_items_public` ainda devolve o row (view filtra `quantity>0` e `status not sold`, não `sold_converted`). RPC convert chama `batata_recompute_live_item_status`; PATCH não.

### RTAA-AA1-mark-sold-mkt-nopi — dono mark_sold unlista SKU sem PI
**Lente AA1.** `batata_mark_live_item_sold` JWT dono → product `is_sold=true` `list_on_marketplace=false`; live_item `status=sold`. Helper/buyer/seller2 recusados. Caminho operacional Facebook/POS do dono — **não** é o convert RPC; fica P2 (stock de loja sem PI, só o dono).

### RTAA-AA4-move-item-across-lives — live_id mutável sem fila
**Lente AA4.** Seller PATCH `live_items.live_id` live A→B (mesmo dono, sem reservas activas) → 200. Immutability VWX só com reservas pending/accepted/converted. Plantar na live do seller2 → `live_item_not_authorized`.

--------------------------------------------------
P3
--------------------------------------------------

### RTAA-AA1-patch-converted-no-processed-by
PATCH converted deixa `processed_by_user_id=null` (RPC gravaria o uid). Auditoria da fila sem actor.

--------------------------------------------------
FALSOS POSITIVOS (retraídos no pass2)
--------------------------------------------------
- `RTAA-AA8-wallet-patch` P0: `PATCH wallets` → **200 []**; saldo 18,97 inalterado.  
- `RTAA-AA7-patch-qty-foreign` P1: seller2 `PATCH live_items.quantity=99` → **200 []**; qty persistida = 5.

--------------------------------------------------
BLOQUEADO (fecho X+VWX a aguentar + variantes novas recusadas)
--------------------------------------------------
- RPC convert facebook_manual / helper_manual / mkt **sem** PI → `convert_requires_paid_order`
- JWT INSERT order `pago` + PI fake → `order_buyer_attribution_denied` / money_cols zera cents
- Buyer INSERT facebook_manual → RLS 403
- Buyer PATCH converted → 200 [] / status fica pending
- Helper inflate qty → `live_item_qty_increase_not_allowed`
- Helper self-widen perms → 200 [] (perms iguais)
- Helper INSERT/mark_sold loja seller2 → 403 / `not_allowed`
- View-only helper INSERT fb → `reservation_buyer_mismatch`
- qty=0 INSERT → CHECK `live_items_kind_stock_chk`; qty negativa → `live_item_qty_below_reservations`
- 2.º seller end live / INSERT item / accept / convert / self-staff → 403 / `not_allowed`
- Mux: stream_key não vaza (403 lives); token/complete/create-mux foreign/buyer 403; cleanup 401; OCR sem token 401 / fake token `invalid_token`
- Rifa: draw foreign `not_allowed`; award/prize RPC 404 schema (JWT sem EXECUTE)
- Convert qty=3 com order qty=1 → `qty_exceeds_stock` (capacidade, não 1:1 PI)
- 2.º RPC convert com 1 PI → 403 capacidade (não comprovámos reuse PI com folga de stock; PATCH já esgota sem PI)
- Happy path: fixture order paga `f51a125a-…` + RPC convert → `ok: true` (não partimos accept/convert legítimo)

--------------------------------------------------
AA8 · CAIXA
--------------------------------------------------
PATCH converted **não** cria order fantasma e **não** credita wallet. P0 caixa **não** aberto. P1 é stock/capacidade.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — **NÃO**
2. Quantos P0: **0**
3. P1 caminho explorável encontrado — **SIM**
4. Quantos P1: **4**
5. P2 hygiene encontrado — **SIM**
6. Quantos P2: **3**
7. P3 baixo risco encontrado — **SIM**
8. Quantos P3: **1**
9. Buyer manipula preço autoritativo — **NÃO**
10. Buyer manipula qty autoritativa — **NÃO**
11. Seller falsifica pagamento plataforma — **NÃO** (PATCH converted não finge PI; consome stock)
12. JWT cria saldo/fundos — **NÃO**
13. Refund excede captura — **NÃO COMPROVADO** (fora de âmbito live POS)
14. Release+refund cria dinheiro líquido — **NÃO**
15. Payout duplica Transfer — **NÃO COMPROVADO**
16. Stock=1 duas vendas válidas — **NÃO** (race PATCH converted qty=1 → ambos `qty_exceeds_stock` após 1 converted)
17. Stock=1 duas capturas líquidas permanentes — **NÃO**
18. Bypass capacidade/reserva — **SIM** (PATCH converted sem order paga; qty 1→4 no mesmo PATCH)
19. Cross-user financeiro — **NÃO**
20. Cross-user dados sensíveis — **NÃO** (stream_key não vaza)
21. Buyer assume seller/admin — **NÃO**
22. Seller assume buyer/admin — **NÃO**
23. Reviews forjadas — **NÃO COMPROVADO** (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — **NÃO** (mark_sold / process / raffle draw fail-closed p/ foreign)
25. RLS crítico quebrado — **SIM** (UPDATE reservas permite `converted` sem paridade do RPC)
26. Edge confia total do cliente — **NÃO** (Mux/OCR/cleanup recusados)
27. Regressão funcional (happy path partido) — **NÃO**
28. Saturação atingida — **NÃO** (P1 PATCH converted aberto; resto da superfície live POS saturado)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
