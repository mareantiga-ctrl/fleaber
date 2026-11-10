# FLEABER — RED TEAM CEGO AQ
## Auditor independente · PÓS-FECHO AHAM · HUB WEB / EDGE / DEEP LINK · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AQ_HUB_EDGE_POS_AHAM_v1
FROZEN_AT: 2026-09-02T09:20:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AQ1, AQ2, AQ3, AQ4, AQ5, AQ6, AQ7]
VEREDICTO: FAIL_P2
prefixo_fixtures: RTAQ-20260902T1006-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas: `tool/redteam_blind_aq_20260902T1006/pass{1,2}.json`.

Anti-atrofia: 0/2 P2 = lista exacta AK/M. Exactos AK **fechados** neste run (GRANT Hub 200, FOMO ended sem `reserved_full`, REST hitch ended `[]`, tip ended 400). Não repetidos: Hub paused items, invite enum, dual Session clássico, mint pós-payout.

Poço AHAM: GRANT + filtro `reserved_full` + broadcasting nas views + tip «só live activa». **Não** tapam: (a) Edge de gorjeta/Mux usam `is_active && status!=ended` em vez de `batata_live_is_broadcasting()` — `scheduled+is_active` abre Session e HLS; scheduled inactivo serve VOD cache; (b) GRANT EXECUTE a anon em `batata_live_item_stock` / `batata_live_item_total_qty` oráculo de preço/qty com UUID; (c) hitch `quantity=null` no REST do player durante o directo, oculto no Hub.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (hitch selou `contract_unit_cents=500` = preço live do vendedor, não 40 € catálogo nem valor do cliente)
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
20. Cross-user dados sensíveis — NÃO (stream key / LiveKit 403; hub `select=*` sem keys)
21. Buyer assume seller/admin — NÃO (`create-mux-live` 403; PATCH `user_type` não escalou)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora da lente)
24. RPC SECURITY DEFINER perigoso executável — SIM (`batata_live_item_stock` / `total_qty` anon; `mark_sold` / settle tip 42501)
25. RLS crítico quebrado — NÃO (`lives` anon 42501; hitch ended buyer `[]`)
26. Edge confia total do cliente — NÃO (`tip_id` 400; `web_return_origin` evil sem Location; CORS não reflecte attacker) — **parcial:** tip/mux não chamam `broadcasting()`
27. Regressão funcional (happy path partido) — NÃO (Hub items anon 200; tip live+active 200)
28. Saturação atingida — NÃO (P2 scheduled-gate aberto)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## VEREDICTO
--------------------------------------------------

Fronteira **dinheiro**: GET settle forjado / unpaid **não captura**. Tip ended published **400**. Hitch ended some do REST buyer. `complete-mux-live` / LiveKit cruzados 403. Webhook sem sig 400. Connect evil **sem** Location hostil.

Falham superfícies **Hub/Edge de vitrine vs broadcasting**:

1. **P2** — gorjeta e Mux aceitam `scheduled+is_active` (e Mux serve VOD de scheduled inactivo) enquanto `batata_live_is_broadcasting()=false`.
2. **P3** — anon lê stock/preço de item de gravado via RPC GRANT (UUID).
3. **P3** — hitch `quantity=null` no REST durante o directo; Hub/FOMO vazios.

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P2 · RTAQ-AQ4-TIP-NOT-BROADCASTING
**Lentes:** AQ4, AQ7  
**Actor:** buyer JWT (create) · anon GET (settle)

**O quê:** AHAM diz tip **só** com live activa. A Edge implementa `is_active===true && status!=="ended"`, **não** `batata_live_is_broadcasting()`. Fixture `status=scheduled` `is_active=true` (live `67fb68d2-…`):

- RPC `batata_live_is_broadcasting` → **false**
- Hub items `[]`; FOMO `ok` items `[]`
- `POST create-live-tip-checkout` → **200** Session `cs_test_a1JePQI7tMboabniZqsN9WEiCQm6AiXB1EOVCFjTk0syskDVnhwTIA4nyE` (1,00 €)
- Pass 1: `cs_test_a1qNEVpyQe8zaK4GqcPUKazOpD5EvLYPVkzBfBMvGbM9piYSbS3DdlMvWW` · `live_tips.status=pending`
- GET settle → «Pagamento ainda não confirmado»

**Não é** tip ended published (AK4 — aqui **400** `Tips only allowed while the live is broadcasting.`). Session criada ≠ captura.

**Prova:** `pass2.json` `tip_sched_act2` + `scheduled_active_surfaces`; `pass1.json` `tips.scheduledActive`.

**Impacto:** Checkout Stripe TEST em directo que **ainda não está no ar**; spam de Sessions. Sem crédito.  
**Severidade:** P2.

---

### P2 · RTAQ-AQ5-MUX-SCHEDULED-GATE
**Lentes:** AQ5  
**Actor:** anon

**O quê:** `resolve-mux-playback` permite playback se `hub_lives_public` contém a live (scheduled entra na view) **ou** se `is_active` e status não é `ended`. Não usa `batata_live_is_broadcasting()`.

1. `scheduled+is_active=true` (`67fb68d2-…`) → **200** `source=live_active` HLS `…m3u8?reduced_latency=true` `is_live:true` apesar de broadcasting=false.
2. `scheduled+is_active=false` com `mux_vod_playback_id` (`9a3665d5-…`) → **200** `source=cache` VOD — trata inactivo como «ended» e serve o playback de cache **antes** do directo existir.

**Não é** mux draft unpublished (AK/M — aqui draft **404** `live_not_public`). **Não é** HLS de unpublished *live* (E0817 / hold AK).

**Prova:** `pass2.json` `mux_scheduled_active` + `mux_scheduled_pub`.

**Impacto:** URL Mux de um agendado (HLS «ao vivo» falso ou VOD prematuro). Precisa de `live_id` (a view Hub lista scheduled publicados).  
**Severidade:** P2.

---

### P3 · RTAQ-AQ1-STOCK-RPC-ANON
**Lente:** AQ1  
**Actor:** anon (apikey)

**O quê:** AHAM `GRANT EXECUTE` de `batata_live_item_stock` (e, neste run, `batata_live_item_total_qty`) a **anon**. A função é SECURITY DEFINER **sem** gate de vitrine/broadcasting. Item `reserved_full` de gravado `651de04b-…` (Hub/FOMO/REST buyer **não** listam):

Anon `POST rpc/batata_live_item_stock` → **200** `ok:true`, `price:7`, `available_qty:1`, `total_qty:1`, `live_status:ended`, `ref_code`.  
`batata_live_item_total_qty` → **200** `1`.  
UUID aleatório → `live_item_not_found` (não enumera). `batata_live_is_draft` / settle tip **42501**.

**Não é** Hub items 401 (AK1-GRANT — views **200**). **Não é** exact AK1-STOCK-RPC-BUYER (JWT); agora **sem login**. UUID não sai da vitrine ended.

**Prova:** `pass1.json` `stock_anon.endedRf`; `pass2.json` `stock_ended_full` + `extra_rpc_anon`.

**Impacto:** oráculo de stock/preço de gravado se o UUID vazar por outro canal.  
**Severidade:** P3.

---

### P3 · RTAQ-AQ1-HITCH-NULLQTY-REST-VS-HUB
**Lentes:** AQ1, AQ7  
**Actor:** buyer JWT (REST) · anon (Hub)

**O quê:** Hitch `marketplace_product` `quantity=null` `price=5` em directo **broadcasting**. View Hub exige `quantity>0` → **[]**. REST buyer (policy stock+broadcasting) → linha `price:5`. FOMO só o `live_only` irmão, não o hitch. INSERT `orders` → **201** `contract_unit_cents=500` (preço live do vendedor, não 40 € do SKU). Edge `create-payment-intent` 400 metadata (sem Session). Após `ended`, REST buyer **[]** (AHAM hitch ended fechado).

**Não é** REST hitch ended (AK1-REST — fechado). Divergência **durante** o directo: player REST ≠ loja Hub.

**Prova:** `pass1.json` `rest_hitch_during_live` + `order_hitch_contract`; `pass2.json` `hitch_on_air` + `hitch_after_end`.

**Impacto:** vitrines desalinhadas; pedido pendente a 5 € sem captura neste harness.  
**Severidade:** P3.

--------------------------------------------------
## HOLDS (fronteira aguentou)
--------------------------------------------------

| Lente | Ataque | Resultado |
|-------|--------|-----------|
| AQ1 | Hub items anon GRANT | **200** (AK1-HUB-ITEMS-GRANT fechado) |
| AQ1 | FOMO ended `reserved_full` | items `[]` (AK1-FOMO fechado) |
| AQ1 | REST hitch após ended | buyer `[]`; seller vê a linha |
| AQ1 | leftover `ended`+`is_active` unpublished discovery | `[]` |
| AQ1 | draft unpublished Hub/FOMO/mux | `[]` / `live_not_public` / mux 404 |
| AQ1 | `handle_suggested` após lives ended | `found=false` |
| AQ1 | produto unlisted Hub | `[]` |
| AQ1 | embed `lives(*)` | 42501 |
| AQ1 | Unicode/`hidden`/`reserved` em `live_items.status` | INSERT **400** check |
| AQ1 | `paused` / `ended\\u200b` / `ao_vivo` em `lives.status` | INSERT **400** check |
| AQ1 | `batata_live_is_broadcasting` unpublished live | `true` — alinhado a discovery E0817; **não** reaberto |
| AQ1 | tip unpublished `live+active` | 200 Session — alinhado a discovery; FOMO `live_not_public` |
| AQ2 | CORS `attacker.fleaber.pt` / `chrome-extension://` / `evil.com` | **não** reflecte; `fleaber.app` / `127.0.0.1:4173` / `localhost:9999` sim (allowlist) |
| AQ2 | Connect `web_return_origin` evil / userinfo / path `../../evil` | HTML ou 303 `/wallet` no host allowlist; `127.0.0.1:9` 303 **allowlist localhost** (KLM/AK) |
| AQ3 | GET settle `cs_test_rtaq_forged_*` | 400 Stripe |
| AQ3 | GET tip settle unpaid (+ B2, + endpoint PI) | não confirmado / 402; `pending` |
| AQ4 | `tip_id` cliente | 400 |
| AQ4 | tip ended published | 400 broadcasting (AK4 fechado) |
| AQ4 | tip leftover ended+is_active / scheduled inactivo / draft | 400 |
| AQ4 | `seller_id` alheio / self / amount 0.01 / 9999 | 400 |
| AQ4 | ingest-ocr token fake | 400 `missing_line_hash` |
| AQ4 | `delete-test-account` `user_id` seller | 403 allowlist nuke |
| AQ4 | `stripe-webhook` sem assinatura | 400 |
| AQ5 | buyer `create-mux-live` (+ PATCH `user_type`) | 403 authz |
| AQ5 | seller2 `complete-mux-live` live A | 403 |
| AQ5 | buyer LiveKit `step=token` | 403 |
| AQ6 | list `chat_media` / outros buckets | 200 `[]` |
| AQ6 | upload anon `chat_media` | 403 RLS |
| AQ7 | hitch ended → contrato 5 € | **NÃO** — REST some; contrato pass1 foi **durante** live |

--------------------------------------------------
## CONTABILIDADE (Stripe TEST)
--------------------------------------------------

Nenhuma captura. Checkout Sessions de gorjeta **unpaid**:

| Session | Contexto | `live_tips.status` após GET settle |
|---------|----------|-------------------------------------|
| `cs_test_a1EmONzLRAYHPGdAyrwMG41ViQIbK5BHuyDU1YRHEYvzTkpGoum4puYBAm` | live+active (happy) | não re-lido; unpaid |
| `cs_test_a1qNEVpyQe8zaK4GqcPUKazOpD5EvLYPVkzBfBMvGbM9piYSbS3DdlMvWW` | scheduled+is_active | `pending` (`a3263d01-…`) |
| `cs_test_a1JePQI7tMboabniZqsN9WEiCQm6AiXB1EOVCFjTk0syskDVnhwTIA4nyE` | scheduled+is_active pass2 | unpaid |
| `cs_test_a1nYiVffiGPqUt9kAY7ZE4ZNaNfQpQPTwqCuAjl0L6vBF8oO1MwzswIN82` | unpublished live (E0817) | unpaid |

Pedido hitch `431c60ad-…`: `contract_unit_cents=500`, `status=pendente`, sem Session.

--------------------------------------------------
## TÁCTICAS / LENTES
--------------------------------------------------

- Anon Hub exercitado (views + FOMO + resolve_handle + OpenAPI + GraphQL).
- ≥2 Edges hostis: `resolve-mux-playback`, `create-live-tip-checkout`, `create-connect-account`, `create-payment-intent`, `complete-mux-live`, `livekit-mux-publish`, `refund-order`, `ingest-ocr-reservation`, `delete-test-account`, `stripe-webhook`.
- ≥1 settle GET com `session_id` forjado e Sessions reais unpaid.
- Session criada ≠ captura (gorjeta scheduled).
- Flutter ≠ fronteira (REST/RPC/Edge directos).

--------------------------------------------------
## FIXTURES
--------------------------------------------------

Prefixo `RTAQ-20260902T1006-`. Seller QA handle **restaurado** `fleahub-demo-ux`. Lives de fixture `ended`. Seller2 `fe661102-…` / buyer2 `432a4e49-…` em `*.fleaber.test`.
