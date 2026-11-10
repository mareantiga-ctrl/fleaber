# FROZEN_REPORT — RED TEAM CEGO CO

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
AUDITOR: REDTEAM_BLIND_CO_DISPUTA_POS_CDCI_v1
FROZEN_AT: 2026-09-06T13:28:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CO1, CO2, CO3, CO4, CO5, CO6, CO7, CO8]
probes_na_tabela: 46 (≥28)
VEREDICTO: FAIL_P2
```

Prefixo: `RTCO-20260906T1317`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`), RPC canonical, observação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `cd486f39-e03c-4c29-898a-e824be9e1a32` · S2 `d760ef60-9379-401c-83ec-f7ddcf742f37`

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
12. JWT cria saldo/fundos — NÃO (release com disputa = false, Δseller 0)
13. Refund excede captura — NÃO (Edge `amount_cents=590` com `amount:1` no body)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito; 2× refund-order idempotente, mesmo `refund_id`)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (B2 INSERT 403 RLS; prova B na disputa A 500/403; SVG/HTML 415)
21. Buyer assume seller/admin — NÃO (refund-order 403 `Sem permissão.`)
22. Seller assume buyer/admin — NÃO (seller `pedido_devolucao` 403)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (release com disputa = false)
25. RLS crítico quebrado — NÃO (B2 INSERT 403)
26. Edge confia total do cliente — NÃO (`amount:1` → 590¢)
27. Regressão funcional (happy path partido) — SIM (proof_photos limpo 500 `54000` — ver P2)
28. Saturação atingida — SIM (matriz CO-A/B/C/D/E · 46 probes · cadeia Stripe+stock+Δwallet)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Path `%255c`/mixed, label URL, carrier spoof, stock×2 — além canónico CDCI?

**Resposta:** FSM, refund Stripe, stock e B2 **agem**. `%255c` / `%u005c` / `%25255c` / `%ef%bc%bc` **não persistem** (não há 201 com encoding). Residual CDCI (`%25252e`, ZWSP, `%u002e`) também **não** persiste.

Fica **P2** porque `batata_storage_url_path_canonical` (fecho CDCI) **rebenta em qualquer URL**: RPC service `https://example.com/a` → 500 `54000 null character not permitted`. INSERT/reply com PNG assinado **próprio** → 500. Os vectores CO-A de encoding herdam o mesmo crash (fail-closed, sem loot). Causa: `chr(0)` dentro da classe do `regexp_replace` (Postgres recusa NUL no padrão). **Loot: não.**

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos CDCI/CI **observados, não contados** (residual ≤3):
- `%25252e%25252e%25252f` → 500 `54000` (já não 201)
- ZWSP entre dots → 500 `54000`
- `%u002e%u002e%u2215` → 500 `54000`
- seller `pago`→`pedido_devolucao` → 403 `order_seller_cannot_mark_pedido_devolucao`

Pass 1 = catálogo FSM. Não se usou como vitória.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| CO1 | `pedido_devolucao` só buyer a partir de `concluido`+disputa. Seller / a partir de `pago` = 403. 2.ª INSERT = 409 `dispute_already_exists_for_order`. `quantity=0` = `order_money_fields_immutable`. |
| CO2 | `devolvida` cedo (pedido_devolucao) = `order_devolvida_denied`. Seller `enviado`→`entregue` = `order_seller_cannot_mark_entregue`. |
| CO3 | **P2** canonicalizer CDCI 54000 em qualquer URL (limpo + encodings). `\n`/`\r` = 403 `dispute_proof_url_denied`. Label host evil / relativo = 403 `order_dispute_label_url_denied`. SVG/HTML upload = 415 `InvalidMimeType`. Prova order B / overwrite = 500 (mesmo crash). Sem persistência, sem loot. |
| CO4 | Edge `amount:1` → `amount_cents=590`. Buyer `refund-order` 403. Race 2× refund-order = mesmo `refund_id` (idempotente). |
| CO5 | Restore refund+cancel: qty 0→1→1 (não ×2). Cadeia devolvida→refund: qty 0→1 uma vez. |
| CO6 | Release com disputa aberta = `false`, Δseller 0. Race release∥INSERT: disputa 201, release false, Δ 0 (XOR). |
| CO7 | B2 INSERT (próprio id ou spoof B1) 403 RLS em pago e em concluido. Webhook sem sig 400 `missing_signature`; evento antigo sig inválida 400 `invalid_signature`. |
| CO8 | Unshipped refund Δwallet 0/0. Cadeia disputa→devolvida→refund: stock +1, Edge 590¢, mesmo `re_…`, Δ 0. Caixa release vs disputa coerente. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura cadeia: **5,90 €** (`amount_paid_cents=590`) order `0a2d7017-…` PI `pi_3UCfAFH7FWYUN3jh0sc8hhSZ`.
- Edge 2× `refund-order`: ambos `already_refunded` / idempotente, `refund_id=re_3UCfAFH7FWYUN3jh0e4XxxeX`, `amount_cents=590`.
- Stock chain: qty 0 (`devolvida` sem restore) → **1** após refund-order.
- Δwallet cadeia: buyer 0 · seller 0. Wallets fim pass3: buyer **61,10 €** · seller **62,00 €**.
- Release com disputa: Δ seller **0**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTCO-CO3-canonical-nul-regexp-crash · P2 · CO3

**Actor:** buyer JWT (e `service_role` RPC).

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `1ad6a600-aeea-43af-8a1d-f548c84cdfb8`. Upload PNG próprio `ok.png` (200).
2. RPC `batata_storage_url_path_canonical` (`service_role`) com URL limpo `https://example.com/a` e com signed PNG próprio.
3. `POST order_disputes` com `proof_photos=[signed]`.
4. `POST order_dispute_replies` com o mesmo signed.
5. Matriz CO-A (`%255c`, `%255c..%255c`, mixed `%252f%255c`, `%u005c`, `%c0%af%255c`, `%2e%2e%5c`, `%00`, `%25255c`, `%ef%bc%bc`, `%u005c..%u005c`) + labels `%255c`/`%25255c` no mesmo crash.

**Esperado:** canonical multi-pass devolve texto; proof limpo 201; encodings com `../` efectivo → `dispute_proof_url_denied` (400).

**Obtido:** **500** `54000 null character not permitted` em:
- RPC canonical **qualquer** URL (incluindo `https://example.com/a`)
- INSERT disputa com foto própria
- reply com foto própria
- todos os encodings CO-A excepto `\n`/`\r` (esses 403 `dispute_proof_url_denied`)

Loot: **não.** Nada persistiu. Storage SVG/HTML 415. B2 INSERT 403.

**Não é exacto CDCI residual:** o exacto CI era persistir `%25252e` / ZWSP (201). Aqui o fecho CDCI **parte o canónico** (`chr(0)` na classe do `regexp_replace`). Residual CI agora também 500 — não inflacionar.

**Severidade P2:** uma classe (guarda CDCI crasha). Fail-closed (sem persistência, sem leitura alheia, sem Δwallet). Happy path de anexar prova **partido** (checklist 27). Não P1: não há caminho explorável nem loot.

**Prova:** `pass2b.json` finding `CO-A.happy_path_proof_500`; `pass2.json` probes CO-A1…A18 / CO-B1 / CO-B4; nota `CO3.canonical_rpc`.

--------------------------------------------------
## TABELA DE PROVAS
--------------------------------------------------

Quota: ≥28 linhas · ≥16 path/proof/label · ≥4 FSM · ≥4 refund/stock · ≥2 carrier/B2.  
`FAIL` = ataque falhou (defesa segurou). `HOLD` = finding. `RESIDUAL` = exacto CDCI observado, não contado.

| # | ID | Payload | HTTP / BD | Resultado |
|---|----|---------|-----------|-----------|
| 1 | CO-A1.pct255c | `%255c` + prefixo B2 | 500 `54000` | FAIL |
| 2 | CO-A2.pct255c_dotdot | `%255c..%255c` + B2 | 500 `54000` | FAIL |
| 3 | CO-A3.mixed_252f_255c | `%252f%255c` + B2 | 500 `54000` | FAIL |
| 4 | CO-A4.pct_u005c | `%u005c` + B2 | 500 `54000` | FAIL |
| 5 | CO-A5.c0af_255c | `%c0%af%255c` + B2 | 500 `54000` | FAIL |
| 6 | CO-A6.windows_dotdot_backslash | `%2e%2e%5c` + B2 | 500 `54000` | FAIL |
| 7 | CO-A7.null_filename | `%00` filename + B2 | 500 `54000` | FAIL |
| 8 | CO-A8.newline_path | `\\n` no path | 403 `dispute_proof_url_denied` | FAIL |
| 9 | CO-A9.cr_path | `\\r` no path | 403 `dispute_proof_url_denied` | FAIL |
| 10 | CO-A16.triple_backslash | `%25255c` (fora lista CDCI) | 500 `54000` | FAIL |
| 11 | CO-A17.pct_fullwidth_backslash | `%ef%bc%bc` UTF-8 U+FF3C | 500 `54000` | FAIL |
| 12 | CO-A18.u005c_dotdot | `%u005c..%u005c` | 500 `54000` | FAIL |
| 13 | CO-A10.bucket_swap_public | `/object/public/fleaber_private/` | 500 `54000` | FAIL |
| 14 | CO-A10b.bucket_swap_fleaber | bucket `fleaber` (não private) | 500 `54000` | FAIL |
| 15 | CO-A11.svg_as_photo | Content-Type `image/svg+xml` | 415 `InvalidMimeType` | FAIL |
| 16 | CO-A11.html_as_photo | Content-Type `text/html` | 415 `InvalidMimeType` | FAIL |
| 17 | CO-A12.proof_order_b_on_a | signed URL order B na disputa A | 500 `54000` | FAIL |
| 18 | CO-A12.overwrite_seller | seller PATCH `proof_photos` path B2 | 500 `54000` | FAIL |
| 19 | CO-A12.overwrite_buyer | buyer PATCH fotos = order B | 500 `54000` | FAIL |
| 20 | CO-A.happy_path_proof_500 | signed PNG **próprio** (controlo) | INSERT 500 · reply 500 · RPC `https://example.com/a` 500 | HOLD |
| 21 | CO-B1.label_pct255c | `return_label_url` `%255c`+B2 | 500 `54000` | FAIL |
| 22 | CO-B2.label_host_evil | host `supabase.co.evil.example` | 403 `order_dispute_label_url_denied` | FAIL |
| 23 | CO-B3.label_relative | path relativo sem host | 403 `order_dispute_label_url_denied` | FAIL |
| 24 | CO-B4.label_double_encode_novo | label `%25255c`+B2 | 500 `54000` | FAIL |
| 25 | CO-R1.triple_25252e | residual CDCI `%25252e` | 500 `54000` (já não 201) | RESIDUAL |
| 26 | CO-R2.zwsp | residual CDCI ZWSP | 500 `54000` | RESIDUAL |
| 27 | CO-R3.pct_u002e | residual CDCI `%u002e` | 500 `54000` | RESIDUAL |
| 28 | CO-C1.first_dispute | INSERT disputa em concluido | 201 `6aa0baf4-…` | FAIL |
| 29 | CO-C1.second_dispute | 2.ª POST mesma encomenda | 409 `dispute_already_exists_for_order` | FAIL |
| 30 | CO-C2.partial_qty0 | PATCH `pedido_devolucao` `quantity=0` | 403 `order_money_fields_immutable` qty=1 | FAIL |
| 31 | CO-C3.devolvida_cedo | seller `devolvida` em pedido | 403 `order_devolvida_denied` | FAIL |
| 32 | CO-C4.seller_pedido_devolucao | seller pago→`pedido_devolucao` | 403 `order_seller_cannot_mark_pedido_devolucao` | FAIL |
| 33 | CO-C4.buyer_pedido_from_pago | buyer `pedido_devolucao` sem disputa | 403 `order_pedido_devolucao_denied` | FAIL |
| 34 | CO-C4.buyer_pedido_from_concluido | buyer `pedido_devolucao` +disputa | 200 status=`pedido_devolucao` | FAIL |
| 35 | CO-D1.amount_body | `refund-order` `amount:1` | Edge `amount_cents=590` | FAIL |
| 36 | CO-D2.restore_x2 | refund + PATCH `cancelado` | qty 0→1→1 | FAIL |
| 37 | CO-D3.release_with_open_dispute | release RPC com disputa aberta | 200 `false` Δseller=0 | FAIL |
| 38 | CO-D3.race_release_dispute | parallel release ∥ INSERT disputa | release false · disputa 201 · Δ0 | FAIL |
| 39 | CO-D4.buyer_refund_seguro | buyer JWT `refund-order` | 403 `Sem permissão.` | FAIL |
| 40 | CO8.stripe_refund_chain | disputa→devolvida→2× refund | `re_3UCfAF…` 590¢ · qty 0→1 · Δ0 | FAIL |
| 41 | CO-E1.webhook_carrier_nosig | POST stripe-webhook sem sig | 400 `missing_signature` | FAIL |
| 42 | CO-E1.webhook_old_event | evento t=1600000000 `v1=deadbeef` | 400 `invalid_signature` | FAIL |
| 43 | CO-E1.carrier_entregue_early | seller enviado→`entregue` | 403 `order_seller_cannot_mark_entregue` | FAIL |
| 44 | CO-E2.b2_insert_disputa_a_pago | B2 INSERT disputa encomenda B1 pago | 403 RLS | FAIL |
| 45 | CO-E2.b2_insert_spoof_buyer_id | B2 INSERT `buyer_id=B1` | 403 RLS | FAIL |
| 46 | CO-E2.b2_insert_disputa_a_concluido | B2 INSERT disputa B1 concluido | 403 RLS | FAIL |

Path/proof/label (CO-A+B+R+controlo): linhas 1–27 = **27** (≥16).  
FSM (CO-C): 28–34 = **7** (≥4).  
Refund/stock/release (CO-D+cadeia): 35–40 = **6** (≥4).  
Carrier/B2 (CO-E): 41–46 = **6** (≥2).

--------------------------------------------------
NÃO-FINDINGS RELEVANTES (vectores do prompt)
--------------------------------------------------

- 2.ª disputa → 409 `dispute_already_exists_for_order`
- B2 INSERT disputa A → 403 RLS
- `devolvida` cedo → 403 `order_devolvida_denied`
- seller `enviado`→`entregue` (carrier) → 403
- seller `pedido_devolucao` → 403
- stock restore dup → +1 unidade, não 2
- Edge `amount` no body → 590¢
- buyer `refund-order` → 403
- release ∥ disputa → XOR (disputa 201, release false)
- `%255c` / `%u005c` / `%25255c` / `%ef%bc%bc` → **não** 201 (crash 54000)
- label host evil / relativo → 403
- SVG/HTML como foto → 415 mime
- webhook sem sig / evento antigo → 400
- residual `%25252e` / ZWSP / `%u002e` → já não persistem (500)

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_co_20260906T1317/` — `_rtco.dart`, `pass1.dart`, `pass2.dart`, `pass2b.dart`, `pass3.dart`, `pass1.json`, `pass1_ids.json`, `pass2.json`, `pass2b.json`, `pass3.json`, este relatório.
