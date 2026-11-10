# FROZEN_REPORT — RED TEAM CEGO EJ · Wallet + Edge pós-pago · POS_OPEN_MVP

## CONTAGEM

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

```
AUDITOR: REDTEAM_BLIND_EJ_WALLET_EDGE_POS_OPEN_v1
probes_na_tabela: 20 · classes_novas: 18 · races: 5
VEREDICTO: PASS_CEGO_SATURADO
```

```
FROZEN_AT: 2026-09-06T19:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EJ1, EJ2, EJ3, EJ4, EJ5, EJ6, EJ7]
prefix: RTEJ-20260906T1905
staging: fxdknzrqjenzqcvnwqqq
```

Coptic payout key · charset 400 = **não corridos** (HOLD anti-atrofia). Tip seller≠owner **não** corrido. B6 buyer `refund-order` 403 = **1 residual** na mesma linha que seller OK. B2 0ms clássico (crédito+disputa com clawback net=0) documentado **dentro** de B2; ângulo novo = dispute-first 25ms. Residual clássico 2/20 (B6 + D1 caixa) = 10% ≪ 40%. **Não** ATROFIA_ABORT.

--------------------------------------------------
## Missão

Após pago: release∥disputa **sem** crédito líquido **e** claim aberto; refund seller-only; tip unpaid Δ=0; settle **não** confia amount do cliente.

**Resposta:** **Missão fechada.** B2 0ms: release `true` + disputa `201 aberta` **e** clawback `estorno` 5,00 € → **net=0**, `both=false`. B2 25ms dispute-first: disputa `aberta`, **0** txn, release não creditou. D2 após crédito: INSERT disputa **403 RLS** (sem claim). B6 buyer **403** «Sem permissão» · seller **1** `re_`. A4/C2 tip pending Δ=0. C1b bag amount=1 vs SKU 12 € → `server_amount_cents=1325` `amount_total=1325`; PUT settle **400** metadata; GET **402**; order `reserva_pendente`. Mint JWT **não**. Double credit **não**. Payout∥ **1** `tr_`.

--------------------------------------------------
## Findings abertos

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## TABELA DE PROVAS (20)

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP | classe_nova? |
|----------|----------|---------|------|-------------|------------------|--------------|
| A1 | UPSERT merge-duplicates + DELETE txn JWT | id existente amount=7777 · order_id fake | upsert **400** 22P02 · DEL **200 []** | Δ=0 | **HOLD** | **SIM** |
| A1b | UPSERT/INSERT txn JWT sem oid | amount=4444 / 12.34 | **403** RLS ×2 | Δ=0 | **HOLD** | **SIM** |
| A2 | rpc payout_finish + credit Content-Profile + claw/debit JWT | finish tr_fake 9999¢ · amount="999" | finish **404** PGRST202 · credit **403** 42501 | Δ=0 | **HOLD** | **SIM** |
| A3 | PATCH wallets `or=(id.eq.S1)` dest alheio + available_balance | dest `acct_1UChok…` | or **200 []** · avail **400** PGRST204 | acct próprio `acct_1U5mYb…` Δ=0 | **HOLD** | **SIM** |
| A4 | tip unpaid + PATCH live_tips paid JWT + GET settle | live `0143849f-…` 2€ | create **200** `cs_test_a1zJXV…` · PATCH **200 []** · GET unpaid | tip `9c6b0893-…` **pending** Δ=0 | **HOLD** | **SIM** |
| A5 | POST `/graphql/v1` insert txn | mutation amount=50 | **200** errors `pg_graphql extension is not enabled` | Δ=0 | **HOLD** | **SIM** |
| B1 | release cedo `pago` + PATCH concluido JWT | oid `848371c1-…` | relB/S **200 false** · PATCH **403** `order_concluido_requires_shipped` | Δ=0 status=`pago` | **HOLD** | **SIM** |
| B5 | seller2 PATCH flag + release + disputa alheia | S2 em `848371c1-…` | flag **200 []** · rel **false** · disp **403 RLS** | Δ=0 | **HOLD** | **SIM** |
| D1 | pago 4242 + release legítimo | PI `pi_3UCkYU…` concluido+mão | **200 true** | **Δ=+5,00** txn `22f12bec-…` | **HOLD** | não |
| D2 | INSERT disputa após release | mesmo oid D1 | **403 RLS** | net=5 open_n=0 **both=false** | **HOLD** | **SIM** |
| A6 | PATCH `wallet_release_processed_at=null` JWT + 2.º release | reabrir flag D1 | PATCH **403** `order_wallet_release_flag_immutable` · rel2 **false** | Δ=0 | **HOLD** | **SIM** |
| B4 | triple release ∥ B+S+S2 | oid `9e25a5c0-…` | true + false + false | Δ=+5,00 **trueCount=1** | **HOLD** | **SIM** race |
| B3 | refund ∥ release após concluido | oid `6ef29f2f-…` | ref **403** `order_refund_blocked_shipped` · rel **true** | Δ=+5,00 sem `re_` | **HOLD** | **SIM** race |
| B2 | release∥disputa 0ms + dispute-first 25ms | `ddcbd53d-…` / `850d3b93-…` | 0ms rel **true** disp **201** · 25ms disp **201** | 0ms venda+estorno **net=0** open; 25ms net=0 open credit=0 **both=false** | **HOLD** | **SIM** race |
| B6 | buyer refund 403 + seller OK | oid `1a0b6061-…` PI `pi_3UCkYo…` | buyer **403** · seller 200 `re_3UCkYo…` idempotent | Δ=0 | **HOLD** | não |
| C1 | CPI amount=1 + PUT settle + GET `pi_` sid | unpaid `1ac69e6d-…` + PI pago | ck **400** claim contention · GET pi_ **400** unpaid copy | unpaid `reserva_pendente` pago intacto | **HOLD** | **SIM** |
| C1b | bag amount=1 + PUT settle + GET amount=1 | oid `c346bac5-…` SKU 12€ | bag **200** · PUT **400** metadata · GET **402** | **quoted=1325** stripe=1325 `reserva_pendente` | **HOLD** | **SIM** |
| C2 | tip `captured=true` ∥ PATCH lives ended JWT buyer | live `85cebbd8-…` | tip **200** `cs_test_a1wZ4i…` · unpub **403** lives · GET unpaid | tip `cdd1aca1-…` **pending** Δ=0 | **HOLD** | **SIM** race |
| C3 | payout over + dest S2 + ∥ body key vs Idempotency-Key header | 99999999 · dest S2 · key `rtejParallelSame1905k` | over **400** insuficiente · dest **400** another user · a **200** `tr_1UCkZE…` · b **400** | **1** Transfer n=1 | **HOLD** | **SIM** race |
| D3 | Transfer count pós-C3 | ledger `stripe_transfer_id` | n=1 | `tr_1UCkZEH7FWYUN3jh0RAyXfgG` 100¢ `balance_after=18` agora=18 | **HOLD** | **SIM** |

probes_na_tabela: **20** (matriz A1–A4 · B1–B6 · C1–C3 · D1–D3 = 16 + A5/A6/A1b/C1b).

C3-confirm (não linha de matriz): ledger `transferred` 100¢ `balance_after=18` = saldo actual 18 — débito coerente com o Transfer.

Dinheiro Stripe TEST real: **sim** — 7 PI succeeded 590¢ (`pi_3UCkYU…`, `pi_3UCkYa…`, `pi_3UCkYe…`, `pi_3UCkYi…`, `pi_3UCkYl…`, `pi_3UCkYo…`, `pi_3UCkYu…`); 1 refund (`re_3UCkYoH7FWYUN3jh0IC8KF0w`); 1 Transfer (`tr_1UCkZEH7FWYUN3jh0RAyXfgG`). Tip/bag Sessions unpaid `cs_test_a1zJXV…` / `cs_test_a1wZ4i…` / `cs_test_a1aVbm…` **não** capturadas.

Directos A4/C2 terminados (`is_active=false`).

--------------------------------------------------
## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| A1 UPSERT+DELETE | EJ1 | 400 uuid fake; DEL 0 rows; A1b 403 RLS |
| A2 finish/credit/claw/debit JWT | EJ1 | 404 assinatura / 403 GRANT |
| A3 PATCH or dest | EJ1 | 0 rows; acct próprio |
| A4 PATCH tips paid | EJ2 | pending Δ=0 |
| A5 graphql | EJ1 | extension off |
| B1 release pago + PATCH JWT | EJ3 | false; 403 shipped |
| B2 0ms+25ms | EJ4 | net líquido+claim = falso (clawback / só disputa) |
| B3 refund∥release concluido | EJ4 | refund shipped 403; 1 crédito |
| B4 triple | EJ3 | 1 crédito |
| B5 seller2 | EJ6 | [] / false / 403 |
| B6 buyer 403 | EJ4 | 1 residual seller-only |
| C1 claim contention | EJ2 | 400; pago alheio intacto |
| C1b amount servidor | EJ2 | 1325 vs 1; PUT 400; GET 402 |
| C2 tip∥unpublish JWT | EJ2 | pending Δ=0; PATCH lives 403 |
| C3 over/dest/header | EJ6 | 1 tr_ |
| D1 pago+release | EJ7 | Δ=+5,00 |
| D2 disputa pós-release | EJ5 | 403 RLS; sem claim |
| D3 count | EJ7 | n=1 |
| A6 flag JWT | EJ3 | 403 immutable |

**Não é finding:** B2 0ms `release=true` **e** disputa `201` **com** clawback net=0 (missão: sem crédito **líquido** + claim). D2 RLS recusa INSERT depois da flag — mais forte que clawback. C3 `Δ` snapshot pass1 =0 com `balance_after=18` agora=18: o débito bate com o ledger (não double wallet+Connect). C1 pass1 claim contention não citou Session — fechado em C1b. GET tip unpaid **200** copy «ainda não confirmado» sem crédito — **não contar** (igual ED/DX).

**Contabilidade:** D1/B4/B3 +5 cada; B2 0ms +5 venda −5 estorno = 0; B2 25ms 0; A6 0. Payout C3 −1 € (100¢). Sem mint JWT. 1 `re_` (B6). 1 `tr_`.

--------------------------------------------------
## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. JWT UPSERT/INSERT/DELETE wallet_transactions — NÃO (400/403; Δ=0)
10. RPC credit/debit/clawback/finish JWT — NÃO (404/403 GRANT)
11. PATCH wallets dest/balance or-filter — NÃO (200 []; acct próprio)
12. Tip unpaid / PATCH status=paid / captured=true credita — NÃO (pending Δ=0)
13. GraphQL insert txn — NÃO (extension off)
14. Release cedo em `pago` / PATCH concluido JWT — NÃO (false; 403)
15. seller2 flag/release/disputa alheia — NÃO
16. Double/triple release >1 crédito — NÃO (trueCount=1)
17. Release∥disputa crédito líquido + claim — NÃO (clawback net=0 / só disputa)
18. Refund∥release em concluido double — NÃO (refund shipped 403)
19. Buyer refund-order aberto — NÃO (403)
20. JWT limpa flag e re-credita — NÃO (403 immutable)
21. Disputa após release = crédito+claim — NÃO (403 RLS)
22. Settle/bag amount cliente vence servidor — NÃO (1325 vs 1)
23. PUT settle / `pi_` como session liquida unpaid — NÃO (400/402)
24. Payout over/dest alheio extra Transfer — NÃO
25. Payout∥ header vs body >1 tr_ — NÃO (n=1)
26. Pago 4242 + release Δ observado — SIM (+5,00)
27. Saturação P0–P2=0 após quota ≥16 + ≥4 classe_nova + ≥3 races + ≥1 dinheiro TEST — SIM

Lacuna honesta: C1 POST CPI `amount=1` numa order `reserva_pendente` do B1 caiu **400 claim contention** (mutex saco) — settle amount fechado no **C1b** com buyer2 + bag. Sem `sk_test_` local → sem captura 4242 das Sessions de tip. `batata_wallet_payout_finish` JWT 404 por assinatura (`text,text,boolean`) — GRANT service_role confirmado no SQL; não é superfície JWT útil.

--------------------------------------------------
## FINDINGS (contáveis)

Nenhum. P0=0 P1=0 P2=0 P3=0.

--------------------------------------------------
## SATURAÇÃO

- Quota: 20 ≥ 16
- classe_nova: 18 ≥ 4
- races: 5 ≥ 3 (release∥disputa, refund∥release, payout∥payout; extra triple release, tip∥unpublish)
- ≥1 order paga + Δ wallet: D1 `pi_3UCkYUH7FWYUN3jh1VAp0ni1` Δ=+5,00
- Residual clássico: 2/20 = 10% < 40%
- P0=P1=P2=0
- Código **não** corrigido · produção intocada · Fase 4 não

```
AUDITOR: REDTEAM_BLIND_EJ_WALLET_EDGE_POS_OPEN_v1
probes_na_tabela: 20 · classes_novas: 18 · races: 5
VEREDICTO: PASS_CEGO_SATURADO
```

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0

**NÃO CORRIGIR.**
