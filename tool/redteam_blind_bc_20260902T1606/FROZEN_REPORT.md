# FLEABER — RED TEAM CEGO BC
## Auditor independente · PÓS-FECHO ANAS · HUB WEB / EDGE / DEEP LINK · v1 (ronda nova)

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 4
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 5
```

```
AUDITOR: REDTEAM_BLIND_BC_HUB_EDGE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T15:22:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BC1, BC2, BC3, BC4, BC5, BC6, BC7]
VEREDICTO: FAIL_P2
prefixo_fixtures: RTBC-20260902T1606-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas: `tool/redteam_blind_bc_20260902T1606/pass1.json`.

Anti-atrofia: 0/1 P2 = lista exacta AQ/AK. Exactos fechados neste run: tip scheduled/draft/error/ended-active **400** broadcasting; Edge `resolve-mux-playback` scheduled/draft/error **404** `live_not_public`; anon stock ended `not_found` (gate ANAS); REST hitch `quantity=null` **[]**; REST `lives` anon **42501**; CORS não reflecte evil; Connect GET sem Location hostil; complete-mux / LiveKit cruzados **403**; settle unpaid sem captura.

Não repetidos (classe AK, fora da CONTAGEM): `batata_resolve_handle` via `handle_suggested` ainda devolve UUID com `hub_published=false`.

Poço ANAS: tip/Mux Edge = `batata_live_is_broadcasting()`; stock **anon** gated. **Não** tapam: (a) `hub_lives_public` publica `mux_vod_playback_id` de scheduled/draft/error — CDN Mux serve HLS sem passar na Edge; (b) oráculo `batata_live_item_stock` autenticado em gravado; (c) `batata_live_item_total_qty` anon sem gate; (d) GET settle da gorjeta ecoa erro Stripe.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 4
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO COMPROVADO
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (settle B2 unpaid; complete-mux/LiveKit 403)
20. Cross-user dados sensíveis — NÃO (sem stream keys na view; JWT stock de gravado exige UUID — P3)
21. Buyer assume seller/admin — NÃO (`create-mux-live` / complete / LiveKit 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da lente)
24. RPC SECURITY DEFINER perigoso executável — SIM (`batata_live_item_stock` JWT ended; `batata_live_item_total_qty` anon)
25. RLS crítico quebrado — NÃO (`lives` anon 42501; hitch nullqty [])
26. Edge confia total do cliente — NÃO (`tip_id` 400; `web_return_origin` evil sem Location; CORS allowlist) — **parcial:** Hub/CDN não passa pela Edge
27. Regressão funcional (happy path partido) — NÃO (tip live+active 200 Session; Hub items broadcasting)
28. Saturação atingida — NÃO (P2 Hub+CDN playback prematuro aberto)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

Fronteira **dinheiro**: GET settle unpaid **não captura** (próprio nem B2). Tip não-broadcasting **400**. `tip_id` cliente **400**. `complete-mux-live` / LiveKit cruzados **403**. Connect evil **sem** Location hostil.

Falha a superfície **Hub / playback prematuro** que a Edge ANAS já recusa:

1. **P2** — `hub_lives_public` lista scheduled (e draft/error `is_active`) com `mux_vod_playback_id`; `GET https://stream.mux.com/{id}.m3u8` devolve `#EXTM3U`; `resolve-mux-playback` no mesmo UUID = **404**.
2. **P3** — buyer JWT `batata_live_item_stock` de gravado `reserved_full` (gate ANAS só `anon`).
3. **P3** — anon `batata_live_item_total_qty` devolve `1` no mesmo UUID.
4. **P3** — draft/error + `is_active` entram na vitrine Hub (`OR is_active`).
5. **P3** — GET settle gorjeta ecoa `No such checkout.session` (oráculo Stripe).

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P2 · RTBC-BC5-CDN-BYPASS-SCHED
**Lentes:** BC1, BC5, BC7  
**Actor:** anon

**O quê:** ANAS fechou `resolve-mux-playback` a `batata_live_is_broadcasting()` (VOD só `ended` público). A view `hub_lives_public` continua `status in (scheduled, live, ended) OR is_active` **e** selecciona `mux_playback_id` / `mux_vod_playback_id`.

Fixture scheduled inactiva `84fe2cdf-…` (IDs Mux reais de um gravado staging):

- Hub anon `select=*` → `mux_vod_playback_id=8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8`
- Edge `POST resolve-mux-playback` → **404** `live_not_public`
- CDN `GET https://stream.mux.com/8cje21NK….m3u8` → **200** `#EXTM3U` (HLS VOD)
- playback **live** do mesmo card → Mux **412** `live_stream_inactive` (não há stream ao vivo; o furo é o VOD)

Draft `is_active` `1d0424fa-…` e error `is_active` `76a16c66-…` publicam o mesmo VOD na view; CDN 200.

**Não é** Edge scheduled HLS (AQ — aqui Edge **404**). **Não é** stream key (select=* sem `mux_stream_key`). Session criada ≠ captura (tips não-broadcast 400).

**Prova:** `pass1.json` `findings` `RTBC-BC5-CDN-BYPASS-SCHED` + `bc5.cdn.hub_sched_vod` + `bc5.resolve.sched`.

**Impacto:** quem lê o Hub vê o playback ID e assiste ao VOD **antes** do directo estar no ar, sem chamar a Edge. Precisa da vitrine (scheduled entra por desenho da view).  
**Severidade:** P2.

---

### P3 · RTBC-BC1-STOCK-JWT-ENDED
**Lente:** BC1  
**Actor:** buyer JWT

**O quê:** ANAS gated `batata_live_item_stock` só se `auth.role() = 'anon'`. Comprador autenticado no item `reserved_full` de gravado `19116296-…` (Hub/FOMO/REST **não** listam):

JWT `POST rpc/batata_live_item_stock` → **200** `ok:true`, `price:11`, `available_qty:1`, `total_qty:1`, `live_status:ended`, `ref_code:RTBC4`.  
Anon no mesmo UUID → `live_item_not_found` (gate ANAS **OK**).

**Não é** oráculo anon (AQ-P3 — fechado). UUID não sai da vitrine ended.

**Prova:** `pass1.json` `bc1.stock.jwt_json`.

**Impacto:** oráculo de stock/preço de gravado se o UUID vazar por outro canal (link, chat, histórico).  
**Severidade:** P3.

---

### P3 · RTBC-BC1-TOTALQTY-ANON-ENDED
**Lente:** BC1  
**Actor:** anon (apikey)

**O quê:** `GRANT EXECUTE` de `batata_live_item_total_qty` a anon (ANAS stock_gate) **sem** o gate de vitrine aplicado a `batata_live_item_stock`. Mesmo item ended:

Anon `POST rpc/batata_live_item_total_qty` → **200** `1`. UUID aleatório não testado para enumeração (função devolve `0` se not found — possível oráculo de existência).

**Não é** o par stock+qty anon do AQ (stock agora not_found). Residual: qty solta.

**Prova:** `pass1.json` `bc1.stock.qty_anon`.

**Impacto:** confirma qty de um UUID de gravado sem login.  
**Severidade:** P3.

---

### P3 · RTBC-BC1-HUB-DRAFT-ERROR-ACTIVE
**Lente:** BC1  
**Actor:** anon

**O quê:** `hub_lives_public` inclui qualquer `is_active=true`, mesmo `status=draft` ou `status=error` (não são `scheduled|live|ended`).

- draft+active `1d0424fa-…` → Hub n=1, FOMO `ok` items `[]`, Edge resolve **404**
- error+active `76a16c66-…` → Hub n=1 (mesmo padrão)

FOMO de scheduled `ok:true` items `[]` (items view exige broadcasting — alinhado). A **live** draft/error continua na grelha pública com IDs Mux (ver P2).

**Não é** Hub paused items (AK). **Não é** seller unpublished (seller2 Hub **[]**).

**Prova:** `pass1.json` `bc1.hub.lives_idle` + `lives_preview`.

**Impacto:** rascunho / erro aparece na vitrine do handle publicado.  
**Severidade:** P3.

---

### P3 · RTBC-BC3-SETTLE-STRIPE-ORACLE
**Lente:** BC3  
**Actor:** anon

**O quê:** GET `create-live-tip-checkout?session_id=cs_test_aaa…&checkout_return=success` → **400** corpo `No such checkout.session: cs_test_aaa…`. GET `create-payment-intent` no mesmo estilo devolve texto genérico «Pagamento ainda não confirmado». Session unpaid verdadeira → «ainda não confirmado» (sem captura). UUID de live_item como session_id → mesmo oráculo Stripe.

**Não é** settle alheio que captura (B2 no `cs_test` do B1 unpaid = texto genérico, sem crédito).

**Prova:** `pass1.json` `bc3.settle.forge` + `uuid`.

**Impacto:** distinguir session Stripe existente vs inventada. Sem dinheiro.  
**Severidade:** P3.

--------------------------------------------------
## HOLDS (amostra)
--------------------------------------------------

| ID | Nota |
|----|------|
| Tip draft/error/scheduled/ended-active | 400 broadcasting (ANAS) |
| Tip `tip_id` cliente | 400 |
| Tip seller_id ≠ dono | 400 |
| Tip live+active | 200 `cs_test_a1LSpvJyizl…` Session ≠ captura |
| Settle unpaid próprio/B2 | «ainda não confirmado» |
| Edge resolve scheduled/draft/error | 404 |
| complete-mux / LiveKit buyer e seller2 | 403 |
| CORS Origin evil / subdomain / null | ACAO `https://fleaber.pt` |
| Connect `web_return_origin` evil | HTML app, sem Location hostil |
| anon `lives` | 42501 |
| hitch qty null REST buyer | [] |
| anon stock ended | not_found |
| seller2 Hub | [] |
| embed `lives(*)` | sem stream keys |
| storage mux/recordings/private | list [] |
| resolve-mux seller2 live+active | 200 — **broadcasting real**, não prematuro (não conta) |
| `resolve_handle` handle_suggested | classe AK — fora da CONTAGEM |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Cobertura |
|-------|-----------|
| BC1 Hub / FOMO / handle | scheduled+VOD cols; draft/error `is_active`; stock JWT; total_qty anon; hitch REST; events JWT; embed |
| BC2 origin / CORS / Connect | Origin evil/sub/null; Connect GET 7 origens |
| BC3 settle alheio | GET tip unpaid B1/B2; forge cs_test; UUID; cross `create-payment-intent` |
| BC4 Edge body spoof | tip_id; seller mismatch; amount 0.5/501; playback_id + origin evil no tip on-air |
| BC5 Mux / playback / LiveKit | resolve estados novos; CDN directo; complete/LiveKit cruzados |
| BC6 Storage | buckets + list mux/recordings/private/avatars/public |
| BC7 Composição | Hub ID + Edge 404 + CDN 200 |

--------------------------------------------------
## FIXTURES (cleanup)
--------------------------------------------------

Directos RTBC criados → `status=ended` `is_active=false` no `finally`. Handle QA `fleahub-demo-ux` restaurado. Sem 4242. Sem Fase 4. Staging only.
