# FROZEN_REPORT — RED TEAM CEGO DG

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
AUDITOR: REDTEAM_BLIND_DG_DISPUTA_POS_CVDA_v1
FROZEN_AT: 2026-09-06T15:46:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DG1, DG2, DG3, DG4, DG5, DG6, DG7]
probes_na_tabela: 31 (≥12)
VEREDICTO: FAIL_P2
```

Prefixo: `RTDG-20260906T1540`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2 / anon. `service_role` só fixture (`setup_paid_order`), RPC canonical/proof_ok, confirmação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `a2f0761a-6366-4c44-855e-b7a70a923a2f`

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
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release com disputa = `false`, Δseller 0)
13. Refund excede captura — NÃO (Edge `amount_cents=590` idempotente)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (prova B2 400; GET B2 como B1 `NoSuchKey`; GET concat `InvalidKey`/`NoSuchKey`)
21. Buyer assume seller/admin — NÃO (refund-order 403 `Sem permissão.`)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release com disputa = false)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO
27. Regressão funcional (happy path partido) — NÃO (prova signed 201; label signed 200; helper `true`; sem 54000)
28. Saturação atingida — NÃO (P2 aberto em label concat `%252f` simples)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Canonical sem 54000. Prova+label signed própria OK. Concat/traversal deny. Bypass path **novo** (não exacto DA `%252f%255c`). CVDA: `//` só após host — prova signed **deve** 201.

**Resposta:** fecho CVDA do `//` no scheme **age**. RPC `https://example.com/a` e signed PNG → **200 sem 54000**. Helper `batata_dispute_proof_url_ok` signed própria → **`true`**. `POST order_disputes` com prova signed → **201**. PATCH label signed → **200**. Controlo `%252f%255c` → **400** (não persiste). `//` cru / `%2f%2f` / `/object/sign//` após host → **400**. Traversal, unicode novo, bucket public, prova B2, label evil/relativo/userinfo/javascript → deny JWT.

Happy path prova+label **OK**. Residual: label JWT aceita concat **`%252f` simples** (um slash, não o par `%252f%255c`) + path B2 — persiste em `return_label_url`. Prova com o mesmo payload → **400** (`[^/]+$`). Loot: **não**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados**:
- Controlo `%252f%255c` → 400 `dispute_proof_url_denied` (fecho DA/CU, 1 linha)
- Residual CDCI `%25252e%25252e%25252f` → 400 (não persiste)
- Happy signed 201 / label 200 — FAIL (defesa/feliz OK), não HOLD

Não se usou ZWSP dots como finding. Residual ≪ 50% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| DG1 | Canonical RPC OK. Helper `proof_url_ok` **true** em signed própria. Label signed **200**. |
| DG2 | **Sem 54000** em URL limpa. |
| DG3 | Disputa + PNG signed **201** `c9b8c0e9-…`. |
| DG4 | Path hostil JWT denied excepto **P2** label `%252f` simples. Controlo `%252f%255c` deny. `//` após host deny. |
| DG5 | 2.ª disputa 409. FSM `pedido_devolucao` → `em_devolucao` + reply vendedor 201. |
| DG6 | Stock restore 0→1 no refund (não ×2). Δwallet 0. |
| DG7 | Buyer `refund-order` 403. Release com disputa `false` Δseller 0. Edge 590¢ idempotente. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia: **5,90 €** (`amount_paid_cents=590`) order `505bc24d-2664-4305-9054-4c4a177116a7`. PI `pi_3UChJ8H7FWYUN3jh1mWpZuRb`.
- Edge `refund-order`: `already_refunded` / idempotente, `refund_id=re_3UChJ8H7FWYUN3jh1QpX2GQL`, `amount_cents=590`.
- Stock: qty 0 → **1** após refund-order.
- Δwallet cadeia: buyer 0 · seller 0.
- Release com disputa: Δ seller **0**.
- Wallets fim: buyer **61,10 €** · seller **37,00 €**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTDG-DG4-label-single-252f-concat · P2 · DG4

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `505bc24d-…`. PNG próprio signed. Disputa `c9b8c0e9-…` **201** com prova própria.
2. Controlo `%252f%255c` em reply → **400** (não contar).
3. `PATCH return_label_url` = URL authenticated própria + **`%252f`** (um slash encoded) + path objecto B2 (`rtdg-secret.png`). Sem `..`, sem `%252f%255c`.
4. Oráculo loot: GET URL persistida, GET chave canónica concatenada, GET objecto B2 como B1.

**Esperado:** 400/403 `order_dispute_label_url_denied` (mesmo critério de prova: um ficheiro, sem concat).

**Obtido:** **200**. `return_label_url` persiste o encoding cru:

`…/ok.png%252forder_disputes/{B2}/00000000-…dg02/rtdg-secret.png`

Canónico: `…/ok.png/order_disputes/{B2}/…/rtdg-secret.png` (um `/`, **não** `//`).

O guarda de label corre o canónico e aceita porque:
- o `//` após host (fecho CVDA) **não** dispara — `%252f` vira um único `/`;
- exige só substring `order_disputes/{B1}/{oid}/` (não âncora `[^/]+$` como a prova);
- não há `..` literal.

A **prova** com o mesmo payload (`DG-B2g`) → **400** `dispute_proof_url_denied` / helper `false`.

Loot: **não.**
- GET stored → 400 `InvalidKey`
- GET chave canónica concat → 404 `NoSuchKey`
- B1 GET objecto B2 → 404 `NoSuchKey`
- helper `proof_url_ok` sobre a URL persistida → `false`

**Severidade P2:** uma classe (URL hostil persistida na etiqueta). Sem leitura alheia, sem Δwallet. Happy path intacto. Não P1: não há caminho explorável.

**Prova:** `pass1.json` probe `DG-B5f.label_single_252f_concat`; `confirm_b5f.dart` / `confirm_b5f.json`.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥12 linhas · ≥1 happy path disputa+prova signed 201 · A1 sem 54000 · B* deny (excepto HOLD novo).  
`FAIL` = ataque falhou (defesa segurou / happy path OK). `HOLD` = finding. Residual CDCI na tabela como FAIL denied.

| # | probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD\|FAIL\|SKIP |
|---|----------|------|-------------|----------|----------|------------------|
| 1 | DG-A1.canon_simple | DG-A | RPC `https://example.com/a` | 200 `"https://example.com/a"` **sem 54000** | — | FAIL |
| 2 | DG-A1.canon_signed | DG-A | RPC signed PNG próprio https | 200 URL lower **sem 54000** | contém `//` no scheme | FAIL |
| 3 | DG-A1.proof_ok_clean | DG-A | RPC `batata_dispute_proof_url_ok` signed própria | 200 **`true`** | — | FAIL |
| 4 | DG-A2.open_with_canonical_proof | DG-A | `POST order_disputes` proof signed | **201** `c9b8c0e9-…` | photos contém oid | FAIL |
| 5 | DG-A3.label_canonical | DG-A | PATCH `return_label_url` signed | **200** | URL própria persistida | FAIL |
| 6 | DG-B1.control_252f_255c | DG-B | controlo `%252f%255c` + B2 | 400 denied | rpc=false persisted=false | FAIL |
| 7 | DG-B2.unicode_big_revsolidus_29f9 | DG-B | joiner U+29F9 + B2 | 400 denied | rpc=false | FAIL |
| 8 | DG-B2b.unicode_box_2572 | DG-B | joiner U+2572 + B2 | 400 denied | rpc=false | FAIL |
| 9 | DG-B2c.cjk_stroke_31d1 | DG-B | joiner U+31D1 + B2 | 400 denied | rpc=false | FAIL |
| 10 | DG-B2d.raw_slashslash_after_file | DG-B | `//extra.png` após ficheiro (cru) | 400 denied | rpc=false | FAIL |
| 11 | DG-B2e.object_sign_double_slash | DG-B | `/object/sign//fleaber_private/` | 400 denied | rpc=false | FAIL |
| 12 | DG-B2f.pct2f2f_after_file | DG-B | `%2f%2f` após ficheiro | 400 denied | rpc=false | FAIL |
| 13 | DG-B2g.single_252f_no_backslash | DG-B | `%252f` simples + path B2 (prova) | 400 denied | rpc=false | FAIL |
| 14 | DG-B3.dotdot_slash | DG-B | `%2e%2e%2f` | 400 denied | rpc=false | FAIL |
| 15 | DG-B3b.residual_25252e | DG-B | residual CDCI `%25252e` (não contar) | 400 denied | rpc=false | FAIL |
| 16 | DG-B4.bucket_public | DG-B | `/object/public/` + needle | 400 denied | rpc=false | FAIL |
| 17 | DG-B4b.proof_b2_on_a | DG-B | signed objecto B2 em disputa A | 400 denied | rpc=false | FAIL |
| 18 | DG-B5.label_evil_host | DG-B | `https://evil.example/…/order_disputes/{B1}/{oid}/` | 403 42501 | stored vazio | FAIL |
| 19 | DG-B5b.label_relative_needle | DG-B | relativo COM needle | 403 42501 | stored vazio | FAIL |
| 20 | DG-B5c.label_schemeless_needle | DG-B | `order_disputes/{B1}/{oid}/ok.png` | 403 42501 | stored vazio | FAIL |
| 21 | DG-B5d.label_host_suffix_evil | DG-B | host `supabase.co.evil.com` + needle | 403 42501 | stored vazio | FAIL |
| 22 | DG-B5e.label_userinfo | DG-B | `https://evil@host/storage/…` | 403 42501 | stored vazio | FAIL |
| 23 | DG-B5f.label_single_252f_concat | DG-B | label `%252f` simples + path B2 | **200** | stored concat B2 | **HOLD** |
| 24 | DG-B5g.label_raw_slashslash | DG-B | label signed + `//extra.png` | 400 denied | stored vazio (PATCH) | FAIL |
| 25 | DG-B5h.label_javascript | DG-B | `javascript:alert(1)//order_disputes/…` | 403 42501 | stored vazio | FAIL |
| 26 | DG-C2.pedido_devolucao | DG-C | buyer `pedido_devolucao` | 200 | status=`pedido_devolucao` | FAIL |
| 27 | DG-C2b.buyer_seller_fsm | DG-C | buyer `em_devolucao` + seller reply | 200 / reply 201 | status=`em_devolucao` | FAIL |
| 28 | DG-C1.second_dispute | DG-C | 2.ª POST mesma order | 409 `dispute_already_exists_for_order` | — | FAIL |
| 29 | DG-C3.stock_refund | DG-C | `devolvida` → `refund-order` | 200 `re_…QpX2GQL` 590¢ | qty 0→1 Δb=0 Δs=0 | FAIL |
| 30 | DG-C4.buyer_refund | DG-C | buyer JWT `refund-order` | 403 `Sem permissão.` | — | FAIL |
| 31 | DG-C4b.release_with_open_dispute | DG-C | release RPC + disputa aberta | 200 `false` | Δseller=0 | FAIL |

Canonical/happy (DG-A): linhas 1–5 = **5** (≥3).  
Path (DG-B): 6–25 = **20** (≥5).  
FSM/refund (DG-C): 26–31 = **6** (≥4).  
**Total 31 ≥ 12.** Happy path disputa+prova signed: linha 4 FAIL (201). Controlo `%252f%255c` linha 6 FAIL (não contar como finding).

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- URL limpa / signed PNG → **sem 54000**; helper **true**; INSERT prova **201**; label signed **200**
- `%252f%255c` → 400 (fecho do P2 DA/CU)
- `//` cru após host / `/object/sign//` / `%2f%2f` → 400
- Unicode U+29F9 / U+2572 / U+31D1 → 400
- `%2e%2e%2f` / bucket public / prova B2 → 400
- label host evil / relativo / scheme-less / suffix `.evil.com` / userinfo / `javascript:` → 403 JWT
- `%252f` simples na **prova** → 400 (só a **label** falha)
- 2.ª disputa → 409
- buyer `refund-order` → 403
- release ∥ disputa → XOR (`false`, Δ 0)
- residual `%25252e` → 400
- stock restore +1, refund 590¢, sem ×2

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_dg_20260906T1540/` — `_rtdg.dart`, `pass1.dart`, `pass1.json`, `confirm_b5f.dart`, `confirm_b5f.json`, este relatório.

**NÃO CORRIGIR.**
