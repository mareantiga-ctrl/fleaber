# FROZEN_REPORT — RED TEAM CEGO EQ

## CONTAGEM

```
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0
```

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_EQ_DISPUTE_SHIP_MARATHON_POS_OPEN_v1
FROZEN_AT: 2026-09-06T20:00:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EQ1, EQ2, EQ3, EQ4, EQ5, EQ6, EQ7, EQ8]
probes_na_tabela: 35 (≥24)
classes_novas: 21
VEREDICTO: PASS_CEGO_SATURADO
```

Prefixo: `RTEQ-20260906T1950`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`, plant release, oráculos). Código **não** corrigido.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `20e2ec8a-0012-4278-b222-9e8a48e463e4` · S2 `96b2c945-a49c-4345-8673-3e9539966e3d`

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora do poço; selo portes intacto)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (C3 Δ 0; C4 1 efeito crédito XOR disputa)
13. Refund excede captura — NÃO (refund 403 `order_refund_blocked_shipped`)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (GET B2 as B1 404; S2 disputa/label `[]`; JWT SELECT revoke 403)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (revoke `../` true só no path literal; objecto B2 intacto 70b)
25. RLS crítico quebrado — NÃO (disputa alheia 403; GRANT revoke 403)
26. Edge confia total do cliente — NÃO (selo portes pós-pago intacto)
27. Regressão funcional (happy path partido) — NÃO (prova signed 201 `4a6daf49-…` + 2.º `151e39e8-…`)
28. Saturação atingida — SIM (35 probes, 21 classe_nova, ≥2 pagos+disputa, P0–P2=0)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Proof canónica; sem traversal; sem loot. Revoke sticky.  
Disputa: actor + janela. Portes/label imutáveis pós-`cs_`/pago.  
Race disputa∥refund∥release sem mint.

**Resposta:** path `../` storage **403 RLS**. `%2e%2e%2f` grava pasta literal `..` no prefixo B1 — GET B2 **404**, prefixo real B2 sem `rteq-enc`. U+FF0F / U+29F8 (sem query) dobram para `/` → `proof_ok` **false**; persist **200 []**. Signed B2 em disputa B1 → `proof_ok` **false**, GET **NoSuchKey**. MOVE dest alheio 404; COPY dest alheio **403**. GraphQL extension off. RPC revoke `../` **true** só no path literal; objecto B2 **200** 70b; registry real B2 vazio. JWT INSERT/SELECT revoke **403**. Após DELETE+revoke: auth **404**, signed GET **404**, `proof_ok` **false**. Re-upload: `proof_ok` continua **false**. Reply mid-revoke **400**. Disputa alheia **403**. Janela `pago` / `enviado` / pós-release **403**. Selo portes pós-pago **não** vira ctt. Label traversal / `%252f` / `//` **não persistem**. S2 não lê label B1. Happy prova **201** (2 orders). Race C3: 400 + 403, qty 0→0. Race C4: crédito XOR disputa (Δs 5€, disputa 400, n=0). Stock mint **0**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados**:
- label `%252f` → `200 []` / `stored=null`
- `//` após host → `200 []` não persiste
- revoke INSERT/SELECT **403** + `proof_ok` **false** (1 linha `EQ-B1`)
- disputa `enviado` → 403 RLS (1 linha `EQ-C2b`)

Pass1 marcou 11 HOLD por `HTTP 200` em RPC `true`/`false` sem loot — **confirm** fechou todos (query cortada; persist `[]`; objecto alheio intacto). **Não entram na CONTAGEM.**

Residual clássico 4/35 ≪ 40% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| EQ1 path | `../` 403. `%2e%2e%2f` pasta literal `..`; GET B2 404. `.%2e/%2e.` 403. `%252e…` 400 InvalidKey. `..\` 403. Null byte 400 Cloudflare. JS/HTML/SVG **415**. MOVE 404; COPY 403. |
| EQ2 revoke | JWT INSERT/SELECT **403**. GraphQL off. RPC `../` **true** só literal; objecto B2 70b; registry real vazio. Sticky re-upload `proof_ok` false. Signed GET pós-DELETE **404**. |
| EQ3 proof_ok | Canónico sem query: U+FF0F / U+29F8 **false**. URL B2 false. Query token corta para URL própria. Forjada / revogada / reply **denied**. |
| EQ4 disputa | Alheia 403. `pago` 403. `enviado` 403. Pós-release 403. Happy 201×2. |
| EQ5 label | `%252f` / `//` / `../`+oid forjado → não persiste. Selo portes pós-pago intacto. |
| EQ6 actor | B2 disputa order B1 **403**. S2 GET/LIST label B1 vazio. GET objecto B2 como B1 **404**. |
| EQ7 race | C3 400+403 qty 0→0 Δ 0. C4 crédito XOR disputa; mint 0. |
| EQ8 caixa | 2 pagos 590¢ + disputa 201. Stock races sem mint. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura 1: **5,90 €** (`pi_amount_received=590`) order `aa3fcf49-…`. PI `pi_3UClEHH7FWYUN3jh1PIJ9IQl`. Disputa `4a6daf49-…` **201**.
- Captura 2 (E1): **5,90 €** order `2d8a7baa-…`. PI `pi_3UClFDH7FWYUN3jh1B3ZHB0J`. Disputa `151e39e8-…` **201**.
- C3 race order `c29ed7d6-…`: disputa 400 `dispute_proof_url_denied` + refund **403** shipped; qty **0→0**.
- C4 race order `50697911-…`: release **true**, `wallet_release_processed_at` set, disputa **400**, disputes n=0; Δseller **+5 €**; qty **0→0**.
- D2: pago 590¢ order `d0d4458f-…`; PATCH ctt `200 []`; shipping não virou ctt.

--------------------------------------------------
FINDINGS
--------------------------------------------------

Nenhum P0–P3 aberto. Pass1 marcou 11 HOLD por `HTTP 200` em RPC sem persistência nem loot; `confirm.json` + `confirm_a2_list.json` fecharam todos.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥24 linhas · ≥2 orders pagas + disputa/refund · ≥6 classe_nova.  
`FAIL` = ataque falhou (defesa / feliz OK). Residual anti-atrofia = FAIL denied ou RESIDUAL.

| # | probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|---|----------|------|----------------|----------|-----------|------------------|--------------|
| 1 | EQ-A1.path_dotdot_upload | EQ-A | POST `…/{B1}/../{B2}/` | 400 403 RLS | loot=false | FAIL | NÃO |
| 2 | EQ-A2.pct_2e2e2f | EQ-A | POST `%2e%2e%2f` | up 200 Key c/ `../`; GET B2 404 | list pasta literal `..`; prefixo B2 sem `rteq-enc` | FAIL | NÃO |
| 3 | EQ-A2b.unicode_ff0f | EQ-A | U+FF0F + path B2 | pass1 true c/ `?token=`; confirm noq **false** | persist `200 []`; fold → `/` | FAIL | SIM |
| 4 | EQ-A2c.unicode_29f8 | EQ-A | U+29F8 + path B2 | pass1 true c/ query; confirm noq **false** | persist photos sem alien | FAIL | SIM |
| 5 | EQ-A2d.mixed_dot_pct2e | EQ-A | `.%2e/%2e.` | 400 403 RLS | loot=false | FAIL | SIM |
| 6 | EQ-A2e.double_pct252e | EQ-A | `%252e%252e%252f` | 400 InvalidKey | loot=false | FAIL | SIM |
| 7 | EQ-A3.windows_backslash | EQ-A | `..\` Windows | 400 403 RLS | loot=false | FAIL | SIM |
| 8 | EQ-A3b.null_byte_path | EQ-A | `ok.png%00.js` | 400 Cloudflare | trunc=false | FAIL | SIM |
| 9 | EQ-A4.mime_js_html_svg | EQ-A | JS + HTML + SVG | **415** InvalidMimeType (svg) | js=400 html=400 svg=400 | FAIL | SIM |
| 10 | EQ-A5.signed_url_buyer2 | EQ-A | signed B2 em disputa B1 | rpc **false** | GET B2 as B1 404 | FAIL | NÃO |
| 11 | EQ-A6.storage_move_alien_prefix | EQ-A | MOVE dest prefixo B2 | 400 NoSuchKey | loot=false | FAIL | SIM |
| 12 | EQ-A6b.storage_copy_alien_prefix | EQ-A | COPY dest prefixo B2 | 400 403 RLS | loot=false | FAIL | SIM |
| 13 | EQ-A7.graphql_revoke_collection | EQ-A | POST /graphql/v1 collection | 200 errors extension off | gqlLeak=false | FAIL | SIM |
| 14 | EQ-A8.revoke_rpc_dotdot_alien | EQ-A | RPC revoke `…/{B1}/../{B2}/…` | rpc **true** (path literal) | GET B2 **200** 70b; registry real n=0 | FAIL | SIM |
| 15 | EQ-B1.delete_revoke_jwt_403 | EQ-B | DELETE+revoke+proof_ok + JWT INSERT/SELECT | auth 404; proof_ok false; ins/sel 403 | residual clássico | RESIDUAL | NÃO |
| 16 | EQ-B2.signed_get_after_delete | EQ-B | signed GET pós-DELETE | **404** NoSuchKey | sem CDN 200 | FAIL | SIM |
| 17 | EQ-B3.reupload_same_path_proof_ok | EQ-B | re-POST mesmo path após revoke | re 200; proof_ok **false** | sticky registry | FAIL | SIM |
| 18 | EQ-B4.forged_alien_proof_url | EQ-B | proof URL signed B2 | rpc **false**; persist `200 []` | kept=false | FAIL | SIM |
| 19 | EQ-B4b.query_token_trick | EQ-B | `?token=` + path B2 | canon corta query; persist `200 []` | keptAlien=false | FAIL | SIM |
| 20 | EQ-B5.revoke_mid_dispute_reply | EQ-B | disputa 201 → revoke → reply | proof_ok **false**; reply **400** | replies n=0 | FAIL | SIM |
| 21 | EQ-C1.dispute_order_alheia | EQ-C | B2 POST disputa order B1 | pass1 409 unique; confirm **403 RLS** | sem row | FAIL | NÃO |
| 22 | EQ-C2a.window_pago | EQ-C | disputa em `pago` | 403 RLS | status=pago | FAIL | SIM |
| 23 | EQ-C2b.window_enviado | EQ-C | disputa em `enviado` | 403 RLS | residual janela | FAIL | NÃO |
| 24 | EQ-C2c.window_after_release | EQ-C | disputa após release | 403 RLS | — | FAIL | NÃO |
| 25 | EQ-C3.dispute_refund_race | EQ-C | disputa∥refund-order | 400 + 403 shipped | qty 0→0 Δ 0 | FAIL | NÃO |
| 26 | EQ-C4.dispute_release_race | EQ-C | release∥disputa | rel true; d 400; two=false | Δs +5€; disputes n=0; mint 0 | FAIL | SIM |
| 27 | EQ-C5.happy_dispute_png_signed | EQ-C | POST disputa proof signed 4242 | **201** `4a6daf49-…` | PI 590¢ | FAIL | NÃO |
| 28 | EQ-D1.patch_ship_after_cs | EQ-D | PATCH ctt após checkout | PATCH `200 []`; cs 400 contention | shipping mão intacto | FAIL | NÃO |
| 29 | EQ-D2.patch_ship_after_pago | EQ-D | PATCH ctt após pago | `200 []` | não virou ctt; paid=590 | FAIL | NÃO |
| 30 | EQ-D3.label_traversal_forge_oid | EQ-D | label `../{oid_forjado}` | 200 [] | stored=null | FAIL | SIM |
| 31 | EQ-D3b.label_252f | EQ-D | PATCH label `%252f` | 200 [] | stored=null | FAIL | NÃO |
| 32 | EQ-D3c.slashslash_after_host | EQ-D | PATCH `//extra.png` | 200 [] | stored=null | FAIL | NÃO |
| 33 | EQ-D4.seller2_reads_label_buyer1 | EQ-D | S2 GET disputa + LIST storage B1 | row `200 []`; GET 404; list n=0 | leak=false | FAIL | SIM |
| 34 | EQ-E1.second_paid_happy_dispute | EQ-E | 2.º pago 4242 + disputa feliz | **201** `151e39e8-…` | PI 590¢ | FAIL | NÃO |
| 35 | EQ-E2.stock_delta_races_no_mint | EQ-E | qty C3+C4 | — | 0→0 e 0→0 mint=false | FAIL | SIM |

EQ-A: linhas 1–14 = **14** (≥8).  
EQ-B: 15–20 = **6** (≥5).  
EQ-C: 21–27 = **7** (≥5).  
EQ-D: 28–33 = **6** (≥4).  
EQ-E: 34–35 = **2** (≥2).  
**Total 35 ≥ 24.** Stripe TEST pago + disputa: linhas 27, 34, 25, 26. classe_nova SIM: 3–9, 11–14, 16–20, 22, 26, 30, 33, 35 = **21 ≥ 6**.

Confirm extra: LIST `order_disputes/{B1}/../` devolve pastas UUID **plantadas** no segmento literal `..` (B2 desta ronda + B2 de EB), **não** o prefixo real `order_disputes/{B2}/` (n=0 como B1). GET objectos B2 = 404.

D1: `create-payment-intent` devolveu `order claim contention` (pass1 e confirm); o PATCH JWT mesmo assim **não** gravou `ctt`. Selo pós-pago coberto em D2.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- Pass1 `proof_ok true` em A2b/A2c/B4b usava suffix **depois** de `?token=` — canónico corta query
- U+FF0F e U+29F8 **são** dobrados para `/` no canónico; needle falha; persist deny
- `%2e%2e%2f` **não** sai do prefixo B1: cria segmento literal `..`; GET autenticado 404
- RPC revoke `../` insere row literal; **não** normaliza; objecto B2 intacto
- JWT INSERT/SELECT revoke **403**
- `proof_ok` lê registry sticky após re-upload
- GraphQL `pg_graphql` desligado
- SVG/JS/HTML **415**
- Signed CDN pós-DELETE **404** (fecho do P2 DQ nesta ronda)
- Janela: `pago` / `enviado` / released → 403; só `concluido`/`entregue` + unreleased
- Selo portes: PATCH JWT não grava `ctt` após pago
- C4: 1 efeito (crédito; disputa 400) — sem clawback duplo
- S2 RLS: disputa e storage do B1 vazios

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_eq_20260906T1950/` — `_rteq.dart`, `pass1.dart`, `pass1.json`, `confirm.dart`, `confirm.json`, `confirm_a2_list.dart`, `confirm_a2_list.json`, este relatório.

**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
