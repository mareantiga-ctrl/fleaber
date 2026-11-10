# FROZEN_REPORT — RED TEAM CEGO EB

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
AUDITOR: REDTEAM_BLIND_EB_STORAGE_POS_DTDY_v1
FROZEN_AT: 2026-09-06T18:32:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EB1, EB2, EB3, EB4, EB5, EB6, EB7]
probes_na_tabela: 31 (≥16)
classes_novas: 17
VEREDICTO: PASS_CEGO_SATURADO
```

Prefixo: `RTEB-20260906T1821`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`, plant release, oráculos).

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `3ca2cf64-93d8-4b4b-be8f-9035b22e8a1a` · S2 `feb33d48-2a34-4472-b6ad-4b50ec3d2c1e`

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
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (race disputa∥refund Δ 0, qty 0→0)
13. Refund excede captura — NÃO (refund 403 `order_refund_blocked_shipped` em concluido)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (S2 GET disputa/label B1 `200 []`; GET objecto 404; LIST prefixo B1 `[]`; JWT SELECT revoke 403)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (revoke `../` devolve true mas **não** toca o objecto B2)
25. RLS crítico quebrado — NÃO (tabela revoke: GRANT JWT 403 `42501`; disputa alheia 403)
26. Edge confia total do cliente — NÃO (selo portes pós-pago intacto)
27. Regressão funcional (happy path partido) — NÃO (prova signed 201 `33f2a951-…`)
28. Saturação atingida — SIM (31 probes, 17 classe_nova, P0–P2=0, pago+disputa no fio)

--------------------------------------------------
MISSÃO
--------------------------------------------------

JWT **não** INSERT/SELECT directo no registry revoke (DV P1).  
Após revoke: proof_ok false; auth GET 404.  
Disputa actor+janela; shipping imutável pós-`cs_`/pago.

**Resposta:** INSERT/SELECT JWT `batata_private_object_revoked` → **403 42501**. Após DELETE+revoke: auth **404**, `proof_ok` **false**. Re-upload no mesmo path: storage 200 mas `proof_ok` continua **false** (registry sticky). Path `../` storage **403 RLS**. `%2e%2e%2f` grava pasta literal `..` no prefixo B1 — GET B2 **404**, prefixo B2 intacto. U+2044/U+2215 dobram para `/` → `proof_ok` **false**; persist **200 []**. URL signed B2 em disputa B1 → `proof_ok` **false**, GET **NoSuchKey**. Disputa alheia **403 RLS**. Janela `enviado` / pós-release **403**. Selo portes pós-pago **não** vira ctt. Label traversal / oid forjado / `%252f` / `//` **não persistem**. S2 não lê label B1. Happy prova **201**. Race disputa∥refund: 400 + 403, Δ 0.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados**:
- label `%252f` → `200 []` / `stored=null`
- `//` após host → `200 []` não persiste
- revoke INSERT deny **403** + `proof_ok` **false** (reteste DTDY, 1 linha `EB-A4A5`)
- disputa `enviado` / pós-release → 403 RLS (janela clássica)
- signed CDN pós-DELETE → **404** `NoSuchKey` (sem residual 200 nesta ronda)

Pass1 HOLDs A2/A2c/A3/A5b/A7/A9/B4/B4b/D2/D3 = oráculo HTTP `200 true/false` sem loot — **confirm** fechou todos (ver NÃO-FINDINGS). **Não entram na CONTAGEM.**

Residual clássico 7/31 ≪ 40% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| EB1 path | `../` 403. `%2e%2e%2f` pasta literal `..` no prefixo próprio; GET B2 404. Overlong `%c0%af` 400 URL. `..\` 403. Null byte 400 Cloudflare. JS/HTML **415**. MOVE dest alheio 404. |
| EB2 revoke | JWT INSERT/SELECT **403**. GraphQL extension off. RPC `../` **true** só no path literal; objecto B2 **200** 70b; registry real B2 vazio. Sticky: re-upload `proof_ok` false. |
| EB3 proof_ok | Canónico sem query: U+2044 false. `%2f` encoded false. URL B2 false. Pós-revoke false. Mid-disputa false. |
| EB4 disputa | Alheia 403. `enviado` 403. Pós-release 403. |
| EB5 label | `%252f` / `//` / `../` / oid forjado → não persiste. Selo portes pós-`cs_`/pago intacto. |
| EB6 actor | B2 disputa order B1 **403**. S2 GET/LIST label B1 vazio. GET objecto B2 como B1 **404**. |
| EB7 caixa | Happy 201 PI 590¢. Race qty 0→0 Δ 0. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia principal: **5,90 €** (`pi_amount_received=590`) order `30823788-…`. PI `pi_3UCjqyH7FWYUN3jh0xtQ1E4G`.
- Disputa feliz: `33f2a951-…` **201** com PNG signed.
- Disputa D2 mid-revoke: `6265ab2a-…` **201**; após DELETE+revoke `proof_ok=false`; PATCH photos `200 []`.
- Race B3: disputa 400 `dispute_proof_url_denied` + refund **403** `order_refund_blocked_shipped`; qty 0→0; Δ 0.
- C1/C2: pago 590¢ order `fad0005e-…`; PATCH ctt `200 []`; shipping não virou ctt.

--------------------------------------------------
FINDINGS
--------------------------------------------------

Nenhum P0–P3 aberto. Pass1 marcou 10 HOLD por `HTTP 200` em RPC `false`/`true` sem persistência nem loot; `confirm.json` + `confirm_a2_list.json` fecharam todos.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥16 linhas · ≥1 order paga + disputa/refund · ≥4 classe_nova.  
`FAIL` = ataque falhou (defesa / feliz OK). Residual anti-atrofia = FAIL denied ou RESIDUAL.

| # | probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|---|----------|------|----------------|----------|-----------|------------------|--------------|
| 1 | EB-A1.path_dotdot_upload | EB-A | POST `…/{B1}/../{B2}/` | 400 403 RLS | loot=false | FAIL | NÃO |
| 2 | EB-A2.pct_2e2e2f | EB-A | POST `%2e%2e%2f` | up 200 Key c/ `../`; GET B2 404 | list pasta literal `..`; prefixo B2 sem `rteb-enc` | FAIL | SIM |
| 3 | EB-A2b.overlong_c0af | EB-A | `%c0%af` no path | 400 FST_ERR_BAD_URL | loot=false | FAIL | SIM |
| 4 | EB-A2c.unicode_2044 | EB-A | U+2044 + path B2 | pass1 true c/ `?token=`; confirm noq **false** | persist `200 []`; fold → `/` | FAIL | SIM |
| 5 | EB-A3.signed_url_buyer2 | EB-A | signed B2 em disputa B1 | rpc **false** | GET B2 as B1 404 | FAIL | NÃO |
| 6 | EB-A4A5.dtdy_revoke_retest | EB-A | DELETE+revoke+proof_ok + JWT INSERT/SELECT | auth 404; proof_ok false; ins/sel 403 | residual DTDY | RESIDUAL | NÃO |
| 7 | EB-A4.delete_revoke_proof_ok | EB-A | DELETE + revoke RPC + proof_ok | auth 404; rev true; proof_ok **false** | — | RESIDUAL | NÃO |
| 8 | EB-A5.jwt_insert_select_revoke | EB-A | POST+GET tabela revoke path B2 | **403** 42501 | n=0 | FAIL | NÃO |
| 9 | EB-A5b.graphql_revoke_collection | EB-A | POST /graphql/v1 collection | 200 errors extension off | gqlLeak=false | FAIL | SIM |
| 10 | EB-A6.mime_js_html | EB-A | JS + HTML mime | **415** InvalidMimeType | sem objecto | FAIL | SIM |
| 11 | EB-A6b.null_byte_path | EB-A | `ok.png%00.js` | 400 Cloudflare | trunc=false | FAIL | SIM |
| 12 | EB-A6c.windows_backslash | EB-A | `..\` Windows | 400 403 RLS | loot=false | FAIL | SIM |
| 13 | EB-A7.pct2f_bypass_revoke_registry | EB-A | revoke `/` ; proof_ok `%2f` | rpc **false** | — | FAIL | SIM |
| 14 | EB-A8.storage_move_alien_prefix | EB-A | MOVE dest prefixo B2 | 400 NoSuchKey | loot=false | FAIL | SIM |
| 15 | EB-A9.revoke_rpc_dotdot_alien | EB-A | RPC revoke `…/{B1}/../{B2}/…` | rpc **true** (path literal) | GET B2 **200** 70b; registry real B2 `[]` | FAIL | SIM |
| 16 | EB-D1.pago_proof_feliz | EB-D | POST disputa proof signed 4242 | **201** `33f2a951-…` | PI 590¢ | FAIL | NÃO |
| 17 | EB-CTRL.label_252f | EB-C | PATCH label `%252f` | 200 [] | stored=null | FAIL | NÃO |
| 18 | EB-CTRL.slashslash_after_host | EB-C | PATCH `//extra.png` | 200 [] | stored=null | FAIL | NÃO |
| 19 | EB-CTRL.signed_cdn_after_delete | EB-A | signed GET pós-DELETE | **404** NoSuchKey | sem CDN 200 | FAIL | NÃO |
| 20 | EB-B1.dispute_order_alheia | EB-B | B2 POST disputa order B1 | pass1 409 unique; confirm **403 RLS** | sem row | FAIL | NÃO |
| 21 | EB-B2.window_enviado | EB-B | disputa em `enviado` | 403 RLS | residual janela | FAIL | NÃO |
| 22 | EB-B2b.window_after_release | EB-B | disputa após release | 403 RLS | residual janela | FAIL | NÃO |
| 23 | EB-B3.dispute_refund_race | EB-B | disputa∥refund-order | 400 + 403 shipped | qty 0→0 Δ 0 | FAIL | NÃO |
| 24 | EB-B4.forged_alien_path | EB-B | proof URL signed B2 | rpc **false**; persist `200 []` | kept=false | FAIL | SIM |
| 25 | EB-B4b.forged_revoked_old_url | EB-B | URL signed objecto revogado | rpc **false**; patch `200 []` | kept=false | FAIL | SIM |
| 26 | EB-C1.patch_ship_after_cs_pago | EB-C | PATCH ctt após Session e pago | 200 [] | shipping não virou ctt; paid=590 | FAIL | NÃO |
| 27 | EB-C2.label_traversal_forge_oid | EB-C | label `../{oid_forjado}` | 200 [] | stored=null | FAIL | SIM |
| 28 | EB-C2b.label_forge_order_id | EB-C | label oid forjado prefixo B1 | 200 [] | stored=null | FAIL | SIM |
| 29 | EB-C3.seller2_reads_label_buyer1 | EB-C | S2 GET disputa + LIST storage B1 | row `200 []`; GET 404; list `[]` | leak=false | FAIL | SIM |
| 30 | EB-D2.revoke_mid_dispute_proof_ok | EB-D | disputa 201 → revoke prova | proof_ok **false**; patch `200 []` | photos históricas mid.png (snapshot) | FAIL | SIM |
| 31 | EB-D3.reupload_same_path_after_revoke | EB-D | re-POST mesmo path após revoke | re 200; proof_ok **false**; patch `200 []` | sticky registry | FAIL | SIM |

EB-A: linhas 1–15 + 19 = **16** (≥6).  
EB-B: 20–25 = **6** (≥4).  
EB-C: 17–18 + 26–29 = **6** (≥3).  
EB-D: 16, 30–31 = **3** (≥3).  
**Total 31 ≥ 16.** Stripe TEST pago + disputa: linhas 16, 23, 30. classe_nova SIM: 2, 3, 4, 9, 10, 11, 12, 13, 14, 15, 24, 25, 27, 28, 29, 30, 31 = **17 ≥ 4**.

Confirm extra (fora da tabela): U+2044/U+2215 **no meio** do buyer-id → canónico dobra `/` → `proof_ok false`. LIST `order_disputes/{B1}/../` devolve só a pasta B2 **plantada** (n=1), não o prefixo real de B2.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- Pass1 `proof_ok true` em A2c usava suffix **depois** de `?token=` — canónico corta query (mesmo falso positivo DV A2)
- U+2044 **é** dobrado para `/` no canónico; needle falha; persist deny
- `%2e%2e%2f` **não** sai do prefixo B1: cria segmento literal `..`; GET autenticado 404; B2 list sem `rteb-enc`
- RPC revoke `../` insere row literal; **não** normaliza; objecto B2 intacto; `proof_ok` B2 ainda true no path real
- JWT INSERT/SELECT revoke **403** (fecho DTDY DV P1)
- `proof_ok` lê registry (fecho DTDY DV P2); sticky após re-upload
- GraphQL `pg_graphql` desligado
- SVG/JS/HTML **415**
- Janela: só `concluido`/`entregue` + unreleased
- Selo portes: PATCH JWT não grava `ctt` após pago / Session
- S2 RLS: disputa e storage do B1 vazios

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_eb_20260906T1821/` — `_rteb.dart`, `pass1.dart`, `pass1.json`, `confirm.dart`, `confirm.json`, `confirm_a2_list.dart`, `confirm_a2_list.json`, este relatório.

**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
