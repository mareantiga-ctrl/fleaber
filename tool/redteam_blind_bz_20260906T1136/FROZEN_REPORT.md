# FROZEN_REPORT — RED TEAM CEGO BZ

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 2

```
1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_BZ_LIVE_POS_BRBW_v1
FROZEN_AT: 2026-09-06T10:52:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BZ1, BZ2, BZ3, BZ4, BZ5, BZ6, BZ7, BZ8]
VEREDICTO: FAIL_P2
prefix: RTBZ-20260906T1136
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BT/BN/BRBW **não contados** (HOLD): `esgotado` / `gone` / `it's mine` / `out of stock` / `sold` / `sold out` / `claimed` / `snap up` / `Ana levou` → `purchase_announce_via_broadcast_only`; item `paused` pending/accept → `live_item_not_sellable`; Mux VOD/asset authenticated → 403; hitch `checkout_product_id` / `product_id` coalesce → 2º accept `qty_exceeds_stock`; convert/broadcast sem PI.

---

## Missão

Depois do fecho FOMO/paused/Mux VOD BRBW, ainda anuncio compra falsa ou vendo item paused?

**Resposta:** ainda anuncio — o denylist não cobre `last one`, `já não há`, `esgotada`, `vendida`, `sem stock`, `mine`, … Convert/broadcast sem PI **não** passou. Item `paused` e `is_active=false` **não** aceitam (sequencial). Hitch `product_id` (marketplace) + `checkout` (live_only) **segura**. JWT autenticado lê `mux_playback_id` de live **unpublished** e **scheduled** que o Hub não lista; VOD/asset continuam 403.

---

## Findings abertos

### BZ-P2-01 — FOMO: sinónimos novos passam no system message (seller e helper `can_manage_chat`)

- **Sev:** P2 · **Lente:** BZ2 · **Actor:** seller JWT; helper só `can_manage_chat`
- **Pré:** denylist BRBW em `batata_live_system_message` (esgotado / gone / it's mine / out of stock / sold / claimed / snap up / levou). Helper aceite com `permissions.can_manage_chat=true` e resto false.
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` `{"p_live_id":…,"p_body":"last one"}` (seller JWT)
  3. Repetir `já não há`, `ja nao ha`, `esgotada`, `vendida`, `sem stock`, `no more`, `taken`, `that's mine`, `mine`, `última unidade`, `reserved`, `nao ha mais`, `last available`, `1 left`, `last piece`, `fora de stock`, `já não existe`, `no quedan`, `it's taken`, `only one left`, `unavailable`, `off sale`, `stock 0`, `zero stock`, `já saiu`, `last 1`
  4. Mesmo RPC com helper JWT: `last one`, `já não há`
  5. Buyer `GET live_messages?kind=eq.system`
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - Exactos: `esgotado` / `gone` / `it's mine` / `out of stock` / `sold` / `sold out` / `claimed` / `snap up` / `Ana levou` → recusados (não contar)
  - `esgotados` → recusado (substring `esgotado`; não contar)
  - Novos: todos os da lista acima `200 {"ok": true}` e rows em `live_messages` (`kind=system`)
  - Helper chat-only: `last one` e `já não há` persistiram
  - Buyer **vê** os bodies (`pass1.json` `p1.fomo.buyer.sees`)
  - Buyer RPC system → `not_allowed`; INSERT `kind=system` (buyer/seller/helper) → RLS 403
- **Impacto:** o vendedor (ou o ajudante de chat) publica no chat do directo que é «last one / já não há / esgotada» **sem** reserva aceite nem order paga. Não mexe stock nem caixa. Espectadores vêem mentira de FOMO.
- **Prova:** `pass1.json` findings `p1.fomo.new.*` / `p1.fomo.helper.*`

Uma classe, vários payloads — **conta 1**.

### BZ-P2-02 — JWT autenticado lê `mux_playback_id` de live unpublished / scheduled (Hub vazio)

- **Sev:** P2 · **Lente:** BZ7 · **Actor:** buyer JWT
- **Pré:** seller2 `hub_published=false`. Live A `status=live` `is_active=true` com `mux_playback_id` plantado. Live B `status=scheduled` `is_active=false` com playback plantado. BRBW: VOD/asset revoke `authenticated`; Hub/discovery exigem `hub_published`; `resolve-mux-playback` exige published ou dono.
- **Repro:**
  1. `GET /rest/v1/lives?id=eq.{unpub}&select=id,mux_playback_id` (buyer JWT)
  2. Idem live `scheduled`
  3. `GET hub_lives_public` + `hub_lives_discovery_public` (buyer)
  4. Idem `mux_vod_playback_id` / `mux_asset_id`
  5. `POST /functions/v1/resolve-mux-playback` buyer/anon vs owner
- **Esperado:** playback_id só via Hub/Edge quando a live é pública; unpublished/scheduled sem ID Mux para não-dono
- **Obtido:**
  - Unpublished live+active: REST buyer `200` `mux_playback_id=BZPLAYBACK1136fake0001`; Hub `[]`; discovery `[]`
  - Scheduled: REST buyer `200` `mux_playback_id=BZSCHED1136fake0001`; Hub `[]`; discovery `[]`
  - Live publicada seller1: REST = Hub = discovery (HOLD — stream público; não contar)
  - `mux_vod_playback_id` / `mux_asset_id`: **403** até unpublished (exacto BRBW, não contar)
  - Anon tabela `lives`: **401** fail-closed
  - Ended unpublished: REST `200 []` (RLS ended exige hub_published)
  - `resolve-mux-playback` buyer/anon unpublished/scheduled/ended → `404 live_not_public`
  - Owner resolve unpublished → `200` playback (HOLD — dono; não contar)
  - `complete-mux-live` / `livekit-mux-publish` alheios → 403
- **Impacto:** conta autenticada que não é dona lê o playback ID Mux de um directo **não listado no Hub** (unpublished ao vivo ou scheduled). Sem stream key. CDN Mux só se o playback for real (`playback_policy=public`); aqui o ID foi plantado. `resolve-mux-playback` **não** entrega o HLS ao buyer — o furo é a coluna REST + RLS `live+active` / `scheduled` sem `hub_published`.
- **Prova:** `pass3.json` `p3.mux.buyer.playback.unpub` / `.sched`; `confirm_mux_hub.log`

Uma classe (unpublished + scheduled) — **conta 1**. Live publicada REST=Hub **não** conta.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| BZ1 | `purchase_broadcast` buyer/seller sem PI | `200 false` |
| BZ1 | buyer `accept_broadcast` | `false` (exacto) |
| BZ1 / BZ8 | `stripe_convert` seller JWT | `403 permission denied for function` |
| BZ8 | PATCH `converted` sem order paga | `403 convert_requires_paid_order` |
| BZ1 | `facebook_manual` PATCH converted | `403 convert_requires_paid_order` |
| BZ1 | INSERT `facebook_manual` `status=converted` | coercido a `pending` |
| BZ4 | marketplace `product_id=SKU` checkout null + live_only `checkout=SKU` | 2º accept `qty_exceeds_stock`; `blocked_qty=1` |
| BZ4 | mesmo SKU em live B após accept live A | `qty_exceeds_stock` |
| BZ4 | dois live_only sem product_id, refs distintas | 2 accepts (2 unidades independentes — correcto) |
| BZ3 | pending/accept com item `paused` | `live_item_not_sellable`; Hub `[]` |
| BZ3 | pending depois pause, depois accept | accept `live_item_not_sellable` |
| BZ3 | `is_active=false` status=available | pending `live_item_not_sellable` |
| BZ3 | PATCH `status=inactive` | CHECK `live_items_status_op_chk` 400 |
| BZ5 | PATCH `live_items.quantity` após accept | `live_item_qty_increase_not_allowed` |
| BZ6 | 2× PATCH accepted paralelo, qty=1 | só 1 `accepted` |
| BZ6 | race `is_active=false` ∥ accept | flag off + **pending** (accept não passou) |
| BZ6 | race pause ∥ accept | estado final paused+accepted; accept1 **200** em paralelo com pause — consistente com accept-então-pause (permitido). Sequential pause-then-accept 403. TOCTOU **não comprovado**. |
| BZ7 | VOD/asset REST authenticated | 403 |
| BZ7 | stream complete/publish alheio | 403 |
| BZ7 | resolve unpublished buyer/anon | `404 live_not_public` |
| BZ7 | published live REST mux_playback_id | igual ao Hub (público) |
| BZ8 | POST order `pendente` sobre item accepted | `order_live_item_exhausted` (fail-closed) |

**Não finding:** INSERT `live_messages` `kind=system` (buyer/seller/helper) RLS 403 — denylist não é bypassável por REST. `live_only`+`product_id` CHECK-ilegal (não há dois marketplace no mesmo `(live_id, product_id)`).

---

## Invariantes A–L (poço live)

| ID | Resultado |
|----|-----------|
| A Stripe cobra contrato | NÃO COMPROVADO neste poço (sem Session TEST) |
| B Cliente não define preço/qty | HOLD qty (PATCH quantity recusado) |
| C Release/refund ≤ fundos | NÃO COMPROVADO (fora do poço) |
| D Uma unidade ≠ duas vendas | HOLD hitch product_id + accept paralelo |
| E JWT não cria saldo/PI | HOLD convert/broadcast sem PI |
| F Off-platform ≠ saldo | HOLD FOMO é mensagem, não caixa |
| G Refund ≤ captura | NÃO COMPROVADO |
| H Parties coerentes | HOLD |
| I Uma intenção payout ≤ 1 Transfer | N/A |
| J Intenções distintas | N/A |
| K Catálogo posterior ≠ contrato | HOLD qty item após accept |
| L Offer/bundle/reserva só com autoridade | HOLD paused / is_active=false / buyer accept_broadcast |

---

## Checklist 28

1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: NÃO
4. Quantos P1: 0
5. Buyer manipula preço autoritativo: NÃO COMPROVADO
6. Buyer manipula qty autoritativa: NÃO
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO COMPROVADO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO
12. Stock=1 duas vendas válidas: NÃO
13. Stock=1 duas capturas líquidas permanentes: NÃO COMPROVADO
14. Bypass capacidade/reserva: NÃO (paused/inactive HOLD; hitch HOLD)
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: SIM (mux_playback_id unpublished/scheduled — P2, sem stream key, sem VOD)
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: NÃO (convert sem GRANT; broadcast exige PI)
21. RLS crítico quebrado: NÃO (lives SELECT live+active/scheduled alinha playback; não quebra caixa)
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: NÃO (convert sem PI comprovadamente bloqueado; captura TEST não era o poço)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: SIM (lentes 8/8; último passe só P2 já classificados)
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços BZ exercitados: convert/broadcast=SIM · staff/FOMO=SIM · stock/hitch=SIM · paused/inactive=SIM · live_id/qty=SIM · race=SIM · Mux=SIM · caixa=SIM  
ATROFIA (só redescobriu exactos BT/BN/BRBW): NÃO — duas classes novas (FOMO last one / já não há; mux_playback_id não-público)

VEREDICTO: **FAIL_P2**

---

## Artefactos

- `tool/redteam_blind_bz_20260906T1136/pass1.json` — FOMO novos / convert / facebook_manual
- `tool/redteam_blind_bz_20260906T1136/pass2.json` — hitch product_id / paused / inactive / qty
- `tool/redteam_blind_bz_20260906T1136/pass3.json` — race / Mux REST+Edge / caixa
- `tool/redteam_blind_bz_20260906T1136/confirm_mux_hub.log` — Hub vs REST playback
- Lives de fixture `RTBZ-20260906T1136*` → `status=ended` `is_active=false` (cleanup)
