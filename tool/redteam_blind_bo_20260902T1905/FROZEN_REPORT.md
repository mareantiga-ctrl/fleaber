# FROZEN_REPORT — RED TEAM CEGO BO

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 4

```
AUDITOR: REDTEAM_BLIND_BO_HUB_EDGE_POS_BFBK_v1
FROZEN_AT: 2026-09-02T18:15:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BO1, BO2, BO3, BO4, BO5, BO6, BO7]
VEREDICTO: FAIL_P2
prefix: RTBO-20260902T1905
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BI/BC **não contados** (HOLD): `hub_lives_discovery_public` scheduled com `mux_vod_playback_id` null; GET `create-connect-account?web_return_origin=https://2130706433` (e `127.1` / `0x7f000001`) ainda 303 para `https://127.0.0.1/wallet` no Edge LIVE — classe exacta, não contar; tip GET forjado já não ecoa `No such checkout`.

---

## Missão

Depois do fecho discovery/CDN BFBK, ainda assisto VOD sem Edge ou tiro tip?

**Resposta:** sim, **assisto VOD sem Edge** — a tabela `lives` (anon e JWT) devolve `mux_vod_playback_id` que as views Hub anulam; a CDN Mux serve HLS. Tip unpaid B2 **não** credita.

---

## Findings abertos

### BO-P2-01 — tabela `lives` (anon) vaza VOD que Hub/discovery anulam; CDN serve HLS

- **Sev:** P2 · **Lente:** BO7/BO1 · **Actor:** anon (também buyer JWT)
- **Pré:** GRANT `select (… mux_vod_playback_id …)` em `lives` a `anon, authenticated`; RLS `status in (live, ended, scheduled)`. Pedir `stream_key` na mesma query → 401/403 (colunas secretas). Pedir só colunas «seguras» → 200.
- **Repro:**
  1. `GET /rest/v1/lives?id=eq.{ended_unpublished}&select=id,status,mux_vod_playback_id` (apikey anon, sem JWT)
  2. `GET https://stream.mux.com/{mux_vod_playback_id}.m3u8`
- **Esperado:** mesmo filtro que `hub_lives_public` / `hub_lives_discovery_public` (VOD só `ended` **e** loja publicada; scheduled/inactive/unpublished → null / 0 rows)
- **Obtido:**
  - Hub/discovery: scheduled `mux_vod_playback_id=null`; ended unpublished **[]**; live+inactive discovery **[]**
  - `lives` anon: 200 com o ID VOD nos quatro estados (scheduled, ended unpublished, live air, live inactive)
  - CDN: `200 #EXTM3U` 1280×720 (prova `pass3.json` p3.anon.vod.cdn; live `fb41ed20-1bc1-4f57-ad2c-fdf33a9f2af9`)
  - `resolve-mux-playback` scheduled / ended unpublished / live inactive → `404 live_not_public` (Edge alinhado às views; a tabela não)
- **Impacto:** visitante anónimo **assiste a gravação** de loja `hub_published=false` e de lives que o Hub ainda não trata como Gravados, **sem** passar no Edge. Sem Δ wallet / sem stream_key. ID Mux com `playback_policy=public` uma vez conhecido.
- **Nota de fixture:** o playback plantado (`8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8`) veio de um VOD real de staging. Em `ended` unpublished isto é o caminho real (`complete-mux-live` grava `mux_vod_playback_id`). Em `scheduled`, `create-mux-live` não preenche VOD — o GRANT/RLS continua errado se a coluna estiver preenchida (stale / reopen service).
- **Prova:** `pass2.json` p2.jwt.vod.ended_unpub + p2.anon.ended_unpub; `pass3.json` p3.anon.vod.cdn; `pass1.json` bo7.vod.bypass.edge

### BO-P2-02 — catálogo Hub de artigos 401 para visitantes (revoke broadcasting)

- **Sev:** P2 · **Lente:** BO1 · **Actor:** anon
- **Pré:** BFBK `revoke execute on batata_live_is_broadcasting from anon`. Views `hub_live_items_public` e `hub_live_items_discovery_public` chamam essa função (invoker).
- **Repro:** `GET /rest/v1/hub_live_items_public?limit=3` (anon)
- **Esperado:** 200 lista (função corre como owner da view) ou 200 `[]` — não 401
- **Obtido:** anon `401 permission denied for function batata_live_is_broadcasting`. Buyer JWT `200` (tem GRANT).
- **Impacto:** vitrine de artigos do directo **partida para Hub web anónimo**. Fail-closed (não vaza stock). Mesma causa nas duas views — **um** finding.
- **Prova:** `pass2.json` p2.hub.items.401 / p2.hub.items.disc.401; `pass1.json` notas `bo1.hub_live_items_public.*`

### BO-P3-01 — `batata_resolve_handle` enumera loja desligada via `handle_suggested`

- **Sev:** P3 · **Lente:** BO1 · **Actor:** anon
- **Pré:** S2 `hub_published=false` `handle=null` `handle_suggested=rtbo1905s2sug`
- **Repro:** `POST /rest/v1/rpc/batata_resolve_handle` `{"p_handle":"rtbo1905s2sug"}`
- **Esperado:** `found=false` se a vitrine está vazia
- **Obtido:** `found=true` `profile_id=d15e351f-…` `hub_published=false`. `hub_profiles_public` []. Discovery **lista** scheduled/air unpublished com `seller_handle=rtbo1905s2sug` e nome «Rtbo S2 Hidden». Comentário SQL (`hub_discovery_handle_gate`) descreve isto como acesso live/gravado — enum de loja não publicada na mesma.
- **Impacto:** UUID + slug de loja desligada. Sem PII financeira. Sem VOD extra além de BO-P2-01.
- **Prova:** `pass1.json` bo1.handle.sug.unpub; notas discovery `air_unpub` / `sched_unpub`

### BO-P3-02 — FOMO / `hub_lives_public` aceitam `status=live` com `is_active=false`

- **Sev:** P3 · **Lente:** BO1 · **Actor:** anon
- **Pré:** live `status=live` `is_active=false`
- **Repro:** `GET hub_lives_public?id=eq.…` ; `rpc batata_hub_live_fomo_snapshot`
- **Esperado:** fora da vitrine (alinhado a `batata_live_is_broadcasting` e discovery, que devolve [])
- **Obtido:** `hub_lives_public` 200 (playback null); FOMO `{"ok":true,"items":[],"live_status":"live","is_active":false}`. `resolve-mux-playback` 404. Discovery [].
- **Impacto:** oráculo de UUID «live» inactivo na vitrine pública. Sem HLS extra.
- **Prova:** `pass1.json` bo1.fomo.live_inactive; `pass2.json` p2.pub.inactive

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Exact discovery scheduled+VOD | BO1 | `mux_vod_playback_id=null` nas views |
| Exact `web_return` 2130706433 / 127.1 / 0x7f000001 | BO2 | LIVE ainda 303 → `https://127.0.0.1/wallet` (Edge sanitizer BFBK **não** observado). Classe exacta — não contar. `0177.0.0.1` idem |
| IPv6 mapped `[::1]` `[::ffff:127.0.0.1]` `[::ffff:7f00:1]` `[::ffff:8.8.8.8]` | BO2 | sem 303 hostil (HTML wallet / 403 WAF) |
| DNS rebinding `localtest.me` `lvh.me` `nip.io` `xip.io` `evil.fleaber.pt` | BO2 | HTML wallet, sem Location hostil |
| CORS Origin evil / IPv6 / chrome-extension | BO2 | ACAO remapeado para `https://fleaber.pt` (não reflecte) |
| CORS localhost:porta | BO2 | reflecte (allowlist dev) |
| Exact tip `No such checkout` | BO3 | mensagem genérica «Pagamento ainda não confirmado» |
| Tip unpaid B2 GET settle | BO3 | tip `pending`; sem crédito |
| Client `tip_id` / `seller_id` mismatch / `buyer_id` spoof | BO4 | `Client tip_id is not allowed` / owner check / JWT ganha |
| Tip scheduled/ended | BO3 | `Tips only allowed while the live is broadcasting` |
| JWT `batata_settle_live_tip_from_stripe` | BO4 | 403 GRANT service_role |
| resolve-mux draft/scheduled/inactive/ended unpublished | BO5 | `404 live_not_public` |
| complete-mux / livekit seller2, buyer, anon | BO5 | 403 / 401 |
| create-mux-live buyer | BO5 | 403 só vendedor |
| Anon `batata_live_is_broadcasting` | BO1 | 401 (fecho BFBK observado nas RPC) |
| Anon `lives` com `stream_key` | BO1 | 401/403 coluna |
| Seller JWT PATCH reopen lives | BO7 | 403 table lives |
| Storage list buckets anon | BO6 | `200 []` |
| Storage object adivinhado | BO6 | 404 NoSuchKey / NoSuchBucket |
| Storage upload text/plain private | BO6 | 415 mime (não 200) |
| FOMO draft / unpublished / ghost | BO1 | `live_not_public` |
| FOMO air (qty agregada) | BO1 | `ok` esperado na vitrine ao ar |

**Não é finding:** `service_role` a inserir lives/VOD (fixture). Actor do exploit = anon/JWT.

**Falsos positivos descartados:** pass1 `GET lives` 403 — era o `select` a incluir `mux_stream_key`; as colunas VOD sozinhas passam (pass2/pass3). Upload JPEG não concluído (base64 do probe) — text/plain já 415.

---

## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| BO1 Hub/FOMO | SIM | P2 items 401; P3 handle_suggested; P3 live inactive |
| BO2 origin/CORS/Connect | SIM | HOLD (exactos IP; IPv6/DNS fechados no sanitizer/WAF) |
| BO3 tip settle | SIM | HOLD unpaid B2 |
| BO4 Edge body | SIM | HOLD tip_id / seller / buyer_id |
| BO5 Mux/LiveKit | SIM | HOLD complete/create/resolve estados |
| BO6 storage | SIM | HOLD |
| BO7 composição | SIM | P2 tabela lives → CDN sem Edge |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO (tip unpaid não completa)
12. JWT cria saldo/fundos — NÃO (settle tip 403)
13. Refund excede captura — NÃO COMPROVADO (fora poço)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO COMPROVADO (fora poço)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — PARCIAL: VOD de loja unpublished via `lives`+CDN (P2); stream keys 401
21. Buyer assume seller/admin — NÃO (complete-mux / create-mux 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO (settle tip JWT 403; broadcasting anon 401)
25. RLS crítico quebrado — PARCIAL: RLS `lives` + GRANT colunas VOD mais largo que as views Hub (P2)
26. Edge confia total do cliente — NÃO (tip_id rejeitado; complete-mux owner check)
27. Regressão funcional (happy path partido) — SIM: Hub artigos anon 401 (P2)
28. Saturação atingida — SIM nas 7 lentes; último passe sem classe nova P0/P1

ATROFIA (só exactos fechados): NÃO  
Poço Stripe TEST pago: NÃO (não exigido — tip unpaid B2 sem captura)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
