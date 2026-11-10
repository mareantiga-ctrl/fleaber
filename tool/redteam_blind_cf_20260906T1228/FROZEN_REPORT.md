# FROZEN_REPORT — RED TEAM CEGO CF

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 3
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 3

```
1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 3
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CF_LIVE_POS_BXCC_v1
FROZEN_AT: 2026-09-06T11:40:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CF1, CF2, CF3, CF4, CF5, CF6, CF7, CF8]
VEREDICTO: FAIL_P2
prefix: RTCF-20260906T1228
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BZ/BXCC **não contados** (HOLD): «last one» / «já não há» / «sem stock» / `sold` / `1 left` / `taken` / `mine now` / `esgotou` / `claimed` / `s0ld` / emoji-wrap `🔥1 left🔥` `⚠️sold⚠️` `✅taken` / `mux_playback_id` JWT SELECT / paused FOMO PT/EN / convert sem PI / hitch `product_id`.

---

## Missão

Depois do fecho FOMO last one / já não há / sem stock e revoke `mux_playback_id`, ainda anuncio compra/FOMO falsa, converto sem PI, leio Mux/stream alheio, ou parto stock no hitch — fora dos exactos BZ/BXCC?

**Resposta:** ainda anuncio — o denylist colapsa espaços/emoji mas **não** letras espaçadas, hífen→concat, sinonímia nova (`foi embora`, `já tem dono`, `claiming`, ES) nem homógrafos (`ſold`, `sаld`). O comprador **imita** `sender_label=Sistema` em `kind=chat`. Convert/PI alheio **não** passou. Hitch e qty>stock **seguros**. `mux_*` REST **403**; o furo irmão é `playback_id` + `livekit_room_name` em live **unpublished/scheduled** (Hub vazio).

---

## Findings abertos

### CF-P2-01 — FOMO: matriz nova passa no system message (seller e helper `can_manage_chat`)

- **Sev:** P2 · **Lente:** CF2 · **Actor:** seller JWT; helper só `can_manage_chat`
- **Pré:** denylist BXCC em `batata_live_system_message` (last one / já não há / sem stock / sold / 1 left / taken / mine now / esgotou / claimed; fold `0→o`; strip emoji/ZW; `\s+` → um espaço).
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` `{"p_live_id":…,"p_body":"l a s t   o n e"}` (seller JWT)
  3. Repetir: `foi embora` · `já tem dono` · `claiming` · `acaba de sair` · `last-one` · `lastone` · `ſold` · `sаld` (Cyrillic а) · `agotado` · `se fue` · `ya tiene dueño` · `final piece` · `levado` · `going once` · `m i n e   n o w` · `reservado`
  4. Helper chat-only: `foi embora`, `claiming`, `l a s t   o n e`, `já tem dono`
  5. Buyer `GET live_messages?kind=eq.system`
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only`
- **Obtido:**
  - Exactos BXCC: `last one` / `já não há` / `sem stock` / `sold` / `1 left` / `taken` / `mine now` / `esgotou` / `claimed` / `s0ld` / `já  não   há` / `🔥1 left🔥` / `⚠️sold⚠️` / `✅taken` / `no more left` / `sold.` / bidi `sold` → recusados (**não contar**)
  - Novos: todos os da lista acima `200 {"ok": true}` e rows `kind=system`
  - Helper chat-only: os 4 payloads persistiram
  - Helper **zero perms** e helper **só `can_mark_items_sold`**: `not_allowed`
  - Buyer RPC: `not_allowed`; INSERT `kind=system` (buyer/seller) → RLS 403
  - Buyer **vê** os bodies (`pass1.json` `p1.fomo.buyer.sees`)
  - Stock `available_qty` inalterado; zero orders pagas nesta live
- **Impacto:** vendedor ou ajudante de chat publica no directo que «foi embora / já tem dono / lastone / ſold» **sem** reserva aceite nem order paga. Não mexe stock nem caixa. Espectadores vêem FOMO oficial (`kind=system`).
- **Prova:** `pass1.json` `persisted_new` / `p1.fomo.helper.*`

Uma classe, vários payloads — **conta 1**.

### CF-P2-02 — Buyer (e seller) chat com `sender_label=Sistema` visível a outro buyer

- **Sev:** P2 · **Lente:** CF2 · **Actor:** buyer JWT
- **Pré:** INSERT `live_messages` `kind=chat` com `user_id=auth.uid()`; `sender_label` sem CHECK.
- **Repro:**
  1. Live ao ar
  2. Buyer `POST live_messages` `{kind:chat, body:"foi embora — última unidade", sender_label:"Sistema"}`
  3. Outro buyer `GET live_messages?id=eq.{id}&select=kind,body,sender_label`
- **Esperado:** label forçada ao perfil / recusa `Sistema` em `kind=chat`
- **Obtido:** `201` + buyer2 lê `kind=chat` `sender_label=Sistema` `body=foi embora — última unidade`
- **Impacto:** o comprador **imita staff/sistema** no chat do directo. Não baixa stock. Diferente do denylist RPC (é `kind=chat`, não `system`).
- **Prova:** `pass1.json` `p1.fomo.buyer.imitate.staff`

Conta **1** (vector distinto de CF-P2-01).

### CF-P2-03 — JWT autenticado lê `playback_id` e `livekit_room_name` de live unpublished / scheduled (Hub vazio)

- **Sev:** P2 · **Lente:** CF7 · **Actor:** buyer JWT
- **Pré:** BXCC `revoke select (mux_playback_id, mux_vod_playback_id, mux_asset_id, mux_stream_key, stream_key)` em `lives`. Seller2 `hub_published=false`. IDs plantados.
- **Repro:**
  1. `GET /rest/v1/lives?id=eq.{unpub}&select=id,playback_id` (buyer JWT)
  2. Idem `livekit_room_name`; live `scheduled` `is_active=false`
  3. Idem `mux_playback_id` / `mux_stream_key` / `stream_key` (exacto BXCC)
  4. `GET hub_lives_public` + `hub_lives_discovery_public`
  5. `POST /functions/v1/resolve-mux-playback`
- **Esperado:** identificadores de stream só via Hub/Edge quando a live é pública; unpublished/scheduled sem playback para não-dono
- **Obtido:**
  - Unpublished live+active: REST buyer `200` `playback_id=CFPLAINPB1228fake0001` e `livekit_room_name=CFROOM1228livekit`; Hub `[]`; discovery `[]`
  - Scheduled: REST buyer `200` `playback_id` + `livekit_room_name`; Hub `[]`
  - Ended unpublished: REST `200 []` (RLS ended exige hub_published — HOLD)
  - `mux_playback_id` / VOD / asset / `mux_stream_key` / `stream_key` / `mux_live_id`: **403** (exacto BXCC, não contar)
  - Anon `mux_playback_id`: **401/403** fail-closed
  - `resolve-mux-playback` buyer/anon unpublished/ended → `404 live_not_public`
  - Owner resolve unpublished → `200` playback (HOLD — dono)
  - Live publicada seller1: Hub expõe `mux_playback_id` (HOLD — stream público)
  - `complete-mux-live` / `livekit-mux-publish` alheios → 403
  - SELECT `*` com colunas revogadas → 403 (não vaza `mux_*` por wildcard)
- **Impacto:** conta autenticada que não é dona lê o **playback_id** (coluna irmã, não a revogada) e o **nome da sala LiveKit** de um directo **não listado no Hub**. Sem stream key. CDN Mux só se `playback_id` for um HLS real (`playback_policy=public`); aqui o ID foi plantado. `resolve-mux-playback` **não** entrega o HLS ao buyer no unpublished. O furo é REST + GRANT residual em `playback_id` / `livekit_room_name`.
- **Prova:** `pass3.json` `p3.mux.buyer.playback_id.unpub` / `.livekit_room_name.unpub`; `pass3b.json` `p3b.sched.*` / `p3b.live.playback_id`

Uma classe (unpublished + scheduled; duas colunas irmãs) — **conta 1**. Exacto `mux_playback_id` **não** conta.

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| CF1 | `purchase_broadcast` buyer/seller/helper sem PI | `200 false` |
| CF1 | broadcast live B com order/PI de live A | `200 false` |
| CF1 | buyer `accept_broadcast` | `false` |
| CF1 | `stripe_convert` seller JWT | `403 permission denied for function` |
| CF1 | reconcile order live A → reserva live B | `403 convert_requires_paid_order` |
| CF1 | buyer PATCH `pago`+PI (marketplace) | `403 order_money_fields_immutable` |
| CF1 | helper self-escalate permissions | PATCH `200 []`; perms inalteradas |
| CF1 | helper zero-perms accept / helper sold convert | `200 []` (sem mudança) |
| CF1 | helper OCR sem device token | `401 missing_device_token` |
| CF8 | PATCH `converted` sem order paga | `403 convert_requires_paid_order` |
| CF8 | FOMO → accept → POST order | `order_live_item_exhausted` (fail-closed) |
| CF8 | cadeia FOMO até `pago` | não chegou converted/pago |
| CF4 | hitch marketplace+live_only mesmo SKU | 2º accept `qty_exceeds_stock` |
| CF4 | race 2 hitch `checkout_product_id` | 0 accepted (ambos pending) |
| CF5 | reservation `requested_qty=5` em qty=1 | qty **coercida a 1**; accept 1 unidade |
| CF6 | race `end_live` ∥ accept | end ganhou; accept `live_ended` |
| CF6 | pending / accept **depois** de ended | `live_ended` |
| CF3 | FOMO vs stock | `available_qty` inalterado |
| CF7 | `mux_playback_id` REST buyer/anon/owner | 403 (exacto BXCC) |
| CF7 | VOD/asset/stream_key REST | 403 |
| CF7 | resolve unpublished buyer/anon | `404 live_not_public` |
| CF7 | Hub unpublished/scheduled | `[]` |
| CF7 | complete-mux / livekit-publish alheio | 403 |
| CF7 | ended unpublished `playback_id` | REST `[]` |
| CF2 | INSERT `kind=system` REST | RLS 403 |
| CF2 | buyer RPC system | `not_allowed` |
| CF2 | helper sem `can_manage_chat` system FOMO | `not_allowed` |

**Não finding:** `live_only` dois items sem hitch de produto = unidades independentes (não exercitado como venda dupla aqui). Owner `resolve-mux-playback` em unpublished = dono.

---

## Invariantes A–L (poço live)

| ID | Resultado |
|----|-----------|
| A Stripe cobra contrato | NÃO COMPROVADO neste poço (sem Session TEST) |
| B Cliente não define preço/qty | HOLD qty (requested_qty=5 → 1) |
| C Release/refund ≤ fundos | NÃO COMPROVADO (fora do poço) |
| D Uma unidade ≠ duas vendas | HOLD hitch product_id + race hitch 0 accepted |
| E JWT não cria saldo/PI | HOLD convert/broadcast/PATCH pago |
| F Off-platform ≠ saldo | HOLD FOMO é mensagem, não caixa |
| G Refund ≤ captura | NÃO COMPROVADO |
| H Parties coerentes | HOLD reconcile PI live errada |
| I Uma intenção payout ≤ 1 Transfer | N/A |
| J Intenções distintas | N/A |
| K Catálogo posterior ≠ contrato | HOLD |
| L Offer/bundle/reserva só com autoridade | HOLD paused exacto; end∥accept; helper perms |

---

## Checklist 28

1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: NÃO
4. Quantos P1: 0
5. Buyer manipula preço autoritativo: NÃO COMPROVADO
6. Buyer manipula qty autoritativa: NÃO (coerção a 1)
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO COMPROVADO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO
12. Stock=1 duas vendas válidas: NÃO
13. Stock=1 duas capturas líquidas permanentes: NÃO COMPROVADO
14. Bypass capacidade/reserva: NÃO (hitch/end HOLD)
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: SIM (`playback_id` / `livekit_room_name` unpublished/scheduled — P2, sem stream key, sem `mux_*`)
17. Buyer assume seller/admin: PARCIAL (`sender_label=Sistema` em chat — P2, não RPC staff)
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: NÃO (convert sem GRANT; broadcast exige PI)
21. RLS crítico quebrado: NÃO (lives SELECT live+active/scheduled alinha `playback_id`; não quebra caixa)
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: NÃO (convert sem PI comprovadamente bloqueado; captura TEST não era o poço)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: SIM (poços A–E; lentes 8/8; tácticas 1–4; último passe só P2 já classificados)
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços CF exercitados: A FOMO matriz=SIM · B convert/PI/staff=SIM · C race/FSM=SIM · D Mux/stream=SIM · E composição caixa=SIM  
Lentes 8/8: CF1 convert · CF2 FOMO · CF3 stock · CF4 hitch · CF5 qty · CF6 race · CF7 Mux · CF8 caixa  
ATROFIA (só redescobriu exactos BZ/BXCC): NÃO — três classes novas (FOMO espaçado/sinonímia/homógrafo; sender_label Sistema; playback_id irmão)

VEREDICTO: **FAIL_P2**

---

## Artefactos

- `tool/redteam_blind_cf_20260906T1228/pass1.json` — FOMO matriz / staff emit / imitate
- `tool/redteam_blind_cf_20260906T1228/pass2.json` — convert / PI alheio / helper / hitch / qty
- `tool/redteam_blind_cf_20260906T1228/pass3.json` — race end∥accept / Mux REST+Edge / caixa
- `tool/redteam_blind_cf_20260906T1228/pass3b.json` — playback_id scheduled + PATCH PI marketplace
- Lives de fixture `RTCF-20260906T1228*` → `status=ended` `is_active=false` (cleanup)
