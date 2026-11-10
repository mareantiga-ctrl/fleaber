# FLEABER — RED TEAM CEGO AW
## Auditor independente · PÓS-FECHO ANAS · HUB WEB / EDGE / DEEP LINK · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: NÃO          → quantos: 0
P3 aberto: SIM          → quantos: 3
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 3
```

```
AUDITOR: REDTEAM_BLIND_AW_HUB_EDGE_POS_ANAS_v1
FROZEN_AT: 2026-09-02T15:22:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AW1, AW2, AW3, AW4, AW5, AW6, AW7]
VEREDICTO: FAIL_P3
prefixo_fixtures: RTAW-20260902T1608-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas: `tool/redteam_blind_aw_20260902T1608/pass{1,2}.json`.

Anti-atrofia: 0/3 P3 = lista exacta AQ/AK. Exactos **fechados** neste run: Hub GRANT 200; tip ended 400 broadcasting; REST hitch qty=null `[]`; anon stock ended `live_item_not_found`; tip scheduled/draft/inactiva 400; Mux VOD inactiva 404 (VOD só `ended` real). Não repetidos: Hub 401 GRANT, tip ended Session, hitch null REST visível, stock ended ok:true, Mux scheduled HLS.

Poço ANAS: `batata_live_is_broadcasting()` em gorjeta/Mux + stock anon gated + REST `quantity>0`. **Não** tapam: (a) `GRANT EXECUTE` `batata_live_item_total_qty` a anon **sem** gate de vitrine; (b) `hub_lives_public` com `OR is_active` lista **draft** (playback IDs) enquanto Mux 404; (c) Connect `web_return_origin` com IP decimal/`127.1` → 303 `https://127.0.0.1/wallet`.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 3
9. Buyer manipula preço autoritativo — NÃO (hitch live `price=0` selou `contract_unit_cents=100` = catálogo 1 €, não 0)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (refund cruzado 403; sem captura)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (settle alheio unpaid; refund B2 403)
20. Cross-user dados sensíveis — NÃO (stream key / LiveKit / complete-mux 403; embed `lives(*)` 42501)
21. Buyer assume seller/admin — NÃO (`create-mux-live` 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da lente)
24. RPC SECURITY DEFINER perigoso executável — SIM (`batata_live_item_total_qty` anon sem gate; `mark_sold` / settle tip 42501)
25. RLS crítico quebrado — NÃO (`lives` embed 42501; hitch ended/qty null buyer `[]`)
26. Edge confia total do cliente — NÃO (`tip_id` 400; `buyer_id` ignorado; CORS não reflecte attacker; `web_return_origin` evil sem Location hostil) — **parcial:** IP decimal → localhost
27. Regressão funcional (happy path partido) — NÃO (Hub items anon 200; tip live+active 200)
28. Saturação atingida — NÃO (P3 abertos)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

Fronteira **dinheiro**: GET settle forjado Stripe 400. Tip unpaid «ainda não confirmado». Tip ended/draft/inactiva/error **400 broadcasting**. Hitch `price=0` sela **1,00 €** catálogo. `complete-mux-live` / LiveKit cruzados 403. Webhook sem sig 400. Connect evil.com **sem** Location hostil.

Falham superfícies **Hub/Edge de higiene** (sem captura):

1. **P3** — anon lê `total_qty` de item que o stock gated esconde (gravado, hitch, paused) se tiver o UUID.
2. **P3** — vitrine `hub_lives_public` (e FOMO `ok`) mostra directo **draft+is_active** com `mux_playback_id`; Mux recusa playback.
3. **P3** — Connect GET com `https://2130706433` / `https://127.1` redirecciona para `https://127.0.0.1/wallet`.

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P3 · RTAW-AW1-TOTAL-QTY-ANON
**Lentes:** AW1, AW7  
**Actor:** anon (apikey)

**O quê:** ANAS gata `batata_live_item_stock` para anon (`live_item_not_found` em gravado/hitch/paused). O irmão `batata_live_item_total_qty` tem `GRANT EXECUTE` a **anon** e **não** tem gate de vitrine/broadcasting.

| UUID | stock anon | total_qty anon |
|------|------------|----------------|
| ended available `4da8d43f-…` | `live_item_not_found` | **2** |
| ended `reserved_full` `a71ab22f-…` | `live_item_not_found` | **1** |
| hitch price=0 qty=null `157accc0-…` | `live_item_not_found` | **2** (qty do SKU) |
| paused item no ar `62ffcbe4-…` | `live_item_not_found` | **2** |
| UUID aleatório | — | **0** (não enumera) |

**Não é** stock ended ok:true (AQ-P3-01 — aqui **not_found**). UUID não sai da vitrine ended/hitch (Hub/REST/FOMO `[]`).

**Prova:** `pass1.json` `total_qty_anon`; `pass2.json` `qty_vs_stock`.

**Impacto:** oráculo de quantidade (não preço) se o UUID vazar por outro canal.  
**Severidade:** P3.

---

### P3 · RTAW-AW1-DRAFT-ACTIVE-HUB-LIVES
**Lentes:** AW1, AW5  
**Actor:** anon

**O quê:** `hub_lives_public` inclui `status in (scheduled,live,ended) **OR is_active=true`**. Fixture `status=draft` `is_active=true` (`cd6d425c-…`):

- `batata_live_is_broadcasting` → **false**
- Hub lives: linha com `mux_playback_id=rtaw_draft_pb_…` e `mux_vod_playback_id=rtaw_draft_vod_…`
- FOMO → `ok:true`, `live_status:draft`, items `[]` (não `live_not_public`)
- `resolve-mux-playback` → **404** `live_not_public`
- `create-live-tip-checkout` → **400** broadcasting

**Não é** Mux scheduled HLS/VOD (AQ-P2-02 — Mux **fechado**). Leak de metadados/playback IDs na vitrine, sem stream.

**Prova:** `pass1.json` `hub_lives` + `fomo.draft` + `mux.draft_active`.

**Impacto:** rascunho aparece na lista pública Hub com IDs Mux; playback e gorjeta recusados.  
**Severidade:** P3.

---

### P3 · RTAW-AW2-CONNECT-DECIMAL-LOCALHOST
**Lente:** AW2  
**Actor:** anon GET

**O quê:** `sanitizeWebReturnOrigin` faz parse URL e allowlist `127.0.0.1`. Origens **não** literais na lista:

- `web_return_origin=https://2130706433` → **303** `Location: https://127.0.0.1/wallet`
- `web_return_origin=https://127.1` → **303** `Location: https://127.0.0.1/wallet`

Evil.com / punycode / `fleaber.app.evil.com` → HTML **sem** Location hostil.

**Não é** `http://127.0.0.1:9` exact AQ/KLM (aqui IP decimal e shorthand).

**Prova:** `pass1.json` `connect_get`; `pass2.json` `connect_decimal` + `connect_127_1`.

**Impacto:** open-redirect para a máquina local do browser após Connect (staging). Sem roubo de código OAuth neste harness.  
**Severidade:** P3.

--------------------------------------------------
## HOLDS (fronteira aguentou)
--------------------------------------------------

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| AW1 | Hub items anon GRANT | **200** (AK1 fechado) |
| AW1 | anon stock ended / hitch / paused | `live_item_not_found` (AQ-P3-01 fechado) |
| AW1 | hitch `price=0` qty=null Hub/discovery/REST | **[]** (ANAS `quantity>0`) |
| AW1 | `showing` Hub vs discovery vs REST | alinhado (listam) |
| AW1 | item `paused` Hub/REST/stock | oculto |
| AW1 | GraphQL `live_itemsCollection` | pg_graphql **not enabled** |
| AW1 | embed `lives(*)` | 42501 |
| AW1 | `hidden` / `Available` em `live_items.status` | INSERT **400** check |
| AW1 | `paused` / `ao_vivo` / `active` em `lives.status` | INSERT **400** check |
| AW2 | CORS fleaber.app.evil / punycode / moz-extension / :8443 / IPv6-mapped | **não** reflecte (ACAO fleaber.pt) |
| AW2 | Connect evil.com / xn-- / data: / fleaber.app?next=evil | sem Location hostil |
| AW3 | GET settle `cs_test_rtaw_forged_*` | 400 Stripe |
| AW3 | GET tip settle unpaid + mix PI + B2 | não confirmado / 402 |
| AW4 | tip ended published | 400 broadcasting (AK4 fechado) |
| AW4 | tip draft / inactiva / error / paused-try | 400 |
| AW4 | tip `is_active` flip race | 400 (flip ganhou) |
| AW4 | `tip_id` cliente | 400 |
| AW4 | amount 0.01 / 9999 | 400 |
| AW4 | `seller_id` alheio / self | 400 |
| AW4 | ingest-ocr token fake | 401 `missing_device_token` |
| AW4 | `delete-test-account` `user_id` seller | 403 nuke allowlist |
| AW4 | `stripe-webhook` sem assinatura | 400 |
| AW5 | Mux VOD `status=live is_active=false` | 404 (ended≠inactiva) |
| AW5 | Mux draft+active (antes do cleanup) | 404 |
| AW5 | buyer `create-mux-live` | 403 authz |
| AW5 | seller2 `complete-mux-live` live A | 403 |
| AW5 | buyer LiveKit `step=token` | 403 |
| AW6 | list buckets (chat_media, product_photos, fleaber_private, …) | 200 `[]` |
| AW6 | upload anon `chat_media` | 403 RLS |
| AW7 | hitch price=0 → contrato 0 € | **NÃO** — `contract_unit_cents=100` |
| AW7 | Edge PI hitch 0 + `buyer_id` alheio | 400 metadata |
| AW7 | refund B2 pedido B1 | 403 |
| AW7 | `batata_mark_live_item_sold` / settle tip RPC anon | 42501 |

Pedido `showing` no ar (`e4f6c303-…`, 4,00 €) **não** é finding: o artigo está na vitrine Hub/REST.

--------------------------------------------------
## CONTABILIDADE (Stripe TEST)
--------------------------------------------------

Nenhuma captura. Checkout Sessions de gorjeta **unpaid**:

| Session | Contexto | GET settle |
|---------|----------|------------|
| `cs_test_a1EMorBT1xWUd7ex51bgt1rn5QuW48A6UFzyHXV2kdGJbg1vnrNpF2duIp` | live+active (happy) | não confirmado |
| `cs_test_a1zIMipMEwDOj4GnbbE1edyRq12DXroNMxsGKZzaC63pgjM3N8cyUOc8Gc` | live + `web_return_origin` evil | (não re-settled) |
| `cs_test_a1z0sN74qyk2vywK5dPL18J8gL2ehIhJJK49duCXP8j1TlO8TNRYkzjScI` | `buyer_id` spoof (ignorado) | — |
| `cs_test_a14nrxvnZM7VlslUJgYmDGD9ToLpcFKBzmel55YJtSy0dM57cB77pV1pl9` | `order_id` extra no body | — |

Pedido hitch 0 € `60d4e341-…`: `contract_unit_cents=100`, `price_total=1`, `pendente`, sem Session.

--------------------------------------------------
## TÁCTICAS / LENTES
--------------------------------------------------

- Anon Hub exercitado (views + FOMO + resolve_handle + GraphQL + OpenAPI + embed).
- ≥2 Edges hostis: `resolve-mux-playback`, `create-live-tip-checkout`, `create-connect-account`, `create-payment-intent`, `complete-mux-live`, `livekit-mux-publish`, `refund-order`, `ingest-ocr-reservation`, `delete-test-account`, `stripe-webhook`.
- ≥1 settle GET com `session_id` forjado, Session real unpaid, mix tip↔PI, buyer2.
- Session criada ≠ captura (gorjeta live unpaid).
- Flutter ≠ fronteira (REST/RPC/Edge directos).

--------------------------------------------------
## FIXTURES
--------------------------------------------------

Prefixo `RTAW-20260902T1608-`. Seller QA handle **restaurado** `fleahub-demo-ux`. Lives de fixture `ended`. Seller2 `187dfec9-…` / buyer2 `b379f82e-…` em `*.fleaber.test`.
