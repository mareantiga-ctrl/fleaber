# FROZEN_REPORT — RED TEAM CEGO DA

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
AUDITOR: REDTEAM_BLIND_DA_DISPUTA_POS_CPCU_v1
FROZEN_AT: 2026-09-06T14:56:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DA1, DA2, DA3, DA4, DA5, DA6, DA7]
probes_na_tabela: 28 (≥12)
VEREDICTO: FAIL_P2
```

Prefixo: `RTDA-20260906T1452`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2 / anon. `service_role` só fixture (`setup_paid_order`), RPC canonical/proof_ok, confirmação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `b23a83be-6498-4a88-9182-320581e8b4d3`

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
20. Cross-user dados sensíveis — NÃO (prova B2 em disputa A 400; concat/unicode 400)
21. Buyer assume seller/admin — NÃO (refund-order 403 `Sem permissão.`)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release com disputa = false)
25. RLS crítico quebrado — NÃO
26. Edge confia total do cliente — NÃO
27. Regressão funcional (happy path partido) — **SIM** (URL signed `https://` recusada: prova 400 + label 400; helper `false`)
28. Saturação atingida — NÃO (A* prova própria partida; P2 aberto)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Canonical limpo **sem 54000**. Prova própria OK. Concat/`//`/traversal → deny. Bypass path **novo** (não só `%252f%255c` exacto CU).

**Resposta:** RPC canonical `https://example.com/a` e signed PNG → **200 sem 54000**. Fecho CU `%252f%255c` **age** (400, não persiste). Traversal / unicode slash / overlong / bucket public / prova B2 / label evil — **denied** no JWT.

Happy path **prova+label com URL signed real está partido.** `batata_dispute_proof_url_ok` exige prefixo `https://…/storage/` **e** `position('//' in v_url)=0`. Qualquer URL `https://` canónica contém `//` no scheme → helper `false` → INSERT prova **400** `dispute_proof_url_denied` → PATCH label **400** `order_dispute_label_url_denied`. Disputa **sem** fotos ainda abre (201). FSM/stock/refund intactos.

Path hostil JWT: **100% deny**. Residual CDCI `%25252e` → 400 (não contar).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos observados, **não contados**:
- Controlo `%252f%255c` → 400 `dispute_proof_url_denied` (fecho CU, 1 linha)
- Residual CDCI `%25252e%25252e%25252f` → 400 (não persiste)

Não se usou PaysafeCash / ZWSP dots como finding. Residual ≪ 50% → não `ATROFIA_ABORT`.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| DA1 | Canonical RPC OK. Helper `proof_url_ok` **false** em signed própria. Label canónica **400**. |
| DA2 | **Sem 54000** em URL limpa. |
| DA3 | Disputa vazia 201. **Prova PNG signed 400** (regressão). |
| DA4 | Path hostil JWT denied (unicode, overlong, `\`, `..`, public, B2, label evil/relativo). Controlo `%252f%255c` deny. |
| DA5 | 2.ª disputa 409. FSM `pedido_devolucao` → `em_devolucao` + reply vendedor 201. |
| DA6 | Stock restore 0→1 no refund (não ×2). Δwallet 0. |
| DA7 | Buyer `refund-order` 403. Release com disputa `false` Δseller 0. Edge 590¢ idempotente. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia: **5,90 €** (`amount_paid_cents=590`) order `27de0758-9e80-41d8-b016-391420a2bf02`. PI `pi_3UCgWSH7FWYUN3jh0IJzCrj0`.
- Edge `refund-order`: `already_refunded` / idempotente, `refund_id=re_3UCgWSH7FWYUN3jh072SoyEg`, `amount_cents=590`.
- Stock: qty 0 (`devolucao_entregue`) → **1** após refund-order.
- Δwallet cadeia: buyer 0 · seller 0.
- Release com disputa: Δ seller **0**.
- Wallets fim: buyer **61,10 €** · seller **50,00 €**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTDA-DA3-https-double-slash-false-positive · P2 · DA1/DA3

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `27de0758-…`. PNG próprio no prefixo `order_disputes/{B1}/{oid}/ok.png`, URL signed `https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/v1/object/sign/…`.
2. RPC `batata_storage_url_path_canonical` → mesmo `https://…` **sem 54000**, `contains('//')=true`.
3. RPC `batata_dispute_proof_url_ok` (signed, buyer, oid) → **`false`**. Vazio → `true`.
4. `POST order_disputes` `proof_photos=[signed]` → **400** `dispute_proof_url_denied` (23514). Fallback sem fotos → **201** `1b290954-…`.
5. `PATCH return_label_url=signed` → **400** `order_dispute_label_url_denied` (23514).

**Esperado:** prova+label URL limpa 201/200 (missão A2/A3; CU pré-CPCU 201).

**Obtido:** helper e triggers recusam **qualquer** URL canónica `https://…` porque `position('//' in v_url)` casa o `//` do scheme, ao mesmo tempo que o helper **exige** `like 'https://fxdknzrqjenzqcvnwqqq.supabase.co/storage/%'`. Conjunto vazio: URL não-vazia válida é impossível.

**Severidade P2:** uma classe (regressão funcional do fecho CU-P2). Sem loot, sem Δwallet, sem persistência hostil JWT. Disputa sem anexo ainda funciona. Não P1: não há caminho explorável — o buraco **bloqueia** o fluxo legítimo.

**Prova:** `pass1.json` probes `DA-A1.proof_ok_clean`, `DA-A2.open_with_canonical_proof`, `DA-A3.label_canonical`; `confirm_slash.dart` / `confirm_slash.json`.

*Observação (não finding JWT):* `service_role` PATCH de label **relativa** / `https:/` (um slash) / scheme-less **persiste** (guarda CPCU sem host + sem `//`). JWT nas mesmas URLs → **403 42501** (guarda antigo). Actor da missão = JWT; não contar.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥12 linhas · ≥1 happy path disputa+prova · A1 sem 54000 · B* deny (excepto HOLD prova própria).  
`FAIL` = ataque falhou (defesa segurou / happy path OK). `HOLD` = finding. Residual CDCI na tabela como FAIL denied.

| # | probe_id | poço | URL/payload | HTTP/RPC | BD/stock | HOLD\|FAIL\|SKIP |
|---|----------|------|-------------|----------|----------|------------------|
| 1 | DA-A1.canon_simple | DA-A | RPC `https://example.com/a` | 200 `"https://example.com/a"` **sem 54000** | — | FAIL |
| 2 | DA-A1.canon_signed | DA-A | RPC signed PNG próprio https | 200 URL lower **sem 54000** | contém `//` | FAIL |
| 3 | DA-A1.proof_ok_clean | DA-A | RPC `batata_dispute_proof_url_ok` signed própria | 200 **`false`** | empty→`true` | **HOLD** |
| 4 | DA-A2.open_with_canonical_proof | DA-A | `POST order_disputes` proof signed | **400** `dispute_proof_url_denied` | fallback vazio 201 `1b290954-…` | **HOLD** |
| 5 | DA-A3.label_canonical | DA-A | PATCH `return_label_url` signed | **400** `order_dispute_label_url_denied` | stored vazio | **HOLD** |
| 6 | DA-B1.control_252f_255c | DA-B | controlo `%252f%255c` + B2 | 400 denied | rpc=false persisted=false | FAIL |
| 7 | DA-B2.unicode_revsolidus_29f5 | DA-B | joiner U+29F5 + B2 | 400 denied | rpc=false | FAIL |
| 8 | DA-B2b.unicode_small_revsolidus_fe68 | DA-B | joiner U+FE68 + B2 | 400 denied | rpc=false | FAIL |
| 9 | DA-B2c.overlong_c1af | DA-B | joiner `%c1%af` + B2 | 400 denied | rpc=false | FAIL |
| 10 | DA-B2d.box_slash_2571 | DA-B | joiner U+2571 + B2 | 400 denied | rpc=false | FAIL |
| 11 | DA-B2e.math_rising_27cb | DA-B | joiner U+27CB + B2 | 400 denied | rpc=false | FAIL |
| 12 | DA-B2f.scheme_single_slash | DA-B | `https:/` host supabase + ficheiro próprio | 403/rpc false | persisted=false | FAIL |
| 13 | DA-B2g.backslash_raw | DA-B | joiner `\` + B2 | 400 denied | rpc=false | FAIL |
| 14 | DA-B3.dotdot_backslash | DA-B | `%2e%2e%5c` | 400 denied | rpc=false | FAIL |
| 15 | DA-B3b.residual_25252e | DA-B | residual CDCI `%25252e` (não contar) | 400 denied | rpc=false | FAIL |
| 16 | DA-B4.bucket_public | DA-B | `/object/public/` + needle | 400 denied | rpc=false | FAIL |
| 17 | DA-B4b.proof_b2_on_a | DA-B | signed objecto B2 em disputa A | 400 denied | rpc=false | FAIL |
| 18 | DA-B5.label_evil_host | DA-B | `https://evil.example/…/order_disputes/{B1}/{oid}/` | 403 42501 | stored vazio | FAIL |
| 19 | DA-B5b.label_relative_needle | DA-B | relativo COM needle | 403 42501 | stored vazio | FAIL |
| 20 | DA-B5c.label_https_single_slash | DA-B | `https:/evil…` + needle | 403 42501 | stored vazio | FAIL |
| 21 | DA-B5d.label_schemeless_needle | DA-B | `order_disputes/{B1}/{oid}/ok.png` | 403 42501 | stored vazio | FAIL |
| 22 | DA-B5e.label_auth_concat_no_slashmix | DA-B | authenticated + `/../` + B2 | 400 23514 | stored vazio | FAIL |
| 23 | DA-C2.pedido_devolucao | DA-C | buyer `pedido_devolucao` | 200 | status=`pedido_devolucao` | FAIL |
| 24 | DA-C2b.buyer_seller_fsm | DA-C | buyer `em_devolucao` + seller reply | 200 / reply 201 | status=`em_devolucao` | FAIL |
| 25 | DA-C1.second_dispute | DA-C | 2.ª POST mesma order | 409 `dispute_already_exists_for_order` | — | FAIL |
| 26 | DA-C3.stock_refund | DA-C | `devolvida` → `refund-order` | 200 `re_…SoyEg` 590¢ | qty 0→1 Δb=0 Δs=0 | FAIL |
| 27 | DA-C4.buyer_refund | DA-C | buyer JWT `refund-order` | 403 `Sem permissão.` | — | FAIL |
| 28 | DA-C4b.release_with_open_dispute | DA-C | release RPC + disputa aberta | 200 `false` | Δseller=0 | FAIL |

Canonical/happy (DA-A): linhas 1–5 = **5** (≥3).  
Path (DA-B): 6–22 = **17** (≥5).  
FSM/refund (DA-C): 23–28 = **6** (≥4).  
**Total 28 ≥ 12.** Happy path disputa+prova: linha 4 HOLD (partida). Controlo `%252f%255c` linha 6 FAIL (não contar como finding).

--------------------------------------------------
NÃO-FINDINGS RELEVANTES
--------------------------------------------------

- URL limpa / signed PNG → **sem 54000**
- `%252f%255c` → 400 (fecho do P2 CU)
- Unicode slash U+29F5 / U+FE68 / U+2571 / U+27CB → 400
- overlong `%c1%af` / backslash raw / `%2e%2e%5c` → 400
- bucket `/object/public/` → 400
- prova B2 em disputa A → 400
- label host evil / relativo / `https:/` / scheme-less → 403 JWT
- 2.ª disputa → 409
- buyer `refund-order` → 403
- release ∥ disputa → XOR (`false`, Δ 0)
- residual `%25252e` → 400
- stock restore +1, refund 590¢, sem ×2

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_da_20260906T1452/` — `_rtda.dart`, `pass1.dart`, `pass1.json`, `confirm_slash.dart`, `confirm_slash.json`, este relatório.

**NÃO CORRIGIR.**
