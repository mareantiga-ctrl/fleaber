# FROZEN_REPORT — RED TEAM CEGO DP · Wallet / release / payout / Connect · POS_DHDM

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
AUDITOR: REDTEAM_BLIND_DP_WALLET_PAYOUT_POS_DHDM_v1
probes_na_tabela: 20 · classes_novas: 12
VEREDICTO: PASS_CEGO_SATURADO
```

```
FROZEN_AT: 2026-09-06T17:16:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DP1, DP2, DP3, DP4, DP5, DP6, DP7]
prefix: RTDP-20260906T1708
staging: fxdknzrqjenzqcvnwqqq
```

buyer `refund-order` 403 · Coptic payout key · charset 400 residual = **não corridos** (HOLD anti-atrofia). ATROFIA: NÃO (0/20 residual clássico).

--------------------------------------------------
## Missão

Buyer **nunca** mint saldo / força release / payout. Seller só no próprio. Release + refund **sem** double credit. Payout: dest Connect / IBAN / key hostil; idempotency; overbalance.

**Resposta:** **Não abriu.** INSERT `wallet_transactions` / ledger JWT → **403 RLS**. RPC credit / debit / apply_tip → **403 GRANT**. PATCH `wallets.balance` / `stripe_account_id` → **0 rows**. Tip unpaid `cs_test_*` pending Δ=0. Release em `pago` → false. seller2 release alheia → false. 2.º release em `concluido` → false Δ2=0. Pago 4242 Δwallet **0** até release. Seller refund 1× `re_` + stock 1→2 Δ=0. Race refund∥release: refund sim, release false, Δ=0. Payout > saldo **400**. `user_id` alheio **400**. Dest no body → Transfer **própria** `acct_1U5mYb…`. Payout∥ mesma key → **1** `tr_`. 2 keys com saldo 1€ → **1** `tr_` saldo 0. Onboarding AccountLink preso ao JWT; GET `wallet_return` sem Transfer; anon **400**. **Mint não.**

--------------------------------------------------
## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

--------------------------------------------------
## TABELA DE PROVAS (20)

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP |
|----------|----------|---------|------|-------------|------------------|
| A1 | POST `wallet_transactions` JWT | buyer+seller INSERT credit 50/80 | **403** RLS ×2 | ΔB=0 ΔS=0 | **HOLD** |
| A2 | rpc credit/debit/tip/ensure | `credit_wallet_once` + `payout_debit` + `apply_tip_once` + `ensure_wallet` alheio | **403** GRANT | ΔS=0 | **HOLD** classe_nova |
| A3 | PATCH `wallets` JWT | balance=9999 · available · `stripe_account_id` alheio | 200 `[]` / 400 coluna / 200 `[]` | dest `acct_1U5mYb…` inalterado Δ=0 | **HOLD** classe_nova |
| A4 | create-live-tip-checkout POST+GET | Session unpaid `cs_test_a1ZEzz…` live `a23a69ec-…` | 200 + GET texto unpaid | tip `c93887b0-…` **pending** ΔS=0 | **HOLD** classe_nova |
| A4b | rpc `send_live_tip_from_wallet` | buyer 99999€ · seller self-tip | 403 `not_allowed` · 400 vendedor inválido | ΔS=0 | **HOLD** classe_nova |
| A5 | POST `wallet_payout_ledger` JWT | seller INSERT `transferred` `tr_fake` | **403** RLS | — | **HOLD** classe_nova |
| D1 | e2e `setup_paid_order` 4242 | PI `pi_3UCiauH7FWYUN3jh1xBciTsL` 590¢ | 200 `pago` | ΔS=0 ΔB=0 `release_at=null` | **HOLD** |
| B1 | `batata_release_seller_wallet_for_order` | release em `pago` sem receção | buyer/seller **200 false** | ΔS=0 | **HOLD** |
| B3 | release JWT seller2 | order alheia `87bdfdef-…` | **200 false** | ΔS=0 | **HOLD** classe_nova |
| B4 | release ×2 buyer | `concluido`+mão fixture `aa2e4acc-…` | 200 **true** + 200 **false** | Δ1=+5,00 Δ2=0 | **HOLD** |
| B5 | PATCH `orders.status` seller | força `concluido` `8bdc2c4e-…` | **403** `order_seller_cannot_mark_concluido` | status `pago` | **HOLD** classe_nova |
| D2 | refund-order seller 1× | pago `cb791d52-…` PI `pi_3UCib8…` | 200 `re_3UCib8H7FWYUN3jh0MBf6GB9` | qty 1→2 ΔS=0 `cancelado` | **HOLD** |
| B2 | refund ∥ release | Future.wait `928baff5-…` | refund `re_3UCibEH…` · release **false** | Δ=0 | **HOLD** race |
| C1 | create-connect-account | amount=99999999 vs 40€ | **400** insuficiente | 0 `tr_` Δ=0 | **HOLD** |
| C2 | create-connect-account | dest alheio + `user_id` S2 | **400** Cannot create another user | 0 `tr_` Δ=0 | **HOLD** classe_nova |
| C2b | create-connect-account | dest=`acct_1UB7nWH…` usd **sem** `user_id` | 200 Transfer **própria** | `tr_1UCicVH7FWYUN3jhozfDVRQj` Δ=−1,00 | **HOLD** classe_nova |
| C3 | payout ∥ mesma key | Future.wait 100¢ `rtdpParallelSame1708k` | 200 `tr_1UCibQH…` + 400 `23505` | **1** Transfer Δ=−1,00 | **HOLD** race |
| C3b | payout ∥ keys distintas | saldo=1,00 · 2× 100¢ | 200 `tr_1UCibTH…` + 400 insuficiente | **1** Transfer 1→0 | **HOLD** classe_nova race |
| C4 | create-connect-account onboarding | POST {} ×2 · GET url · buyer · anon · GET `wallet_return` · S2 reuse | 200 AccountLink próprio · anon **400** · GET sem Transfer | `acct_1U5mYbQeUNx8ar08` urls distintas | **HOLD** classe_nova |
| C5 | create-connect-account anon | amount=100 sem Authorization | **400** Missing authorization | 0 `tr_` | **HOLD** classe_nova |

probes_na_tabela: **20** (matriz A1–A4 · B1–B4 · C1–C4 · D1–D2 = 14 + extras A4b/A5/B5/C2b/C3b/C5).

Dinheiro Stripe TEST real: **sim** — 5 PI succeeded 590¢ (`pi_3UCiauH…`, `pi_3UCiazH…`, `pi_3UCib4H…`, `pi_3UCib8H…`, `pi_3UCibEH…`); 2 refunds (`re_3UCib8H…`, `re_3UCibEH…`); 3 Transfers (`tr_1UCibQH…`, `tr_1UCibTH…`, `tr_1UCicVH…`). Session tip unpaid `cs_test_a1ZEzz…` **não** capturada.

Directo de A4 terminado (`is_active=false`).

--------------------------------------------------
## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| A1 JWT insert txn | DP1 | 403 RLS; Δ=0 |
| A2 RPC credit/adjust | DP1 | 403 GRANT service_role |
| A3 PATCH balance/dest | DP1 | 0 rows; dest próprio |
| A4 tip unpaid | DP7 | pending Δ=0 |
| A4b tip wallet hostil | DP1 | 403/400 Δ=0 |
| A5 INSERT ledger | DP1 | 403 RLS |
| B1 release cedo | DP2 | false em `pago` |
| B2 race refund∥release | DP3 | refund sim; release false; Δ=0 |
| B3 seller2 | DP5 | false |
| B4 double release | DP6 | 2.º false Δ2=0; 1.º +5,00 legítimo |
| B5 seller `concluido` | DP2 | 403 |
| C1 overbalance | DP4 | 400 |
| C2 `user_id` alheio | DP4 | 400 |
| C2b dest body | DP4 | 1 Transfer própria |
| C3 mesma key ∥ | DP3 | 1 `tr_`; gémeo unique 23505 |
| C3b 2 keys saldo 1€ | DP3 | 1 `tr_`; gémeo 400; saldo 0 |
| C4 onboarding reuse | DP4 | AccountLink por JWT; GET sem payout |
| C5 anon payout | DP5 | 400 |
| D1 pago 4242 | DP7 | `pago` Δ=0 até release |
| D2 seller refund 1× | DP7 | `re_` + stock 1→2 Δ=0 |

**Não é finding:** C3 gémeo 400 `23505` (unique) em vez de `idempotent:true` — 1 Transfer, sem double debit. D2/B2 `already_refunded:true` no 1.º POST = forma da resposta após `re_` criado (stock e PI coerentes).

**Contabilidade:** release B4 +5,00 € (venda após `concluido` fixture). Payouts −1 −1 −1 = −3,00 €. Sem mint JWT.

--------------------------------------------------
## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DP1 forge | SIM | HOLD A1–A5 |
| DP2 release | SIM | HOLD B1/B5 janela + FSM |
| DP3 race | SIM | HOLD B2 · C3 · C3b |
| DP4 payout | SIM | HOLD C1/C2/C2b/C4 · ≥1 `tr_` TEST |
| DP5 actor | SIM | HOLD B3 seller2 · C5 anon · buyer JWT forge |
| DP6 idempotency | SIM | HOLD B4 2.º false · C3 1 `tr_` |
| DP7 Δledger | SIM | HOLD D1 Δ=0 · D2 stock+wallet · A4 tip 0 |

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
9. Buyer mint `wallet_transactions` / RPC credit — NÃO
10. PATCH balance / dest Connect — NÃO
11. Tip unpaid credita — NÃO
12. Release antes de janela — NÃO
13. seller2 release alheia — NÃO
14. Double release / refund∥release double credit — NÃO
15. Payout > available / dest alheio / anon — NÃO
16. Onboarding token reuse / GET payout — NÃO
17. Pago 4242 Δwallet antecipado — NÃO
18. Saturação P0–P2=0 após quota ≥14 + ≥1 pago TEST + ≥2 races + ≥3 classe_nova — SIM

ATROFIA: NÃO — buyer refund 403 / Coptic / charset **não** na tabela.  
Poço Stripe TEST: SIM (5 PI + 2 refunds + 3 Transfers + 1 Session unpaid).  
Quota DP-A ≥4: SIM · DP-B ≥4: SIM · DP-C ≥4: SIM · DP-D ≥2: SIM  
Races ≥2: SIM (B2, C3, C3b)  
classe_nova ≥3: SIM (12)  
Lentes 7/7 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ARTEFACTOS

`tool/redteam_blind_dp_20260906T1708/` — `_rtdp.dart`, `pass1.dart`, `confirm_c2.dart`, `pass1.json`, `confirm_c2.json`, este relatório.

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
