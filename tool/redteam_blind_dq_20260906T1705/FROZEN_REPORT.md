# FROZEN_REPORT — RED TEAM CEGO DQ

## CONTAGEM

```
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1
```

1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado? SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_DQ_SHIP_DISPUTE_POS_DHDM_v1
FROZEN_AT: 2026-09-06T17:12:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DQ1, DQ2, DQ3, DQ4, DQ5, DQ6, DQ7]
probes_na_tabela: 25 (≥14)
classes_novas: 9
VEREDICTO: FAIL_P2
```

Prefixo: `RTDQ-20260906T1705`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2 / anon. `service_role` só fixture (`setup_paid_order`, plant `wallet_release_processed_at`, oráculos).

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `8c3bf978-e7a4-4f47-90b2-d51676a3c48e`

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora do poço; selo portes intacto)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (race disputa∥refund Δ 0)
13. Refund excede captura — NÃO (590¢ idempotente `re_3UCicUH7…`)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (GET B2 `NoSuchKey`; proof_ok B2 `false`; persist hostil `200 []`)
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO (saco portes = max selo 1548¢)
27. Regressão funcional (happy path partido) — NÃO (prova signed 201; label signed persistida na confirmação; enviado seller JWT 200)
28. Saturação atingida — NÃO (P2 aberto em signed URL pós-DELETE)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Proof URL: path canónico, sem traversal, sem concat, sem `//` hostil após host.  
Disputa só na janela e pelo buyer certo.  
Shipping seal: buyer não muda portes após Session/pago.

**Resposta:** path `../` storage **403 RLS**. Helper `proof_ok` em URL B2 / `%2e%2e%2f` / U+2AFB / `%25c0%25af` / `%00` → **false** (confirm sem `?token=`). Persist JWT hostil **não grava**. Label `%252f` e `//` **não persistem**. Disputa alheia / enviado / pós-release → **403**. JWT `completed_at` **200 []** inalterado. Selo portes pós-`cs_` e pós-pago **mão intacto**. Saco CTT+mão body=mão → **1548¢** (max CTT). Happy prova **201** `aa6e8cf9-…`. Seller `enviado` sem prova **após pago** = regra documentada (200).

Residual: signed URL própria continua a servir bytes **depois de DELETE** do objecto (GET autenticado 404). Sem loot alheio.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados** como finding:
- label `%252f` → `200 []` / `stored=null` (deny residual, fecho DG/DBDG)
- `//` após host → `200 []` não persiste
- disputa pós-release → 403 RLS (janela residual)

Pass1 marcou vários RPC `200 true` por concatenar o ataque **depois de `?token=`** — o canónico corta a query e fica a URL própria. Confirm sem query → `false`. Não contar.

Novos (contam para quota): U+2AFB, `%25c0%25af`, `%00` omit, signed reuse pós-DELETE, JS mime 415, janela `enviado`, JWT backdate `completed_at`, saco portes misturados.

Residual clássico ≪ 40% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| DQ1 path | `../` 403. `%2e%2e%2f` / U+2AFB / `%25c0%25af` / `%00` → helper **false**; persist `200 []`. |
| DQ2 actor | B2 disputa order B1 **403**. PATCH status hostil `200 []` (disputa `aberta`, order `concluido`). |
| DQ3 janela | Pós-release 403. `enviado` 403. JWT `completed_at` −60d não grava; RLS sem janela calendário (só concluido+unreleased). |
| DQ4 race | disputa∥refund: prova hostil 400 + refund **403** `order_refund_blocked_shipped`; qty 0→0; Δ 0. |
| DQ5 shipping seal | pós-`cs_` mão intacto; pós-pago mão intacto; saco misto **1548¢**. |
| DQ6 storage | upload próprio 200; B2 GET `NoSuchKey`; JS 415; **P2** signed GET 200 após DELETE. |
| DQ7 stock pós-refund | refund pago 590¢ idempotente; qty **0→1**; status `cancelado`. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia principal: **5,90 €** (`amount_paid_cents=590`) order `13937338-…`. PI `pi_3UCibiH7FWYUN3jh1p3SmHpD`.
- Saco misto CTT+mão: Session `cs_test_a1X2E1N1…` **amount_total=1548¢** (2×590 + 350 CTT + protecção). Selos BD intactos.
- Refund D3: order `daabd3ac-…` PI `pi_3UCicUH7…` → `re_3UCicUH7…0XgBBzAw` **590¢** idempotente; qty **0→1**.
- Race B3: Δbuyer **0** · Δseller **0**; refund bloqueado em `concluido`.
- Disputa feliz: `aa6e8cf9-…` **201** com PNG signed.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTDQ-A4-signed-reuse-after-delete · P2 · DQ6

**Actor:** buyer JWT (objecto próprio).

**Passos:**
1. Upload PNG `order_disputes/{B1}/{oid}/a4b.png` → 200.
2. `object/sign` expiresIn=3600 → URL signed.
3. GET signed → **200** 70 bytes (PNG).
4. DELETE object (Content-Type octet-stream) → **200** `Successfully deleted`.
5. GET autenticado do mesmo path → **404** `NoSuchKey`.
6. GET da **mesma** signed URL antiga → **200** 70 bytes (PNG).

**Esperado:** após DELETE, signed GET 404/400 (objecto revogado).

**Obtido:** o token signed continua a servir o ficheiro até `exp` (~1 h). O GET autenticado já não vê o objecto.

Loot: **não** (só bytes do próprio upload; B2 `NoSuchKey`). Sem caminho para prefixo alheio.

**Severidade P2:** higiene de revoke vs token signed. Não P1: não lê objectos de outro buyer. Não P0: sem dinheiro.

**Prova:** `confirm_a4_label.json` (`reuse: true`). Pass1 A4 foi falso (DELETE 400 por `application/json` vazio) — a confirmação é a prova.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥14 linhas · ≥1 order paga + disputa/refund · ≥3 classe_nova.  
`FAIL` = ataque falhou (defesa / feliz OK). `HOLD` = finding. Residual anti-atrofia na tabela como FAIL denied.

| # | probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD\|FAIL\|SKIP | classe_nova? |
|---|----------|------|----------------|----------|-----------|------------------|--------------|
| 1 | DQ-A1.path_dotdot_upload | DQ-A | POST `…/{B1}/../{B2}/` | 400 403 RLS | getAlien 404 | FAIL | NÃO |
| 2 | DQ-A1b.encoded_dots_url | DQ-A | `%2e%2e%2f` + path B2 (sem query) | rpc **false** | persist `200 []` photos intactas | FAIL | NÃO |
| 3 | DQ-A2.proof_url_other_buyer | DQ-A | signed B2 em disputa B1 | rpc **false** | GET B2 as B1 404 NoSuchKey | FAIL | NÃO |
| 4 | DQ-A3.ct_mismatch_js | DQ-A | upload `evil.js` CT=javascript | **415** InvalidMimeType | sem objecto | FAIL | SIM |
| 5 | DQ-A4.signed_reuse_after_delete | DQ-A | sign → DELETE → GET signed antiga | GET signed **200** 70b; auth 404 | objecto apagado | **HOLD** | SIM |
| 6 | DQ-A5.unicode_triple_solidus_2afb | DQ-A | U+2AFB ⫻ + path B2 | rpc **false** | canon mantém ⫻; persist `200 []` | FAIL | SIM |
| 7 | DQ-A5b.overlong_double_pct25c0af | DQ-A | `%25c0%25af` + path B2 | rpc **false** | `%25c0%25af` literal; persist `200 []` | FAIL | SIM |
| 8 | DQ-A5c.null_omit_pct00 | DQ-A | `%00` (sem chr(0)) + path B2 | rpc **false** | sem 54000; `%00` strip; extra `/` falha needle | FAIL | SIM |
| 9 | DQ-A5d.label_unicode_2afb | DQ-A | PATCH label U+2AFB | 200 [] | stored label não é ⫻ | FAIL | SIM |
| 10 | DQ-CTRL.label_252f | DQ-A | PATCH label `%252f` + B2 | 200 [] | stored=null | FAIL | NÃO |
| 11 | DQ-CTRL.slashslash_after_host | DQ-A | PATCH label `//extra.png` | 200 [] | stored=null | FAIL | NÃO |
| 12 | DQ-B1.dispute_order_alheia | DQ-B | B2 POST disputa order B1 | 403 RLS | sem row | FAIL | NÃO |
| 13 | DQ-B2.window_after_release | DQ-B | disputa após release (svc plant) | 403 RLS | residual janela | FAIL | NÃO |
| 14 | DQ-B2b.window_enviado_not_concluido | DQ-B | disputa em `enviado` | 403 RLS | status=enviado | FAIL | SIM |
| 15 | DQ-B2c.jwt_backdate_completed_at | DQ-B | JWT PATCH completed_at −60d | 200 [] | completed_at=now; disputa 201 (unreleased) | FAIL | SIM |
| 16 | DQ-B3.dispute_refund_race | DQ-B | disputa∥refund-order | 400 + 403 shipped | qty 0→0 Δ 0 | FAIL | NÃO |
| 17 | DQ-B3b.race_oracles | DQ-B | stock/wallet após race | — | Δb=0 Δs=0 refund_id vazio | FAIL | NÃO |
| 18 | DQ-B4.patch_hostile_status | DQ-B | disputa=resolvida + order=cancelado | 200 [] | status disputa=aberta order=concluido | FAIL | NÃO |
| 19 | DQ-C1.patch_ship_after_cs | DQ-C | PATCH ctt após `cs_test_` | 200 [] | shipping=`entrega em mão` | FAIL | NÃO |
| 20 | DQ-C2.patch_ship_after_pago | DQ-C | PATCH ctt após pago | 200 [] | shipping inalterado | FAIL | NÃO |
| 21 | DQ-C3.bag_mixed_shipping | DQ-C | bag CTT+mão body=mão | 200 Session | **amt=1548¢** selos intactos | FAIL | SIM |
| 22 | DQ-D1.pago_label_feliz | DQ-D | POST disputa proof signed | **201** `aa6e8cf9-…` | photos contém oid | FAIL | NÃO |
| 23 | DQ-D1b.label_canonical | DQ-D | PATCH return_label_url signed | 200 (confirm) | URL própria persistida | FAIL | NÃO |
| 24 | DQ-D2.seller_enviado_sem_prova | DQ-D | seller JWT enviado sem proof | **200** | status=`enviado` proof=null (regra: pago basta) | FAIL | NÃO |
| 25 | DQ-D3.refund_stock_oracle | DQ-D | refund-order em pago | 200 590¢ idempotente | qty **0→1** cancelado | FAIL | NÃO |

DQ-A: linhas 1–11 = **11** (≥5).  
DQ-B: 12–18 = **7** (≥4).  
DQ-C: 19–21 = **3** (≥3).  
DQ-D: 22–25 = **4** (≥2).  
**Total 25 ≥ 14.** Stripe TEST pago + disputa: linhas 22, 16, 25. classe_nova SIM: 4, 5, 6, 7, 8, 9, 14, 15, 21 = **9 ≥ 3**.

Pass1 HOLDs A1b/A2/A3/A5*/C3/D1b/D2 = oráculo HTTP 200 ou JWT em falta — **não** entram na CONTAGEM (confirm `confirm.json` / `confirm_a4_label.json`).

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- Canónico corta `?query` — suffix hostil depois do token signed **não** é path (falso `true` no pass1)
- U+2AFB **não** é dobrado para `/` (fica no filename); needle `[^/]+$` falha por `/` extra
- `%25c0%25af` **não** decodifica no loop (só `%c0%af`)
- `%00` percent strip; sem 54000; concat ainda tem `/` → deny
- JS mime **415** (storage)
- Selo portes pós-Session e pós-pago
- Saco misto cobra CTT (1548¢), não mão
- Janela: só `concluido`/`entregue` + `wallet_release_processed_at` null — sem calendário de 60d
- Seller marca `enviado` sem tracking **depois de pago** (regra)
- Refund 590¢ + stock +1 uma vez

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_dq_20260906T1705/` — `_rtdq.dart`, `pass1.dart`, `pass1.json`, `confirm.dart`, `confirm.json`, `confirm_a4_label.dart`, `confirm_a4_label.json`, este relatório.

**NÃO CORRIGIR.**

RESUMO_NUMERICO: P0=0 P1=0 P2=1 P3=0 TOTAL=1
