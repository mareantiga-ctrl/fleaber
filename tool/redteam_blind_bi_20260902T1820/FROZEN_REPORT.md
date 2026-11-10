# FROZEN_REPORT — RED TEAM CEGO BI

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido: NÃO)

TOTAL P0–P3 abertos: 3
```

**VEREDICTO:** `FAIL_P2`

```
AUDITOR: REDTEAM_BLIND_BI_HUB_EDGE_POS_ATBE_v1
FROZEN_AT: 2026-09-02T18:35:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BI1, BI2, BI3, BI4, BI5, BI6, BI7]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (Session de gorjeta criada `cs_test_a1DGIaMQ…`; **não** paguei — `STRIPE_SECRET_KEY` ausente no env do auditor) · actors JWT B1/S1/B2/S2/S3 · `service_role` só fixture / observação. Prefixo `RTBI-20260902T1820-`. Código **não** corrigido. Produção intocada. FASE 4 não iniciada.

BC/AW/AQ/AK **não lidos** como roteiro. Poço: VOD sem Edge, tip capture alheia, CORS/Connect hijack, RPC oráculo.

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
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO (fora do poço Hub; tip `amount_eur=999999` → `Tip amount too high`)
10. Buyer manipula qty autoritativa — NÃO (não exercido checkout marketplace)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO
13. Refund excede captura — NÃO (`refund-order` buyer encomenda inexistente 404)
14. Release+refund cria dinheiro líquido — NÃO (fora de poço)
15. Payout duplica Transfer — NÃO (Connect POST `user_id` alheio 400)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO (stock anon scheduled `live_item_not_found`)
19. Cross-user financeiro — NÃO (tip seller swap 400; settle unpaid B2 sem captura)
20. Cross-user dados sensíveis — NÃO (stream_key REST 42501; embed `lives(*)` PGRST200/42501; complete-mux/LiveKit 403; storage objectos alheios `[]`)
21. Buyer assume seller/admin — NÃO (`create-mux-live` buyer 403)
22. Seller assume buyer/admin — NÃO (S1 `complete-mux` live S2 403)
23. Reviews forjadas — NÃO (fora de poço)
24. RPC SECURITY DEFINER perigoso executável — PARCIAL (`batata_live_is_broadcasting` anon = P3; FOMO scheduled `ok=true` sem fila nesta fixture)
25. RLS crítico quebrado — NÃO (`lives` tabela 401/403 anon e JWT)
26. Edge confia total do cliente — NÃO (`tip_id` 400; `buyer_id` no resolve-mux ignorado; CORS não reflecte evil) — **parcial:** `web_return_origin` IP decimal canonicaliza para loopback allowlisted
27. Regressão funcional (happy path partido) — NÃO (auditor não alterou código)
28. Saturação atingida — NÃO (discovery ainda selecciona playback cru; sanitizer IP aberto)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------

Exactos BC/AW da lista do prompt — **não redescobertos como findings** (fechados neste run):

| Exacto (não contar) | Resultado |
|---------------------|-----------|
| scheduled+VOD na `hub_lives_public` | BLOCKED — S1 publicado: `mux_vod_playback_id=null` e `mux_playback_id=null` em scheduled |
| draft `is_active` na grelha `hub_lives_public` | BLOCKED — draft+active `n=0` |
| tip GET `No such checkout.session` | BLOCKED — session forjada → «Pagamento ainda não confirmado» 400 |
| `total_qty` anon | BLOCKED — 42501 `permission denied for function batata_live_item_total_qty` |

Outros fechados (não exactos, não contar): `tip_id` cliente 400; tip scheduled/ended 400 broadcasting; CORS Origin evil → `https://fleaber.pt`; complete-mux / LiveKit cruzados 403; handle_suggested unpublished `found=false`; embed stream keys falhou; settle unpaid B2 sem captura.

Atrofia da lista exacta: **0**. Não `ATROFIA_ABORT`.

--------------------------------------------------
## FINDINGS
--------------------------------------------------

### P2-BI7 — `hub_lives_discovery_public` publica `mux_vod_playback_id` cru; CDN Mux serve HLS; Edge `resolve-mux-playback` 404

**Lentes:** BI7, BI1, BI5

**O que isto é:** O fecho ATBE na vitrine `hub_lives_public` anula playback live fora de `live`+active e VOD fora de `ended`. O feed de descoberta (`hub_lives_discovery_public`) continua a seleccionar `l.mux_playback_id` e `l.mux_vod_playback_id` **sem** esse `CASE`. Um anon constrói `https://stream.mux.com/{id}.m3u8` e vê o manifesto HLS — **sem** passar na Edge.

**Actor:** anon (REST views + GET CDN)

**Pré:** vendedor lab `fleahub-demo-ux` na vitrine; lives fixture com VOD real de staging `8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8`.

**Repro:**
1. `GET /rest/v1/hub_lives_public?id=eq.{scheduled}` → `mux_vod_playback_id=null`, `mux_playback_id=null`
2. `GET /rest/v1/hub_lives_discovery_public?id=eq.{scheduled}` → ambos os IDs preenchidos
3. `GET https://stream.mux.com/8cje21NKdUUro21jGdEv2UlfmWLD7TAMIWi2W01H5Gb8.m3u8` → `200` `#EXTM3U` 1280×720
4. `POST resolve-mux-playback` `{live_id: scheduled}` → `404 live_not_public`

O mesmo VOD aparece na discovery de um directo **ainda no ar** (`status=live` `is_active=true`) enquanto `hub_lives_public` anula o VOD e só mostra o playback live.

**Esperado:** o canal público (vitrine **e** descoberta) alinha com a Edge: VOD só `ended`; live play só broadcasting.

**Obtido:**
- S1 publicado scheduled `6bdfa1e2-…`: public anula; discovery expõe VOD+playback
- S1 publicado live `094f3276-…`: public `mux_playback_id` live, VOD null; discovery VOD+playback
- CDN `cdn_extm3u=true` status 200
- S2 não publicado (handle imutável via PATCH): discovery **ainda** lista scheduled+live via slug do nome, com os mesmos IDs — a descoberta **não** exige `hub_published` para `scheduled+is_active`

**Porque P2:** bypass comprovado da Edge (HLS real). Não é P0/P1: não há captura nem mint; o ID Mux tem de existir na row (resto de gravado / fixture). Classe única (scheduled e ao-ar = a mesma coluna crua).

---

### P2-BI2 — `web_return_origin` IPv4 decimal / `127.1` / hex / octal → 303 `https://127.0.0.1/wallet`

**Lentes:** BI2

**O que isto é:** `sanitizeWebReturnOrigin` faz `new URL(raw)` e aceita o hostname **já canonicalizado** `127.0.0.1` (allowlist de dev). Formas que o WHATWG trata como loopback passam.

**Actor:** browser, **sem JWT** (GET `create-connect-account`)

**Repro:**
```
GET /functions/v1/create-connect-account?web_return_origin=https://2130706433
GET …?web_return_origin=https://127.1
GET …?web_return_origin=https://0x7f000001
GET …?web_return_origin=https://0177.0.0.1
```

**Esperado:** só hosts literais `fleaber.pt` / `localhost` / `127.0.0.1` escritos assim; IP dword/octal/hex rejeitados.

**Obtido:** os quatro → **303** `Location: https://127.0.0.1/wallet`.  
`https://evil.com`, `https://attacker.fleaber.pt`, userinfo, IPv6 `[::1]`, `https://2130706433.fleaber.pt` → HTML da app, **sem** Location hostil.

Connect POST `web_return_origin=evil` + `user_id` B1 com JWT S2 → 400 `Cannot create another user Stripe account`.

**Porque P2:** open-redirect para loopback (listener local pode apanhar o return do Connect). Não é P1: não redirecciona para `evil.com`; `localhost` literal já estava na allowlist de propósito. Classe única (4 encodings).

Gorjeta: POST aceitou `web_return_origin=https://2130706433` na Session `cs_test_a1DGIaMQ…`. GET settle **pago** (Location `{origin}/stripe-success?session_id=`) **não** foi exercido — sem `sk_test` no env. Mesmo sanitizer; lacuna honesta na captura.

---

### P3-BI1 — anon executa `batata_live_is_broadcasting` (oráculo UUID)

**Lentes:** BI1

**O que isto é:** o SQL histórico revoga EXECUTE a `anon`. Em staging o RPC responde `200 true/false` com a chave anon.

**Repro:** `POST /rest/v1/rpc/batata_live_is_broadcasting` `{p_live_id}` sem JWT.

**Obtido:** live no ar → `true`; UUID aleatório → `false`; draft → `false`.

**Porque P3:** oráculo binário. Os UUIDs no ar já estão na discovery. Não enumera VOD nem chaves.

--------------------------------------------------
## BLOQUEADOS (amostra)
--------------------------------------------------

| Prova | Resultado |
|-------|-----------|
| `hub_lives_public` draft/error | `n=0` |
| `hub_lives_public` scheduled S1 | listed, playback/VOD **null** |
| `hub_lives_public` live S1 | playback live, VOD **null** |
| `hub_lives_public` ended S1 | VOD preenchido, playback **null** |
| FOMO draft | `live_not_public` |
| FOMO scheduled S1 | `ok=true` items `[]` (fila não reproduzida — itens scheduled não entram nas views) |
| stock anon scheduled | `live_item_not_found` |
| stock anon ended | `live_item_not_found` |
| stock seller2 ended **próprio** | `ok=true` (gestão) |
| stock S1 ended de S2 | `live_item_not_found` |
| `total_qty` anon | 42501 |
| `batata_resolve_handle` `rtbi1820s3sug` unpublished | `found=false` |
| REST `lives` anon/JWT | 401/403 |
| embed `hub_lives_public?select=lives(*)` | PGRST200 / 42501 |
| `resolve-mux` scheduled/draft/error/live-off | 404 `live_not_public` |
| `complete-mux-live` B1 / S1 vs live S2 | 403 |
| `livekit-mux-publish` token B1 / S1 | 403 |
| `create-mux-live` buyer | 403 |
| CORS evil / subdomain / chrome-extension | `Allow-Origin: https://fleaber.pt` |
| CORS `http://127.0.0.1:4173` | reflecte (dev, allowlist) |
| tip `tip_id` cliente | 400 |
| tip scheduled / ended | 400 broadcasting |
| tip `seller_id` ≠ owner | 400 |
| GET settle unpaid B2 / anon | texto «ainda não confirmado», sem 303 |
| GET settle `cs_test_aFORGED_…` | 400 sem oráculo Stripe |
| tip `amount_eur=999999` | 400 too high |
| storage `fleaber_private` objectos B2/S1 | `[]` (só pasta do próprio uid) |
| `refund-order` buyer | 404 |
| OCR sem device token | 401 |
| `create-payment-intent` `buyer_id` alheio | 400 missing metadata |

Estados `ao_vivo` / `idle` / `paused`: INSERT 23514 (check da tabela) — não há row para `resolve-mux` nesses labels.

--------------------------------------------------
## LENTES
--------------------------------------------------

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| BI1 Hub/FOMO | SIM | P3 broadcasting anon; FOMO scheduled `ok` sem impacto de fila |
| BI2 origin/CORS/Connect | SIM | P2 IP canonical |
| BI3 tip settle | SIM | unpaid B2 BLOCKED; captura TEST **não** paga (lacuna) |
| BI4 Edge body | SIM | `tip_id` / amount / seller_id / buyer_id BLOCKED |
| BI5 Mux/LiveKit | SIM | cruzado 403; resolve estados novos 404 |
| BI6 storage | SIM | objectos alheios BLOCKED |
| BI7 Hub+Edge+CDN | SIM | **P2** discovery VOD + CDN |

--------------------------------------------------
## INVARIANTES (A–L) neste poço
--------------------------------------------------

| ID | Estado |
|----|--------|
| A Stripe cobra contrato | NÃO COMPROVADO (sem pagamento TEST da gorjeta) |
| B cliente não define preço | HOLD no teto da gorjeta |
| C–K núcleo caixa | NÃO COMPROVADO neste poço Hub |
| L autoridade | HOLD Mux/LiveKit owner; FALHA parcial no sanitizer de origin |

--------------------------------------------------
## TÁCTICAS
--------------------------------------------------

- Anon Hub: views + FOMO + stock + broadcasting + CDN Mux
- ≥2 Edges hostis: `resolve-mux-playback`, `create-live-tip-checkout`, `create-connect-account`, `complete-mux-live`, `livekit-mux-publish`, `create-mux-live`, `refund-order`, `ingest-ocr-reservation`, `create-payment-intent`
- Settle tip session alheia unpaid (B2 + anon)
- SESSION criada ≠ captura (Session `cs_test_a1DGIaMQ…` unpaid)
- Flutter ≠ fronteira (REST + Edge + CDN)

Lacuna: sem `sk_test` no env → não confirmei Location pós-captura da gorjeta nem settle B2 duma Session **paga**.

--------------------------------------------------
## FIXTURES
--------------------------------------------------

Prefixo `RTBI-20260902T1820-`. Lives criadas foram marcadas `ended` `is_active=false` no fim de cada passe. S2 `hub_published` ficou `false` (`handle_immutable_use_rpc` / telefone). S3 unpublished para handle_suggested.

Probes: `tool/redteam_blind_bi_20260902T1820/pass1.dart` · `pass2.dart` · `pass3.dart`  
Bruto: `pass1_findings.json` · `pass2_findings.json` · `pass3_findings.json`

--------------------------------------------------
## RESPOSTA FINAL (checklist 28)
--------------------------------------------------

```
1. P0 aberto encontrado: NÃO
2. Quantos P0: 0
3. P1 aberto encontrado: NÃO
4. Quantos P1: 0
5. Buyer manipula preço autoritativo: NÃO
6. Buyer manipula qty autoritativa: NÃO
7. Seller falsifica pagamento plataforma: NÃO
8. JWT cria saldo/fundos: NÃO
9. Refund excede captura: NÃO
10. Release+refund cria dinheiro líquido: NÃO
11. Payout duplica Transfer indevidamente: NÃO
12. Stock=1 duas vendas válidas: NÃO
13. Stock=1 duas capturas líquidas permanentes: NÃO
14. Bypass capacidade/reserva: NÃO
15. Cross-user financeiro: NÃO
16. Cross-user dados sensíveis: NÃO
17. Buyer assume seller/admin: NÃO
18. Seller assume buyer/admin: NÃO
19. Reviews forjadas/duplicadas: NÃO
20. RPC SECURITY DEFINER perigoso executável: PARCIAL (broadcasting anon)
21. RLS crítico quebrado: NÃO
22. Edge confia autoridade do cliente no total: NÃO (parcial origin IP)
23. Conclusão crítica NÃO COMPROVADA: SIM (gorjeta paga / Location decimal)
24. Regressão funcional (código alterado por ti): NÃO
25. Último passe nova classe P0/P1: NÃO
26. Saturação: NÃO
27. Produção tocada: NÃO
28. Fase 4 iniciada: NÃO

Poços: Hub/FOMO=SIM · origin/CORS/Connect=SIM · tip settle=SIM · Edge body=SIM · Mux/LiveKit=SIM · storage=SIM · composição CDN=SIM
ATROFIA (só redescobriu núcleo fechado): NÃO
```

**VEREDICTO:** `FAIL_P2`
