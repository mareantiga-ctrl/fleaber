# FROZEN_REPORT — RED TEAM CEGO CU

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
AUDITOR: REDTEAM_BLIND_CU_DISPUTA_POS_ALLOW_v1
FROZEN_AT: 2026-09-06T14:18:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CU1, CU2, CU3, CU4, CU5, CU6, CU7]
probes_na_tabela: 22 (≥12)
VEREDICTO: FAIL_P2
```

Prefixo: `RTCU-20260906T1412`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2 / anon. `service_role` só fixture (`setup_paid_order`), RPC canonical, observação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `4064686f-1949-45fc-8806-c499d1bf0688`

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
10. Buyer manipula qty autoritativa — NÃO (`quantity=0` → `order_money_fields_immutable`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release com disputa = `false`, Δseller 0)
13. Refund excede captura — NÃO (Edge `amount_cents=590` idempotente)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (prova B na disputa A 400; B1 GET objecto B2 404; stored concat 400/NoSuchKey)
21. Buyer assume seller/admin — NÃO (refund-order 403 `Sem permissão.`)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release com disputa = false)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO
27. Regressão funcional (happy path partido) — NÃO (URL limpa **sem** 54000; disputa+prova+FSM OK)
28. Saturação atingida — NÃO (P2 aberto em C1b; C* não está 100% denied)

--------------------------------------------------
MISSÃO
--------------------------------------------------

URL/path canónico limpo → sem 54000. Happy path disputa funciona. Ataques de path continuam denied. Atacar allowlist/canonical — não chase triple-encode.

**Resposta:** hotfix canónico **age**. RPC `https://example.com/a` e signed PNG próprio → **200 sem 54000**. INSERT disputa com prova própria **201** `aberta`. Label canónica **200**. FSM `pedido_devolucao` → `em_devolucao` + reply vendedor **201**. Stock/refund: qty 0→1, Edge `re_3UCfwDH7FWYUN3jh18hoaHuv` 590¢ idempotente.

Path hostil **na maior parte denied** (`%255c..%255c`, `%2e%2e%5c`, `%00`, bucket public, prova B2, label host evil / relativo / evil+needle). Residual CDCI `%25252e` / ZWSP → **400** (não persiste).

Fica **P2** porque `%252f%255c` (slash misto, **sem** `..`) **persiste** em `proof_photos`: o canónico vira `//`, o guarda só exige substring `order_disputes/{buyer}/{oid}/`. Concatena path B2. **Loot: não.**

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos CDCI observados, **não contados** (residual 2/22 ≈ 9% < 50%):
- `%25252e%25252e%25252f` → 400 `dispute_proof_url_denied` (já não 201)
- ZWSP entre dots → 400 `dispute_proof_url_denied`

Não se usou PaysafeCash / PicPay / esaurito / Coptic / follow unpublished.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| CU1 | Canonical RPC + label URL limpa 200. Signed PNG próprio persistido na disputa. |
| CU2 | **Sem 54000** em URL limpa (regressão CO fechada). |
| CU3 | Happy path: disputa 201 `aberta` + prova + `pedido_devolucao` + `em_devolucao`. |
| CU4 | Traversal / null / bucket / prova B / label evil → deny. **P2** `%252f%255c` concat persiste. |
| CU5 | 2.ª disputa 409. FSM buyer/seller avança. |
| CU6 | `quantity=0` 403. Stock restore +1 no refund (não ×2). |
| CU7 | Buyer `refund-order` 403. Release com disputa `false` Δseller 0. Edge 590¢. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia: **5,90 €** (`amount_paid_cents=590`) order `eca7b51c-…` PI `pi_3UCfwDH7FWYUN3jh1QwnTVHo`.
- Edge `refund-order`: `already_refunded` / idempotente, `refund_id=re_3UCfwDH7FWYUN3jh18hoaHuv`, `amount_cents=590`.
- Stock: qty 0 (`devolucao_entregue`/`devolvida`) → **1** após refund-order.
- Δwallet cadeia: buyer 0 · seller −1,00 € no intervalo (não atribuído com prova a este refund; Stripe list 0 no instante da medição).
- Release com disputa: Δ seller **0**.
- Wallets fim: buyer **61,10 €** · seller **58,00 €**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTCU-CU4-mixed-slash-concat-persist · P2 · CU4

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `eca7b51c-9fb9-4824-845b-5a27caf808e9`. Disputa `a3604c80-…` com PNG próprio (201, sem 54000).
2. RPC `batata_storage_url_path_canonical` (`service_role`): `%252f%255c` → `//`.
3. `POST order_dispute_replies` `proof_photos=[prefixo B1 + %252f%255c + path B2]`.
4. Oráculo loot: GET URL persistida, GET objecto B2 como B1, GET chave canónica concatenada.

**Esperado:** `dispute_proof_url_denied` (400), como `%255c..%255c`.

**Obtido:** **201**. `proof_photos` persiste o encoding cru:

`…/ok.png%252f%255corder_disputes/4064686f-…/00000000-…/rtcu-secret.png`

Canónico: `…/ok.png//order_disputes/{B2}/…/rtcu-secret.png`.

O guarda corre o canónico e aceita porque:
- não há `..` após decode (`//` não é traversal);
- `position('order_disputes/{B1}/{oid}/' in path) > 0` (substring, não âncora).

Loot: **não.**
- GET stored sem token → 400 `token`
- GET chave canónica → 404 `NoSuchKey`
- B1 GET objecto B2 → 404 `NoSuchKey`
- B2 GET próprio → 200 PNG 70b

Não é exacto CDCI residual (`%25252e` / ZWSP agora 400). É buraco da **allowlist de path** pós-canónico (needle substring + slash misto).

**Severidade P2:** uma classe (prova hostil persistida). Sem leitura alheia, sem Δwallet. Happy path intacto. Não P1: não há caminho explorável.

**Prova:** `pass1.json` probe `CU-C1b.mixed_252f_255c`; reply `0c24fb88-…`; `confirm_c1b.dart` + `confirm_c1b_loot.json`.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥12 linhas · ≥1 happy path disputa · A1 sem 54000 · C* denied (excepto HOLD C1b).  
`FAIL` = ataque falhou (defesa segurou / happy path OK). `HOLD` = finding. `RESIDUAL` = exacto CDCI observado, não contado.

| # | probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD\|FAIL\|SKIP |
|---|----------|------|-------------|----------|----------|------------------|
| 1 | CU-A1.canon_simple | CU-A | RPC `https://example.com/a` | 200 `"https://example.com/a"` **sem 54000** | — | FAIL |
| 2 | CU-A1.canon_signed | CU-A | RPC signed PNG próprio https | 200 URL lower **sem 54000** | — | FAIL |
| 3 | CU-A3.open_with_canonical_proof | CU-A | `POST order_disputes` proof signed | 201 `aberta` `a3604c80-…` | photos contém oid | FAIL |
| 4 | CU-A2.label_canonical | CU-A | PATCH `return_label_url` signed | 200 | URL própria persistida | FAIL |
| 5 | CU-B1.pedido_devolucao | CU-B | buyer `pedido_devolucao` | 200 | status=`pedido_devolucao` | FAIL |
| 6 | CU-B2.buyer_seller_stable | CU-B | buyer `em_devolucao` + seller reply | 200 / reply 201 | status=`em_devolucao` | FAIL |
| 7 | CU-B3.stock_refund | CU-B | `devolvida` → `refund-order` | 200 `re_…hoaHuv` 590¢ | qty 0→1 Δb=0 | FAIL |
| 8 | CU-C1.pct255c_mixed | CU-C | `%255c..%255c` + B2 | 400 `dispute_proof_url_denied` | persisted=false | FAIL |
| 9 | CU-C1b.mixed_252f_255c | CU-C | `%252f%255c` + path B2 | **201** | photos persiste encoding + B2 | **HOLD** |
| 10 | CU-C2.windows_dotdot_null | CU-C | `%2e%2e%5c` + `%00` | 400 `dispute_proof_url_denied` | persisted=false | FAIL |
| 11 | CU-C2b.dotdot_backslash_only | CU-C | `%2e%2e%5c` | 400 `dispute_proof_url_denied` | persisted=false | FAIL |
| 12 | CU-C3.bucket_swap_public | CU-C | `/object/public/fleaber_private/` | 400 `dispute_proof_url_denied` | persisted=false | FAIL |
| 13 | CU-C3b.proof_order_b_on_a | CU-C | signed object B2 em disputa A | 400 `dispute_proof_url_denied` | persisted=false | FAIL |
| 14 | CU-C4.label_host_evil | CU-C | host `supabase.co.evil.example` | 403 `order_dispute_label_url_denied` | stored vazio | FAIL |
| 15 | CU-C4b.label_relative | CU-C | path relativo sem host | 403 `order_dispute_label_url_denied` | stored vazio | FAIL |
| 16 | CU-C4c.label_evil_host_with_needle | CU-C | `https://evil.example/…/order_disputes/{B1}/{oid}/` | 403 `order_dispute_label_url_denied` | stored vazio | FAIL |
| 17 | CU-R1.triple_25252e | CU-C | residual CDCI `%25252e` | 400 `dispute_proof_url_denied` | persisted=false | RESIDUAL |
| 18 | CU-R2.zwsp_dots | CU-C | residual CDCI ZWSP | 400 `dispute_proof_url_denied` | persisted=false | RESIDUAL |
| 19 | CU-D1.second_dispute | CU-D | 2.ª POST mesma order | 409 `dispute_already_exists_for_order` | — | FAIL |
| 20 | CU-D1b.partial_qty0 | CU-D | PATCH `quantity=0` | 403 `order_money_fields_immutable` | qty=1 | FAIL |
| 21 | CU-D2.buyer_refund_seguro | CU-D | buyer JWT `refund-order` | 403 `Sem permissão.` | — | FAIL |
| 22 | CU-D2.release_with_open_dispute | CU-D | release RPC + disputa aberta | 200 `false` | Δseller=0 | FAIL |

Canonical/happy (CU-A+B): linhas 1–7 = **7** (≥3+3).  
Path deny (CU-C+R): 8–18 = **11** (≥4).  
FSM/refund (CU-D): 19–22 = **4** (≥2).  
**Total 22 ≥ 12.** Happy path disputa completo: linhas 3–7.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- URL limpa / signed PNG → **sem 54000** (fecho do P2 CO)
- `%255c..%255c` → 400 (canónico produz `..`)
- `%00` / `%2e%2e%5c` → 400
- bucket `/object/public/` → 400
- prova order B em disputa A → 400
- label host evil / relativo / evil+needle → 403
- 2.ª disputa → 409
- `quantity=0` → 403 qty=1
- buyer `refund-order` → 403
- release ∥ disputa → XOR (disputa 201, release false, Δ 0)
- residual `%25252e` / ZWSP → 400 (não persiste)

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_cu_20260906T1412/` — `_rtcu.dart`, `pass1.dart`, `pass1.json`, `confirm_c1b.dart`, `confirm_c1b_loot.dart`, `confirm_c1b_loot.json`, este relatório.

**NÃO CORRIGIR.**
