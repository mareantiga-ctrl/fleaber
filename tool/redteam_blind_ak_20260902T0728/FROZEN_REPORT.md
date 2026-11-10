# FLEABER — RED TEAM CEGO AK
## Auditor independente · PÓS-FECHO AEAFAG · HUB WEB / EDGE / DEEP LINK · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 4
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AK_HUB_EDGE_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T06:42:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AK1, AK2, AK3, AK4, AK5, AK6, AK7]
VEREDICTO: FAIL_P2
prefixo_fixtures: RTAK-20260902T0728-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas: `tool/redteam_blind_ak_20260902T0728/pass{1,2,3,4}.json`.

Anti-atrofia: 0/4 P2 = lista exacta M (Hub paused items, invite enum, pairing ended, dual Session clássico, mint pós-payout, plain→JSON). Variantes novas: GRANT da view Hub, `reserved_full` no FOMO/JWT, hitch REST após ended, gorjeta em gravado.

Poço AEAFAG: RLS `live_items` e discovery escondem esgotados no REST. **Não** tapam: (a) FOMO/Hub JWT a mostrar `reserved_full` com `available_qty=1` em directo **ended**; (b) REST a mostrar hitch marketplace de gravado (preço 5 €) enquanto Hub/FOMO vão vazios; (c) Hub web anon 401; (d) Edge a abrir Checkout Session de gorjeta em live ended.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 4
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO (`contract_unit_cents=4000` no hitch ended; live_item 5 € **não** selou)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO (fora da lente)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (settle alheio unpaid; complete-mux 403)
20. Cross-user dados sensíveis — NÃO (stream key / LiveKit 403)
21. Buyer assume seller/admin — NÃO (`create-mux-live` 403 authz)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da lente)
24. RPC SECURITY DEFINER perigoso executável — NÃO COMPROVADO (FOMO é definer por desenho; stock anon 42501)
25. RLS crítico quebrado — NÃO (tabela `live_items` anon 42501; buyer REST esconde `reserved_full`)
26. Edge confia total do cliente — NÃO (`tip_id` recusado; `web_return_origin` evil não vira Location; CORS não reflecte attacker)
27. Regressão funcional (happy path partido) — SIM (`hub_live_items_public` / discovery items **401** para anon)
28. Saturação atingida — NÃO (P2 abertos; AE preço ended fechado neste hitch)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

Fronteira **dinheiro**: GET settle forjado / unpaid **não captura**. Gorjeta Session em live ended fica `pending`. Hitch marketplace após ended sela **40,00 €** (catálogo), não 5 €. `complete-mux-live` / LiveKit token cruzados 403. `delete-test-account` 403. Webhook sem sig 400.

Falham superfícies **Hub/Edge de vitrine**:

1. **P2** — anon não lê `hub_live_items_public` (42501 `batata_live_item_stock`) — loja Hub web partida.
2. **P2** — FOMO + JWT na mesma view mostram `reserved_full` com `available_qty=1` em directo **ended**; REST buyer `[]`.
3. **P2** — REST buyer ainda lista hitch `marketplace_product` de gravado (preço 5 €); Hub/FOMO `[]`. Contrato checkout 40 €.
4. **P2** — `create-live-tip-checkout` abre Session Stripe em live **ended** published (1,00 € unpaid).

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P2 · RTAK-AK1-HUB-ITEMS-GRANT
**Lentes:** AK1  
**Actor:** anon (apikey)

**O quê:** As views `hub_live_items_public` e `hub_live_items_discovery_public` chamam `batata_live_item_stock` no `WHERE` (`security_barrier`). `GRANT EXECUTE` dessa função **não** está em `anon`. GET Hub items → **401** `permission denied for function batata_live_item_stock`. JWT buyer e `service_role` **200**.

FOMO (`batata_hub_live_fomo_snapshot`, security definer) continua **200** — o catálogo web anónimo parte; o oráculo RPC não.

**Não é** Hub paused items.

**Prova:** `pass1.json` `ak1.ended_pub_items`; `pass2.json` `view_matrix.hub_live_items_public` anon 401 / buyer 200.

**Impacto:** Hub público (sem login) não lista artigos de lives. Regressão funcional da vitrine.  
**Severidade:** P2.

---

### P2 · RTAK-AK1-FOMO-ENDED-RESERVED-FULL
**Lentes:** AK1  
**Actor:** anon (FOMO) · buyer JWT (view)

**O quê:** Após AEAFAG, REST `live_items` **esconde** `reserved_full` ao comprador (`[]`). A view Hub **não** exclui `reserved_full` (só `paused`/`inactive`/`sold`) e exige `available_qty > 0`. Item fixture `386a1d58-…` em live **ended** published `7148ec4f-…`: `status=reserved_full`, `quantity=1`, stock `available_qty=1`.

- Anon `POST rpc/batata_hub_live_fomo_snapshot` → `ok:true`, item com `available_qty:1`, `pending_queue_count:0`, `display_reserved_qty:0`.
- Buyer `GET hub_live_items_public` → linha `price:7`, `status:reserved_full`.
- Buyer `GET live_items?id=eq.` → `[]`. Seller REST vê a linha.

**Não é** discovery a mostrar esgotado (fechado AG) nem paused items.

**Prova:** `pass1.json` FOMO payload; `pass2.json` `RTAK-AK1-RESERVED-FULL-IN-VIEW`; `pass3.json` `rest_rf` + `fomo`.

**Impacto:** oráculo de stock/preço em **gravado**; REST e Hub divergem. UUID + qty exacta sem estar no player REST.  
**Severidade:** P2.

---

### P2 · RTAK-AK1-REST-ENDED-HITCH
**Lentes:** AK1, AK7  
**Actor:** buyer JWT

**O quê:** Hitch `marketplace_product` com `quantity=null` (check `live_items_kind_stock_chk`) em live activa, depois `status=ended`. Hub/FOMO **não** listam (`quantity>0` falha na view). REST buyer **ainda** devolve `price:5`, `status:available`, `is_active:true` — porque a policy AEAFAG permite SELECT se a live está em `hub_lives_public` (ended publicado entra).

INSERT `orders` com esse `live_item_id` → **201**, `contract_unit_cents=4000`, `price_total=40` (catálogo, **não** 5 €). Edge `create-payment-intent` 400 `Missing payment metadata` neste harness (sem captura).

**Não é** o P0 AE (selo ao preço do live_item ended). Aqui o contrato **aguenta** 40 €. O leak é o **preço 5 € ainda visível no REST** após o directo acabar, enquanto a vitrine Hub já esconde.

**Prova:** `pass4.json` `p4.surfaces` + `contract`. Item `f01aba78-…` live `af51cd1d-…` order `1569ced9-…`.

**Impacto:** player/REST ≠ Hub; preço histórico de live no catálogo cru. Sem Session barata neste teste.  
**Severidade:** P2.

---

### P2 · RTAK-AK4-TIP-ENDED-PUB
**Lentes:** AK4, AK3  
**Actor:** buyer JWT (create) · anon GET (settle)

**O quê:** `POST create-live-tip-checkout` com `live_id` de directo **ended** published + `seller_id` dono → **200** `checkoutUrl` Session `cs_test_a1dDiPJUomxH9P8xUrgLOhO2cwUPXKfHncYbn1TUcIMXZpFvfBSbXMsuLO` (1,00 €). GET settle `checkout_return=success` → texto «Pagamento ainda não confirmado». `live_tips.status=pending`.

**Não é** dual Session clássico nem mint. Session criada ≠ captura.

**Prova:** `pass2.json` `RTAK-AK4-TIP-ENDED-PUB`; `pass3.json` `tip_settle` + `tip_row`.

**Impacto:** Checkout Stripe TEST em gravado; spam de Sessions; sem crédito.  
**Severidade:** P2.

---

### P3 · RTAK-AK1-STOCK-RPC-BUYER
**Lente:** AK1  
**Actor:** buyer JWT

`POST rpc/batata_live_item_stock` no UUID FOMO do gravado → **200** `total_qty`/`available_qty`/`price`. Anon **42501**. Redundante com FOMO (já devolve qty); JWT extra no item que o REST lhe esconde.

**Prova:** `pass2.json` `p2.stock_buyer`.  
**Severidade:** P3.

--------------------------------------------------
## HOLDS (fronteira aguentou)
--------------------------------------------------

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| AK1 | leftover `ended`+`is_active` unpublished na discovery | `[]` |
| AK1 | scheduled unpublished Hub/discovery | `[]` |
| AK1 | `hub_lives_public` de live activa unpublished | `[]` (só discovery) |
| AK1 | FOMO unpublished | `live_not_public` |
| AK1 | `handle_suggested` após lives ended | `found=false` (alinhado com discovery) |
| AK1 | embed PostgREST `lives(*)` / `live_items(*)` | PGRST200 |
| AK1 | `hub_live_messages_public` live unpublished | `[]` |
| AK1 | produto unlisted no Hub | `[]` |
| AK2 | CORS `attacker.fleaber.pt` / `chrome-extension://` / `evil.com` | **não** reflecte (KLM exact); `fleaber.app` e `127.0.0.1:4173` sim (allowlist) |
| AK2 | Connect GET `web_return_origin=evil.com` / `fleaber.pt.evil.com` / `user:pass@` | 200 HTML **sem** Location hostil; `fleaber.pt/@evil.com` → 303 `/wallet` |
| AK3 | GET settle `cs_test_rtak_forged_*` | 400 «não confirmado», ACAO `fleaber.pt` |
| AK3 | GET tip settle unpaid | `pending`, sem crédito |
| AK4 | `tip_id` cliente + `seller_id=self` | 400 `Client tip_id is not allowed` |
| AK4 | ingest-ocr token fake | 400 `missing_line_hash` (não 200 ok) |
| AK4 | `delete-test-account` `user_id` seller | 403 allowlist nuke |
| AK4 | `stripe-webhook` sem assinatura | 400 `missing_signature` |
| AK5 | `resolve-mux-playback` draft / leftover ended unpublished | 404 `live_not_public` |
| AK5 | mux **após** `endLives` no unpublished | 404 |
| AK5 | buyer `create-mux-live` | 403 authz |
| AK5 | seller2 `complete-mux-live` live A | 403 |
| AK5 | buyer LiveKit `step=token` live alheia | 403 |
| AK5 | mux HLS enquanto unpublished **está live** | 200 `source=live_active` — alinhado a discovery E0817; FOMO recusa (vitrine). **Não** reaberto como M draft. |
| AK6 | list `chat_media` prefixos `product_photos` / raiz | 200 `[]` (listagem M fechada ou vazia neste actor) |
| AK6 | list outros buckets | 200 `[]` |
| AK6 | upload anon `chat_media` | 403 RLS |
| AK7 | hitch ended → contrato 5 € | **NÃO** — `contract_unit_cents=4000` |
| AK7 | order `live_only` após ended | 400 `order_contract_price_missing` |

--------------------------------------------------
## CONTABILIDADE (Stripe TEST)
--------------------------------------------------

Nenhuma captura. Uma Checkout Session de gorjeta **unpaid**:

| Session | Montante | `live_tips.status` após GET settle |
|---------|----------|-------------------------------------|
| `cs_test_a1dDiPJUomxH9P8xUrgLOhO2cwUPXKfHncYbn1TUcIMXZpFvfBSbXMsuLO` | 1,00 € | `pending` (`c4124365-…`) |

Pedido hitch `1569ced9-…`: `contract_unit_cents=4000`, sem Session (Edge 400 metadata).

--------------------------------------------------
## TÁCTICAS / LENTES
--------------------------------------------------

- Anon Hub exercitado (views + FOMO + resolve_handle + OpenAPI).
- ≥2 Edges hostis: `resolve-mux-playback`, `create-live-tip-checkout`, `create-connect-account`, `create-payment-intent`, `complete-mux-live`, `livekit-mux-publish`, `refund-order`, `ingest-ocr-reservation`, `delete-test-account`, `stripe-webhook`.
- ≥1 settle GET com `session_id` forjado e Session real unpaid.
- Session criada ≠ captura (gorjeta).
- Flutter ≠ fronteira (REST/RPC/Edge directos).

--------------------------------------------------
## FIXTURES
--------------------------------------------------

Prefixo `RTAK-20260902T0728-`. Seller QA handle **restaurado** para `fleahub-demo-ux` (cleanup, não fix de produto). Lives de fixture `ended`. Seller2 `a7b09370-…` / buyer2 `e45c5ffa-…` em `*.fleaber.test`.
