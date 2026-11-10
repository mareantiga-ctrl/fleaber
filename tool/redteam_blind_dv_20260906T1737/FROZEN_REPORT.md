# FROZEN_REPORT — RED TEAM CEGO DV

## CONTAGEM

```
P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 2
```

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 1
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DV_STORAGE_POS_DNDS_v1
FROZEN_AT: 2026-09-06T17:47:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DV1, DV2, DV3, DV4, DV5, DV6, DV7]
probes_na_tabela: 27 (≥16)
classes_novas: 13
VEREDICTO: FAIL_P1
```

Prefixo: `RTDV-20260906T1737`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2 / anon. `service_role` só fixture (`setup_paid_order`, plant release, oráculos).

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `211d7842-51dc-446b-83b1-bee42cc3ec2b`

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (race disputa∥refund Δ 0)
13. Refund excede captura — NÃO (590¢ idempotente `re_3UCjA4H7…`)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — SIM (SELECT/INSERT `batata_private_object_revoked` path de B2)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (RPC revoke alheio 42501; tabela directa não)
25. RLS crítico quebrado — SIM (tabela revoke: GRANT INSERT/SELECT authenticated, sem RLS)
26. Edge confia total do cliente — NÃO (C2 selo pago intacto; C3 amount 429)
27. Regressão funcional (happy path partido) — NÃO (prova signed 201 `1296b2ca-…` e `eb442db3-…`)
28. Saturação atingida — NÃO (P1+P2 abertos)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Proof URL canónica; sem traversal; sem loot alheio.  
Após DELETE: auth 404; `batata_revoke_private_object` → proof_ok false; signed CDN até exp = residual.  
Disputa: actor + janela. Shipping: imutável após `cs_`/pago.

**Resposta:** path `../` storage **403 RLS**. COPY prefixo B2 **403**. RPC revoke alheio **42501**. U+FF0F sem `?query` → canónico vira `/` → **proof_ok false**; persist `200 []`. Label `%252f` / `//` / `@evil` / `https:/` **não persistem**. Disputa alheia / enviado / pós-release → **403**. JWT `completed_at` **200 []**. Selo portes pós-pago **não vira ctt**. Happy prova **201**. Refund **590¢** stock **0→1** idempotente.

**Buracos DNDS:** (1) JWT autenticado **INSERT+SELECT** na tabela `batata_private_object_revoked` (bypass do RPC `revoke_forbidden`). (2) `proof_ok` **true** após DELETE+revoke; disputa **201** com URL de objecto já apagado.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados**:
- label `%252f` → `200 []` / `stored=null`
- `//` após host → `200 []` não persiste
- disputa `enviado` / pós-release → 403 RLS (janela clássica)
- signed CDN 200 pós-DELETE no pass1 (`70b`) — confirm ~3 min depois **404**; persist-pass CDN **404** imediato. Residual plataforma (máx 1 linha) — **não entra na CONTAGEM**.

Pass1 HOLDs A2/A3/A6/D2 = oráculo HTTP `200 true/false` ou refund 200 sem `doubleStock` — **não** entram (confirm: A2 noq `false`; A3 GET `NoSuchKey`; A6 upload **415**; D2 qty **0→1**).

Residual clássico 4/27 ≪ 40% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| DV1 path | `../` 403. COPY 403. U+FF0F noq **false**. SVG mime **415**. |
| DV2 revoke | RPC alheio 42501. **P1** INSERT/SELECT tabela. **P2** proof_ok ignora registry + disputa 201. Auth GET 404 após DELETE. CDN residual pass1 200 → confirm 404. |
| DV3 actor | B2 disputa order B1 **403**. PATCH status hostil `200 []` (disputa `aberta`, order `concluido`). |
| DV4 janela | `enviado` 403. Pós-release 403. JWT `completed_at` −60d não grava. |
| DV5 shipping | pós-pago PATCH ctt `200 []` (shipping ficou `null`, não `ctt`). C1 Session **429** — selo mão intacto sem `cs_`. |
| DV6 label | `%252f` / `//` / `@evil` / `https:/` / U+FF0F → não persiste. |
| DV7 stock | race qty 0→0 Δ 0. Refund pago 590¢ idempotente; qty **0→1**; `cancelado`. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia principal: **5,90 €** (`amount_paid_cents=590`) order `a2a4618c-…`. PI `pi_3UCj9JH7FWYUN3jh1JMHTq74`.
- Disputa feliz: `1296b2ca-…` **201** com PNG signed.
- Persist prova revogada: order `8a8ff4ca-…` disputa `eb442db3-…` **201** URL `gone.png` (objecto 404).
- Refund D2: order `f15201bd-…` PI `pi_3UCjA4H7…` → `re_3UCjA4H7…10AoIzbm` **590¢** idempotente; qty **0→1**.
- Race B3: disputa 400 `dispute_proof_url_denied` + refund **403** `order_refund_blocked_shipped`; qty 0→0; Δ 0.
- C3 bag: **429** rate-limit; selos BD CTT+mão intactos; amount **não** observado nesta ronda.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### P1-1 · RTDV-A7-revoke-table-direct-insert · P1 · DV2

**Actor:** buyer JWT (B1).

**Passos:**
1. `POST /rest/v1/batata_private_object_revoked` body `object_path=order_disputes/{B2}/{oid}/hostile-revoke.png` → **201**.
2. `GET` da mesma tabela com JWT B1 → **200** n=3, incluindo path de B2 e path `dnds-…` de outro teste.
3. Segundo INSERT `order_proofs/{B2}/hostile-proof.png` → **201**.
4. PATCH/DELETE da tabela → **403** `permission denied` (só INSERT+SELECT granted).
5. Anon SELECT → **401**.
6. RPC `batata_revoke_private_object` no path B2 → **42501** `revoke_forbidden` (o RPC está correcto; a tabela não).

**Esperado:** INSERT/SELECT só via RPC e só no prefixo do `auth.uid()`; RLS deny no REST.

**Obtido:** authenticated tem GRANT INSERT+SELECT; **sem RLS**. Qualquer sessão autenticada escreve path alheio e lê o registry inteiro.

Loot: paths de provas apagadas de outros buyers (UUIDs). Sem bytes de ficheiro. Sem dinheiro.

**Severidade P1:** bypass do actor-check do revoke (controlo DNDS). Não P0: sem dinheiro. Não só P2: caminho REST explorável agora (INSERT+SELECT), não residual de CDN.

**Prova:** `pass1.json` probe `DV-A7`; `confirm.json` `a7_select_b1` / `a7_insert_proofs_b2`.

--------------------------------------------------

### P2-1 · RTDV-A4-proof-ok-ignores-revoke · P2 · DV2

**Actor:** buyer JWT (objecto próprio).

**Passos:**
1. Upload PNG `order_disputes/{B1}/{oid}/gone.png` → 200.
2. DELETE → 200 `Successfully deleted`. Auth GET → **404** `NoSuchKey`.
3. RPC `batata_revoke_private_object` → **true**. Row na tabela revoke presente.
4. RPC `batata_dispute_proof_url_ok` na URL canónica (sem `?token=`) → **true**.
5. POST `order_disputes` com essa URL → **201** `eb442db3-…`; `proof_photos` contém `…/gone.png`.
6. CDN signed GET nesta confirmação → **404** (pass1 A5 tinha sido 200 70b no outro objecto).

**Esperado:** após revoke, `proof_ok` false; POST disputa 400 `dispute_proof_url_denied`.

**Obtido:** o helper é `immutable` e **não consulta** `batata_private_object_revoked`. A disputa aceita prova cujo objecto já não existe.

Loot: **não** (só o próprio path). Sem leitura alheia.

**Severidade P2:** hygiene do requisito de prova + revoke registry morto no oráculo. Não P1: não lê objectos de outro buyer; não muda dinheiro.

**Prova:** `confirm_a4_persist.json` (`proof_ok=true`, `dispute=201`, `auth=404`, `rev=true`).

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥16 linhas · ≥1 order paga + disputa/refund · ≥4 classe_nova.  
`FAIL` = ataque falhou (defesa / feliz OK). `HOLD` = finding na CONTAGEM. Residual anti-atrofia = FAIL denied ou RESIDUAL.

| # | probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|---|----------|------|----------------|----------|-----------|------------------|--------------|
| 1 | DV-A1.path_dotdot_upload | DV-A | POST `…/{B1}/../{B2}/` | 400 403 RLS | loot=false | FAIL | NÃO |
| 2 | DV-A2.unicode_ff0f_fullwidth | DV-A | U+FF0F + path B2 (pass1 c/ query) | rpc true→**confirm noq false** | persist `200 []` | FAIL | SIM |
| 3 | DV-A3.signed_url_buyer2 | DV-A | signed B2 em disputa B1 | rpc **false** | GET B2 as B1 404 NoSuchKey | FAIL | NÃO |
| 4 | DV-A4.delete_revoke_proof_ok | DV-A | DELETE + revoke RPC + proof_ok | auth 404; rev true; **proof_ok true** | row revoke presente | **HOLD** | SIM |
| 5 | DV-A5.signed_get_after_delete | DV-A | signed GET pós-DELETE | pass1 **200** 70b; confirm **404** | residual CDN | RESIDUAL | SIM |
| 6 | DV-A6.mime_svg_polyglot | DV-A | upload poly.svg CT=svg+xml | **415** InvalidMimeType | sem objecto | FAIL | SIM |
| 7 | DV-A7.revoke_table_direct_insert | DV-A | POST REST path B2 | **201** | SELECT n=3 leak B2 | **HOLD** | SIM |
| 8 | DV-A8.revoke_rpc_alien_path | DV-A | RPC revoke path B2 | **403** 42501 | — | FAIL | SIM |
| 9 | DV-A9.storage_copy_alien_prefix | DV-A | COPY dest prefixo B2 | **400** 403 RLS | GET dest 404 | FAIL | SIM |
| 10 | DV-D1.pago_proof_feliz | DV-D | POST disputa proof signed | **201** `1296b2ca-…` | photos contém oid | FAIL | NÃO |
| 11 | DV-A2b.label_unicode_ff0f | DV-A | PATCH label U+FF0F | 200 [] | stored=null | FAIL | SIM |
| 12 | DV-CTRL.label_252f | DV-A | PATCH label `%252f` | 200 [] | stored=null | FAIL | NÃO |
| 13 | DV-CTRL.slashslash_after_host | DV-A | PATCH `//extra.png` | 200 [] | stored=null | FAIL | NÃO |
| 14 | DV-A4b.persist_revoked_proof | DV-A | PATCH photos URL revogada (mesma order) | 200 [] | photos intactas | FAIL | SIM |
| 15 | DV-B1.dispute_order_alheia | DV-B | B2 POST disputa order B1 | 403 RLS | sem row | FAIL | NÃO |
| 16 | DV-B2.window_enviado | DV-B | disputa em `enviado` | 403 RLS | residual janela | FAIL | NÃO |
| 17 | DV-B2b.window_after_release | DV-B | disputa após release | 403 RLS | residual janela | FAIL | NÃO |
| 18 | DV-B2c.jwt_backdate_completed_at | DV-B | JWT PATCH completed_at −60d | 200 [] | completed_at=now | FAIL | SIM |
| 19 | DV-B3.dispute_refund_race | DV-B | disputa∥refund-order | 400 + 403 shipped | qty 0→0 Δ 0 | FAIL | NÃO |
| 20 | DV-B4.patch_hostile_status | DV-B | disputa=resolvida + order=cancelado | 200 [] | aberta / concluido | FAIL | NÃO |
| 21 | DV-C1.patch_ship_after_cs | DV-C | PATCH ctt após checkout | Session **429**; PATCH 200 [] | shipping=mão | FAIL | NÃO |
| 22 | DV-C2.patch_ship_after_pago | DV-C | PATCH ctt após pago | 200 [] | shipping não virou ctt | FAIL | NÃO |
| 23 | DV-C3.bag_mixed_shipping | DV-C | bag CTT+mão body=mão | **429** | selos CTT+mão intactos | FAIL | SIM |
| 24 | DV-C4.label_userinfo_at | DV-C | label `@evil.example` | 200 [] | stored=null | FAIL | SIM |
| 25 | DV-C4b.label_https_single_slash | DV-C | label `https:/` | 200 [] | stored=null | FAIL | SIM |
| 26 | DV-D2.refund_stock_idempotent | DV-D | refund ×2 | 200 idempotente 590¢ | qty **0→1** cancelado | FAIL | NÃO |
| 27 | DV-D2b.refund_happened | DV-D | oráculo stock | 200 | qty 0→1 | FAIL | NÃO |

DV-A: linhas 1–9 + 11–14 = **13** (≥6).  
DV-B: 15–20 = **6** (≥4).  
DV-C: 21–25 = **5** (≥4).  
DV-D: 10, 26–27 = **3** (≥2).  
**Total 27 ≥ 16.** Stripe TEST pago + disputa: linhas 10, 4/confirm `eb442db3-…`, 19, 26. classe_nova SIM: 2, 4, 5, 6, 7, 8, 9, 11, 14, 18, 23, 24, 25 = **13 ≥ 4**.

Confirm extra (fora da tabela, prova P2-1): POST disputa URL revogada em order nova → **201** `eb442db3-…`.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- Canónico corta `?query` — suffix hostil depois do token signed **não** é path (falso `true` no pass1 A2)
- U+FF0F **é** dobrado para `/` no canónico; needle falha; persist deny
- SVG **415** no storage; helper `true` em URL fantasma **não** persiste sozinho neste teste
- RPC revoke alheio **42501** (actor-check no RPC OK)
- Storage COPY prefixo alheio **403**
- Selo portes: PATCH JWT não grava `ctt` após pago
- C3 amount **429** (rate-limit checkout) — selos BD intactos; não subcotação observada
- Janela: só `concluido`/`entregue` + unreleased
- Refund 590¢ + stock +1 uma vez (`already_refunded` no 2.º call)

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_dv_20260906T1737/` — `_rtdv.dart`, `pass1.dart`, `pass1.json`, `confirm.dart`, `confirm.json`, `confirm_a4_persist.dart`, `confirm_a4_persist.json`, este relatório.

**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=1 P2=1 P3=0 TOTAL=2
