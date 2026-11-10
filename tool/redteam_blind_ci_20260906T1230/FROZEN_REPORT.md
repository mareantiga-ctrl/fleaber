# FROZEN_REPORT — RED TEAM CEGO CI

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
AUDITOR: REDTEAM_BLIND_CI_DISPUTA_POS_BXCC_v1
FROZEN_AT: 2026-09-06T12:42:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CI1, CI2, CI3, CI4, CI5, CI6, CI7, CI8]
VEREDICTO: FAIL_P2
```

Prefixo: `RTCI-20260906T1230`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢) · sem produção · sem Fase 4.  
Atacante = JWT B1/S1/B2/S2 / anon. `service_role` só fixture (`setup_paid_order`) e observação.

B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588` · B2 `9d6d7066-52d8-4bf7-89b3-da31d521c5f8` · S2 `fd0b68a6-f3df-48c6-8250-1b96bab386d1`

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
10. Buyer manipula qty autoritativa — NÃO (`quantity=0` em 2.ª pedido → `order_money_fields_immutable`)
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (release +5,00 € só em concluido sem disputa, JWT do comprador, caminho feliz)
13. Refund excede captura — NÃO (`amount` no body ignorado; Edge 590¢)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer — NÃO (fora de âmbito; 2× refund-order idempotente)
16. Stock=1 duas vendas válidas — NÃO
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO (list B2=`[]`; GET alheio=`NoSuchKey`; URL persistido → 400 / sem PNG)
21. Buyer assume seller/admin — NÃO (refund-order 403; finalize RPC 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (S2 release = false)
25. RLS crítico quebrado — NÃO (B2 INSERT/reply 403; B2/S2 PATCH 0 rows)
26. Edge confia total do cliente — NÃO (`refund-order` ignora `amount` no body)
27. Regressão funcional (happy path partido) — NÃO (pago→enviado→concluido→disputa→pedido_devolucao→em_devolucao→devolucao_entregue→devolvida→refund)
28. Saturação atingida — SIM (poços A–D · lentes CI1–CI8 · tácticas 1–4 · cadeia Stripe+stock+Δwallet)

--------------------------------------------------
MISSÃO
--------------------------------------------------

Ainda desvio **devolução/refund**, **prova alheia**, **stock restore duplo**, ou **fecho seller cedo** — além do path bidi/`%252e` exacto?

**Resposta:** o FSM e o refund Stripe **agem**. 2.ª disputa 409. Seller não marca `pedido_devolucao` nem `devolvida` cedo. B2 não entra na disputa A. `devolvida` não relista stock com PI vivo; restore **uma vez** no `refund-order`. `amount` no body ignorado (590¢). Release com disputa aberta = false. Race release∥disputa: release XOR disputa.

Fica **P2** porque `batata_storage_url_path_canonical` (3 passes) **não cobre** encodings fora da lista BXCC. Persistiram em `proof_photos` / `return_label_url`: `%25252e` (triple), `%e2%88%95` / `%e2%a7%b8` / `%e2%81%84` / `%ef%bc%8f` (UTF-8 percent dos slashes unicode), ZWSP/U+00AD entre dots, `%00`, `%f0%80%80%af`, `％2e` (U+FF05), `%u002e`, U+2216, `\` ASCII (check fold, valor cru). **Loot: não.** Storage `../` resolve **dentro** do prefixo B1; `../../` → 403 RLS.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Exactos BXCC **observados, não contados**:
- seller `pago`→`pedido_devolucao` → 403 `order_seller_cannot_mark_pedido_devolucao`
- `%c0%ae` / `%252e%252e%252f` → 400 `dispute_proof_url_denied` (BXCC **fecha** estes)
- `／` U+FF0F no path → **ainda 201**, persistido (check converte, valor não)
- RLO U+202E → **ainda 201**
- U+2215 / U+29F8 **char** → **ainda 201** (unicode slash residual)

Pass 1 = catálogo FSM. Não se usou como vitória: dual Session, bag unlist, seller PATCH `resolvida` clássico (0 rows, status ficou `aberta`).

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| CI1 | `pedido_devolucao` só buyer a partir de `concluido`+disputa. Sem disputa / a partir de `pago` = 403. 2.ª INSERT + race = 409 `dispute_already_exists_for_order`. Reopen após `PATCH resolvida` (0 rows, status `aberta`) = 409. 2.ª PATCH + `quantity=0` = `order_money_fields_immutable`. |
| CI2 | `devolvida` cedo (pedido/em_devolucao) = `order_devolvida_denied`. Seller `enviado`→`entregue` = `order_seller_cannot_mark_entregue`. Race concluido∥disputa em enviado: disputa **não** abre sem concluido. `return_delivered_at` coluna inexistente (400 PGRST204). Buyer `concluido` mid-return = `order_concluido_denied_during_return`. |
| CI3 | **P2** canonicalizer incompleto: triple-encode / percent-UTF8 slash / ZWSP / `%00` / overlong 4-byte / fullwidth `%` / `%u002e` / U+2216 persistem. Label triple-encode 201. Relativo / file / bucket public / host evil = denied. Prova order B na disputa A = denied. Overwrite seller/buyer = denied. Storage `../` fica no prefixo B1; `../../` 403. |
| CI4 | Edge `amount:1` / `999999` → refund **590¢**. Buyer `refund-order` 403. Buyer `batata_finalize_stripe_order_refund` 403 GRANT. Parcial wallet pós-envio (100% vs oferta 1%) = `dispute_partial_refund_requires_stripe`. Seller RPC = `not_allowed`. Race 2× refund após `devolvida` = idempotente. |
| CI5 | `devolvida` com PI vivo: qty 1→1 (sem restore). Após refund: qty 0→1 (uma unidade). Refund+cancelado: +1 não +2. Disputa×cancelado = `order_cancel_denied_post_pay`, qty inalterada. |
| CI6 | Release concluido sem disputa = `true`, Δseller +5,00 €. Disputa **depois** do release = 403 RLS. Release **com** disputa aberta = `false`, Δseller 0. Race release∥INSERT: release true, disputa 403 (XOR). |
| CI7 | B2 INSERT (próprio id ou spoof B1) 403. S2 INSERT 403. anon 401. B2 reply 403. B2/S2 PATCH 0 rows. Storage list `order_disputes/B2/` como B1 = `[]`. GET alheio = NoSuchKey. S2 release = false. |
| CI8 | Unshipped refund: Δwallet 0/0 (anulação Stripe, não mint). Cadeia disputa→devolvida→refund: stock +1, Stripe 590¢, Δ 0. Caixa release vs disputa coerente. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Captura: **5,90 €** (`amount_paid_cents=590`).
- Wallets (pass 3, após refunds unshipped): buyer **61,10 €** · seller **45,33 €** (Δ 0 nestes refunds).
- Release feliz (order `c8f4a29a-…`, sem disputa): Δ seller **+5,00 €** → seller **55,33 €**.
- Stock chain `51d36c89-…`: qty 0 (vendido) → 0 em `devolvida` sem refund → **1** após `refund-order`.
- Stripe race: 1.º 500 idempotency in-progress; 2.º idempotente; sem 2 capturas.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTCI-CI3-canonical-path-incomplete · P2 · CI3

**Actor:** buyer JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `3ecd963b-07ae-495d-9a26-1b69ed932664`. Disputa `4ed91e49-822e-4e1f-b1a8-34e0fb735ced`.
2. `POST order_dispute_replies` com `proof_photos` = signed storage do prefixo B1/OID + **encoding fora da lista BXCC (3 passes)** + prefixo B2 `order_disputes/{B2}/0000…c2c2/rtci-secret.png`.
3. Confirmação por `POST order_disputes` (INSERT): `%25252e`, `%e2%88%95`, ZWSP, `%00`.
4. Label: `return_label_url` com `%25252e%25252e%25252f` + needle B2 → 201.
5. Storage: `POST object/.../{oid}/../{B2}/file` → key `order_disputes/{B1}/{B2}/file` (ainda prefixo B1). `../../` → 403 RLS.
6. Oráculo loot: GET URL guardada / GET object B2 com JWT B1 → sem PNG.

**Separadores/encodings que persistiram (201), todos a mesma classe (não exacto BXCC):**

| Vector | Onde |
|--------|------|
| `%25252e%25252e%25252f` triple-encode `../` | replies + INSERT + label |
| `%e2%88%95` UTF-8 DIVISION SLASH | replies + INSERT |
| `%e2%a7%b8` UTF-8 BIG SOLIDUS | replies |
| `%e2%81%84` UTF-8 FRACTION SLASH | replies |
| `%ef%bc%8f` UTF-8 fullwidth slash | replies |
| `%00` null | replies + INSERT |
| `.` + ZWSP + `./` | replies + INSERT |
| `.` + U+00AD + `./` | replies |
| `%f0%80%80%af` overlong 4-byte `/` | replies |
| `％2e％2e％2f` fullwidth percent | replies |
| `%u002e%u002e%u2215` | replies |
| U+2216 SET MINUS | replies |
| `\` ASCII (check fold `/`, valor cru) | replies |
| tab U+0009 (201; script `contains` falhou o escape JSON) | replies |

**Esperado:** `dispute_proof_url_denied` / `order_dispute_label_url_denied` após canonical multi-pass (incluindo triple-encode, percent-UTF8 dos slashes, controlos invisíveis, `%00`).

**Obtido:** INSERT/reply **201**, array persistido com o encoding + prefixo B2 no mesmo string.  
Loot: **não**. GET signed sem `token` → 400 `InvalidRequest`; GET B2 `NoSuchKey`. O URL não é um objecto válido. Storage `../` não sai do prefixo do comprador.

**Não é exacto BXCC:** o exacto é bidi / `%252e%252f` / `／` (e o char U+2215/U+29F8). `%c0%ae` e `%252e` **estão fechados** (400). Aqui o canónico **não reescreve** triple / percent-UTF8 / ZWSP / `%00`.

**Severidade P2:** o guarda BXCC é uma lista fechada; grava um URL morto que *parece* apontar a provas alheias. Sem leitura cross-user, sem Δwallet. Uma classe, vários oráculos — **não** inflacionar P2 por variante. Upload `../` no mesmo prefixo = evidência da mesma higiene de path, não P1 (confirmado: `../../` 403).

**Prova:** `pass2.json` findings `CI3.triple_encode_dotdot`, `CI3.pct_utf8_u2215`, `CI3.insert_triple_encode`, `CI3.insert_zwsp_dots`, `CI3.label_triple_encode` + notas `*.loot`; `pass2b.json` `CI3.upload_dotdot_two` 403.

--------------------------------------------------
NÃO-FINDINGS RELEVANTES (vectores do prompt)
--------------------------------------------------

- 2.ª disputa / race → 409 `dispute_already_exists_for_order`
- B2 INSERT / reply disputa A → 403 RLS
- `devolvida` cedo → 403 `order_devolvida_denied`
- seller `enviado`→`entregue` (carrier early) → 403 `order_seller_cannot_mark_entregue`
- race buyer concluido ∥ disputa em enviado → disputa não cola sem concluido
- stock restore dup (refund race / refund×cancel / disputa×cancel) → +1 unidade, não 2
- Edge `amount` no body → ignorado (590¢)
- buyer `refund-order` (Seguro seller-only) → 403
- conluio parcial 100% vs oferta 1% com PI vivo → `dispute_partial_refund_requires_stripe`
- release ∥ disputa aberta → false / XOR na race
- prova order B na disputa A → 400 `dispute_proof_url_denied`
- overwrite proof seller/buyer → 400
- relativo / `file://` / bucket public / host evil → denied
- `\n` no path → 403 `dispute_proof_url_denied`

--------------------------------------------------
ARTEFACTOS
--------------------------------------------------

`tool/redteam_blind_ci_20260906T1230/` — `_rtci.dart`, `pass1.dart`, `pass2.dart`, `pass2b.dart`, `pass3.dart`, `pass1.json`, `pass2.json`, `pass2b.json`, `pass3.json`, `pass1_ids.json`, este relatório.
