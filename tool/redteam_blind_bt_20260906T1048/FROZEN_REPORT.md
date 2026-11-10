# FROZEN_REPORT — RED TEAM CEGO BT

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
AUDITOR: REDTEAM_BLIND_BT_LIVE_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T10:05:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BT1, BT2, BT3, BT4, BT5, BT6, BT7, BT8]
VEREDICTO: FAIL_P2
prefix: RTBT-20260906T1048
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BN/BH **não contados** (HOLD): hitch `logical_item_id` / mesmo `checkout_product_id` 2× accept → `qty_exceeds_stock`; «claimed» / «snap up» / «Ana levou» / «sold» → `purchase_announce_via_broadcast_only`; buyer `accept_broadcast` → `false`.

---

## Missão

Depois do fecho FOMO/accept/hitch BLBQ, ainda anuncio compra falsa ou converto reserva sem pagamento?

**Resposta:** ainda anuncio — o denylist não cobre sinónimos novos (`gone`, `it's mine`, `esgotado`, …). Convert/broadcast sem PI **não** passou. Stock hitch pelo mesmo `checkout_product_id` **segura**. Item `paused` continua a aceitar fila. JWT autenticado lê `mux_vod_playback_id` / `mux_asset_id` de live alheia (stream key não).

---

## Findings abertos

### BT-P2-01 — FOMO: sinónimos novos passam no system message (seller e helper `can_manage_chat`)

- **Sev:** P2 · **Lente:** BT2 · **Actor:** seller JWT; helper só `can_manage_chat`
- **Pré:** denylist BLBQ em `batata_live_system_message` (claimed / snap up / levou / sold / esgotou / mine now / its gone). Helper aceite com `permissions.can_manage_chat=true` e resto false.
- **Repro:**
  1. Live `status=live` `is_active=true`
  2. `POST /rest/v1/rpc/batata_live_system_message` `{"p_live_id":…,"p_body":"esgotado"}` (seller JWT)
  3. Repetir `gone`, `it's mine`, `its mine`, `GONE!`, `that's mine`, `out of stock`, `last one gone`, `esgotada`, `acabou`, `no stock`
  4. Mesmo RPC com helper JWT: `esgotado`, `gone`
  5. Buyer `GET live_messages?kind=eq.system`
- **Esperado:** `ok=false` `purchase_announce_via_broadcast_only` (anúncio de compra só via broadcast com PI)
- **Obtido:**
  - Exactos: `claimed` / `snap up` / `Ana levou` / `sold` → recusados (não contar)
  - Novos: todos `200 {"ok": true}` e rows em `live_messages` (`kind=system`)
  - Helper chat-only: `esgotado` e `gone` persistiram
  - Buyer **vê** `body=esgotado` (`pass3b.json` p3b.fomo.buyer.sees)
  - Buyer RPC system → `not_allowed`; INSERT `kind=system` → RLS 403
- **Impacto:** o vendedor (ou o ajudante de chat) publica no chat do directo que o artigo «está esgotado / gone / it's mine» **sem** reserva aceite nem order paga. Não mexe stock nem caixa. Espectadores vêem mentira de FOMO.
- **Prova:** `pass1.json` findings `p1.fomo.*`; `pass3b.json` nota `p3b.fomo.buyer.sees`

Uma classe, vários payloads — **conta 1**.

### BT-P2-02 — item `paused`: Hub vazio, buyer entra na fila, seller aceita

- **Sev:** P2 · **Lente:** BT5 · **Actor:** buyer JWT + seller JWT
- **Pré:** live no ar; `live_items.status=paused`; Hub `hub_live_items_public` não lista o card
- **Repro:**
  1. `PATCH live_items status=paused` (seller)
  2. `GET hub_live_items_public?id=eq.{item}` (buyer) → `200 []`
  3. `POST live_reservation_requests` pending (buyer JWT)
  4. `PATCH status=accepted` (seller JWT)
- **Esperado:** pending/accept recusados enquanto o item não está à venda
- **Obtido:** Hub `[]`; reserva `dddd36ff-…` ficou `accepted` (`pass2.json`)
- **Impacto:** o card some da vitrine pública mas o caminho REST continua a vender. Não é mint (seller tem de aceitar). `inactive` no INSERT foi recusado por constraint (não contar segundo caso).
- **Prova:** `pass2.json` finding `p2.paused.still.accepts`

### BT-P2-03 — JWT autenticado lê VOD/asset Mux da live de outro vendedor

- **Sev:** P2 · **Lente:** BT7 · **Actor:** buyer JWT e seller2 JWT
- **Pré:** live seller1 `status=live` `is_active=true` com `mux_vod_playback_id` e `mux_asset_id` preenchidos. Anon: `revoke` BLBQ nas colunas Mux. Stream key já `revoke` a `authenticated`.
- **Repro:**
  1. `GET /rest/v1/lives?id=eq.{live}&select=id,mux_vod_playback_id` (buyer JWT)
  2. Idem `mux_asset_id`
  3. Idem `mux_stream_key` / `stream_key` / `mux_live_id`
  4. `GET hub_lives_public?id=eq.{live}&select=mux_playback_id,mux_vod_playback_id` (anon)
- **Esperado:** VOD/asset só owner/studio; Hub já anula VOD enquanto `live`; stream key nunca a não-owner
- **Obtido:**
  - Buyer/seller2: `mux_vod_playback_id` e `mux_asset_id` **200** com o ID plantado
  - `mux_stream_key` / `stream_key` / `mux_live_id`: **403** até para o owner via REST (HOLD)
  - Anon tabela `lives`: **401** `permission denied for table profiles` (fail-closed)
  - Hub anon: playback live OK, `mux_vod_playback_id=null` (alinhado)
  - `resolve-mux-playback` buyer: HLS playback, **sem** stream key; `complete-mux-live` / `livekit-mux-publish` alheios → 403
  - PATCH Mux/title pelo owner via REST → 403 (colunas/tabela; não é exploit)
- **Impacto:** conta autenticada que não é dona lê IDs Mux VOD/asset de um directo alheio ainda no ar. Sem stream key, sem ingest hijack nesta prova. CDN Mux só se o playback for real (`playback_policy=public`); aqui o ID foi plantado.
- **Prova:** `pass3b.json` findings `p3b.buyer.id,mux_vod_playback_id` / `mux_asset_id` (seller2 igual — **um** finding)

---

## HOLD (não contar)

| Lente | Prova | Resultado |
|-------|--------|-----------|
| BT1 | `purchase_broadcast` buyer/seller sem PI | `200 false` |
| BT1 | buyer `accept_broadcast` | `false` (exacto) |
| BT1 | `accept_broadcast` com `live_id` de outra live | `false` |
| BT8 | `stripe_convert` seller/buyer sem PI | `403 permission denied for function` |
| BT8 | PATCH `converted` sem order paga | `403 convert_requires_paid_order` |
| BT4 | dois live_only, mesmo `checkout_product_id`, refs HA/HB, `logical_item_id` null | 2º accept `qty_exceeds_stock`; `blocked_qty=1` |
| BT5 | PATCH `live_items.quantity` após accept | `live_item_qty_increase_not_allowed` |
| BT5 | PATCH `requested_qty` seller após accept | `qty_exceeds_stock`; buyer revert `200 []` qty=1 |
| BT5 | PATCH reserva `live_id` noutro directo no accept | `live_item_live_mismatch` |
| BT6 | pending/accept após `ended` | `live_ended` |
| BT6 | 8× PATCH accepted paralelo, qty=1, 2 buyers | só 1 `accepted` |
| BT4 | INSERT/mark_sold hitch `checkout_product_id` SKU seller2 | `live_item_checkout_product_seller_mismatch`; SKU intacto |
| BT7 | stream key / `mux_live_id` REST | 403 |
| BT7 | Edge complete/publish live alheia | 403 |

**Não finding (falso positivo):** dois `marketplace_product` cruzados (`product_id=A, checkout=B` vs `product_id=B, checkout=A`) aceitaram os dois — são **dois SKUs qty=1**, não duas vendas da mesma unidade. `create-payment-intent` no cruzado devolveu `400 Missing payment metadata` (sem captura). Não contar.

**Nota (não contar):** pending em live **ended** continua em `blocked_qty` da live nova com o mesmo checkout (`available_qty=0`). Fail-closed (não oversell). Fantasma congela stock até a pending expirar.

---

## Invariantes A–L (poço live)

| ID | Resultado |
|----|-----------|
| A Stripe cobra contrato | NÃO COMPROVADO neste poço (sem Session TEST) |
| B Cliente não define preço/qty | HOLD qty (PATCH requested_qty) |
| C Release/refund ≤ fundos | NÃO COMPROVADO (fora do poço) |
| D Uma unidade ≠ duas vendas | HOLD accept paralelo + hitch mesmo checkout |
| E JWT não cria saldo/PI | HOLD convert/broadcast sem PI |
| F Off-platform ≠ saldo | HOLD FOMO é mensagem, não caixa |
| G Refund ≤ captura | NÃO COMPROVADO |
| H Parties coerentes | HOLD live_id swap |
| I Uma intenção payout ≤ 1 Transfer | N/A |
| J Intenções distintas | N/A |
| K Catálogo posterior ≠ contrato | HOLD qty item após accept |
| L Offer/bundle/reserva só com autoridade | HOLD buyer accept_broadcast; PARCIAL pause (BT-P2-02) |

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
14. Bypass capacidade/reserva: PARCIAL (paused ainda aceita; hitch checkout HOLD)
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: SIM (Mux VOD/asset IDs — P2, sem stream key)
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: NÃO (convert sem GRANT; broadcast exige PI)
21. RLS crítico quebrado: NÃO
22. Edge confia autoridade do cliente no total: NÃO
23. Conclusão crítica NÃO COMPROVADA: NÃO (convert sem PI comprovadamente bloqueado; captura TEST não era o poço)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: SIM (lentes 8/8; último passe só P2 já classificados)
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços BT exercitados: convert/broadcast=SIM · staff/FOMO=SIM · stock/hitch=SIM · mark_sold=SIM · live_id/qty=SIM · race=SIM · Mux=SIM · caixa=SIM  
ATROFIA (só redescobriu exactos BN/BH): NÃO

VEREDICTO: **FAIL_P2**

---

## Artefactos

- `tool/redteam_blind_bt_20260906T1048/pass1.json` — FOMO / convert / broadcast
- `tool/redteam_blind_bt_20260906T1048/pass2.json` — hitch / qty / paused / live_id
- `tool/redteam_blind_bt_20260906T1048/pass3.json` — race / Mux Edge / mark_sold
- `tool/redteam_blind_bt_20260906T1048/pass3b.json` — Mux colunas / FOMO visível
- Lives de fixture `RTBT-20260906T1048*` → `status=ended` `is_active=false` (cleanup)
