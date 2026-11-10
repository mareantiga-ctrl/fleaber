# FROZEN_REPORT — RED TEAM CEGO BU · Hub / Edge / Mux / tip · POS_BLBQ

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 2
P3 aberto: SIM → quantos: 1
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 3

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado? SIM
8. Quantos P3: 1

```
AUDITOR: REDTEAM_BLIND_BU_HUB_EDGE_POS_BLBQ_v1
FROZEN_AT: 2026-09-06T10:55:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BU1, BU2, BU3, BU4, BU5, BU6, BU7]
VEREDICTO: FAIL_P2
prefix: RTBU-20260906T1046
staging: fxdknzrqjenzqcvnwqqq
```

Staging · Stripe TEST · actors JWT B1/S1/B2/S2 · `service_role` só fixture / observação. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

Exactos BO/BI **reprovados e não contados:** `GET lives` Mux cols anon → 401/403; `web_return` `https://2130706433` → HTML wallet (sem 303 loopback); discovery scheduled **sem** `mux_vod_playback_id`; Hub items live inactiva → `[]`.

--------------------------------------------------
## CHECKLIST (28)
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO (fora de poço; tip amount teto servidor)
10. Buyer manipula qty autoritativa — NÃO COMPROVADO (poço Hub/Edge)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (tip unpaid Δwallet=0)
13. Refund excede captura — NÃO COMPROVADO (poço não era refund)
14. Release+refund cria dinheiro líquido — NÃO COMPROVADO
15. Payout duplica Transfer — NÃO COMPROVADO
16. Stock=1 duas vendas válidas — NÃO COMPROVADO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO (FOMO inactiva sem items)
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (storage GET alheio 400; list só pasta própria)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO
24. RPC SECURITY DEFINER perigoso executável — NÃO (`batata_settle_live_tip_from_stripe` 403 JWT)
25. RLS crítico quebrado — NÃO (`lives` 403 authenticated / 401 anon)
26. Edge confia total do cliente — NÃO (`tip_id` cliente recusado; complete-mux 403)
27. Regressão funcional (happy path partido) — NÃO
28. Saturação atingida — SIM (poços novos IPv6/nip.io/embed/tip unpaid/complete-mux/FOMO inactiva/storage)

Poços BU exercitados: Hub/FOMO=SIM · origin/CORS=SIM · tip settle=SIM · Edge body=SIM · Mux/LiveKit=SIM · storage=SIM · composição=SIM  
ATROFIA (só redescobriu exactos fechados): NÃO  
Pagamento TEST gorjeta: Session criada, **não** paga (poço unpaid B2). Captura paga NÃO COMPROVADA — lacuna honesta, não INCONCLUSIVO porque o poço era bypass unpaid.

--------------------------------------------------
## FINDINGS (contáveis)
--------------------------------------------------

### BU-P2-001 · BU1/BU7 · Discovery lista *scheduled* de Hub unpublished

**Actor:** anon  
**Pré:** S2 `hub_published=false`, handle vazio; live `status=scheduled` `is_active=false`.  
**Request:** `GET /rest/v1/hub_lives_discovery_public?id=eq.{id}&select=id,status,is_active,mux_playback_id,seller_handle`  
**Esperado:** 0 rows (montra unpublished).  
**Obtido:** 200 row `seller_handle=rtbu-20260906t1046-s2`, `mux_playback_id=null`, `mux_vod_playback_id=null`. `hub_lives_public` = `[]`.  
**Impacto:** vendedor que despublicou o Hub continua visível no feed de discovery com directo *agendado* (sem HLS). Não é VOD.  
**Repro:** fixture S2 unpublished + live scheduled; GET discovery.  
**Sev:** P2  
**Prova:** `pass1.json` `BU1-DISC-UNPUB-SCHED`; live `b070dff8-bf05-4009-a214-a56f7b7fdb3b`.

### BU-P2-002 · BU1/BU5/BU7 · Directo unpublished no ar: discovery + resolve-mux dão playback; Hub page esconde

**Actor:** anon  
**Pré:** S2 `hub_published=false`; live `status=live` `is_active=true` com `mux_playback_id`.  
**Request:**  
1. `GET hub_lives_public?id=eq.{id}` → `[]`  
2. `GET hub_lives_discovery_public?id=eq.{id}` → row + `mux_playback_id`  
3. `POST /functions/v1/resolve-mux-playback {"live_id"}` → `source=live_active` + URL `stream.mux.com/{id}.m3u8`  
**Esperado:** se unpublished esconde o vendedor, as três superfícies alinhadas (404 / sem playback).  
**Obtido:** Hub page esconde; discovery e Edge devolvem playback de directo **ao ar**. CDN Mux com id de fixture não serviu HLS real (id inventado) — leak do *id* + URL Edge comprovado; assistir CDN real **não** demonstrado neste id.  
**Impacto:** política partida (`hub_published` só na view Hub, não no feed nem no `batata_live_is_broadcasting`). Quem “despublica o Hub” e testa um directo aparece na discovery com playback. Não é VOD prematuro nem live *inactiva*.  
**Repro:** pass1 `BU1-UNPUB-AIR-PB` + pass3 `BU5-RESOLVE-UNPUB-AIR` (`115cd621-9072-4c34-bbeb-b28ad5580faf`).  
**Sev:** P2 (não P1: directo *broadcasting* é acto público; sem prova CDN HLS real; sem dinheiro).

### BU-P3-001 · BU1 · FOMO `ok` em live `is_active=false` scheduled (sem items)

**Actor:** anon  
**Pré:** live published-seller `status=scheduled` `is_active=false`.  
**Request:** `POST /rest/v1/rpc/batata_hub_live_fomo_snapshot {"p_live_id"}`  
**Esperado (poço):** `live_not_public` para qualquer `is_active=false`.  
**Obtido:** `{"ok":true,"items":[],"is_active":false,"live_status":"scheduled"}`.  
Contraste: `status=live` `is_active=false` → `live_not_public`; items Hub inactiva → `[]`.  
**Impacto:** FOMO segue `hub_lives_public` (scheduled entra na view). Sem stock.  
**Sev:** P3  
**Prova:** pass1 `BU1-FOMO-sched-empty`.

--------------------------------------------------
## DESCARTADOS / HOLD (não contar)
--------------------------------------------------

| Poço | Resultado |
|------|-----------|
| Anon/B1 `GET lives` Mux cols | 401 profiles / 403 lives — HOLD (exacto fechado) |
| Embed `lives(*)` noutro REST | 401/403 — HOLD |
| `mux_playback_id` live **inactiva** via discovery/public | `[]` / null — HOLD |
| resolve-mux inactive / scheduled / ended unpublished | 404 `live_not_public` — HOLD |
| VOD prematuro CDN | B1 não lê `lives`; fixtures fake id — sem HLS real |
| IPv6 mapped `[::ffff:127.0.0.1]` / `[::1]` web_return | 200 HTML wallet, **sem** 303 hostil — HOLD |
| `127.0.0.1.nip.io` / sslip / localtest.me / lvh.me | idem — HOLD |
| `https://2130706433` | HTML, sem 303 (exacto, não contar) |
| CORS Origin hostil | `ACAO=https://fleaber.pt` (não reflecte) — HOLD |
| CORS `http://localhost:5173` | reflecte (dev allowlist) — residual, não finding |
| complete-mux / livekit token / egress B2 vs S1 | 403 — HOLD |
| create-mux buyer | 403 só vendedor — HOLD |
| egress-cleanup secret errado | 401 — HOLD |
| tip `tip_id` cliente | 400 not allowed — HOLD |
| tip seller ≠ owner | 400 — HOLD |
| tip live inactiva | 400 broadcasting — HOLD |
| GET settle unpaid B2/anon | «Pagamento ainda não confirmado»; tip `pending`; Δwallet=0 — HOLD |
| RPC settle JWT | 403 function denied — HOLD |
| `fleaber_private` `object/public` | 404 NoSuchBucket — HOLD |
| List/GET cruzado storage | B1 lista **só** o próprio uid; B2 GET ficheiro B1 = 400; B1 GET ficheiro S1 = 400. List pastas top-level = prefixes dos *próprios* objectos (B2 `[]`). **Não é P1.** |
| chat_media public=true | residual conhecido; anon upload RLS 403; list `product_photos` prefix |

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| BU1 Hub/FOMO | SIM | P2×1 scheduled unpublished; P3 FOMO scheduled |
| BU2 origin/CORS/Connect | SIM | não |
| BU3 tip settle unpaid B2 | SIM Session + GET + RPC | não |
| BU4 Edge body | SIM complete-mux / livekit / tip_id | não |
| BU5 Mux/LiveKit | SIM REST, embed, resolve, CDN tentativa | P2 composição unpublished air |
| BU6 storage | SIM list/GET/upload | não (FP list cruzada) |
| BU7 composição | SIM discovery∥resolve∥Hub page | mesmo P2-002 |

--------------------------------------------------
## INVARIANTES (órbita Hub/Edge)
--------------------------------------------------

A–L núcleo checkout: não o poço. Nesta órbita: E (JWT saldo) HOLD; L (tip autoridade) HOLD.

--------------------------------------------------
## ARTEFACTOS
--------------------------------------------------

- `tool/redteam_blind_bu_20260906T1046/pass1.dart` + `pass1.json` + `pass1.log`
- `pass2.dart` / `pass2.log` (descida storage; FP cruzado)
- `pass3.dart` + `pass3.json` + `pass3.log` (GET binário status-only; resolve unpublished)
- Fixtures lives `RTBU-20260906T1046*` terminadas após freeze.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO INICIAR FASE 4.**
