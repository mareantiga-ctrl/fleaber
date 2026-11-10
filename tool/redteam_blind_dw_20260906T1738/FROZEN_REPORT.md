# FROZEN_REPORT — RED TEAM CEGO DW · Wallet / release / payout / Connect · POS_DNDS

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: SIM → quantos: 1
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

```
1. P0 dinheiro irreversível encontrado? NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado? SIM
4. Quantos P1: 1
5. P2 hygiene encontrado? NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_DW_WALLET_POS_DNDS_v1
probes_na_tabela: 19 · classes_novas: 14
VEREDICTO: FAIL_P1
```

```
FROZEN_AT: 2026-09-06T17:46:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DW1, DW2, DW3, DW4, DW5, DW6, DW7]
prefix: RTDW-20260906T1738
staging: fxdknzrqjenzqcvnwqqq
```

buyer `refund-order` 403 · Coptic payout key · charset 400 residual = **não corridos** (HOLD anti-atrofia). ATROFIA: NÃO (0/19 desses clássicos).

--------------------------------------------------
## Missão

Buyer nunca mint/force release/payout. Seller só no próprio. Release+refund sem double credit. Payout: overbalance, dest alheio, idempotency, Connect hostil. Ângulos **novos** vs DP: UPSERT/UPDATE txn, `payout_finish` p_failed, PATCH profiles/flag, type=`reembolso` negativo, PATCH tips, webhook sem assinatura, release∥ paralelo, case-fold ASCII, amount negativo/array, GET amount, crash_inject sem secret, credit∥debit, **release∥disputa em concluido**.

**Resposta:** **Abriu P1-1.** Race `batata_release_seller_wallet_for_order` ∥ `POST order_disputes` em `concluido`+mão: crédito **+5,00 €** (`venda`) **e** disputa `aberta` no mesmo instante. Refund seller **403** `order_refund_blocked_shipped`; buyer **403** sem permissão; 2.º release false; sem clawback. O resto da matriz **HOLD**: INSERT/UPSERT/PATCH txn **403 RLS**; RPC finish/credit **403 GRANT**; PATCH profiles **400** coluna; DELETE wallets **0 rows**; tip unpaid `pending` Δ=0; PATCH tips **0 rows**; pago 4242 Δ=0 até release; flag release **403 immutable**; seller2 false; release∥ ×2 **1** crédito; refund 1× `re_` stock 1→2 Δ=0; refund∥release em `pago` Δ=0; over/neg/array **400**; dest/IBAN → 1 Transfer **própria**; mesma key **1** `tr_`; case-fold ASCII **1** `tr_` (mesmo id, 2× 200); GET amount sem payout; crash sem secret ignorado; webhook **400** missing_signature; credit∥debit credit **403**. **Mint JWT não.**

--------------------------------------------------
## Findings abertos

### P1-1 — B5-release-disputa

**O que isto é:** o comprador confirma a receção (isso liberta o dinheiro ao vendedor) e, ao mesmo tempo, abre uma disputa. A regra da carteira é: se já há disputa aberta, **não** creditar. Os dois pedidos em paralelo furam essa regra.

**Quem / onde:** Comprador B1 · Vendedor S1 · encomenda `ff0851b9-3378-43d9-a894-742e72c8aa69` (PI `pi_3UCjBKH7FWYUN3jh03vrsrUB` 590¢ succeeded) · disputa `6bc94bed-1ba0-487a-b36c-574716973292`.

**O que fizemos:** encomenda paga Stripe TEST; fixture `concluido` + entrega em mão (janela em que o release é legítimo). No mesmo instante: RPC de libertação (B1) **e** INSERT disputa (B1). Depois: 2.º release, refund seller, refund buyer.

**Esperado vs resultado**
- Ecrã/RPC libertação: esperado recusar se disputa aberta → visto **200 true** (crédito)
- Disputa: esperado recusar **ou** bloquear o crédito → visto **201** `status=aberta`
- Base de dados: esperado Δwallet 0 **ou** disputa inexistente → visto txn `venda` **+5,00 €** `71e685f5-…` e `wallet_release_processed_at=2026-09-06T16:44:41.337471Z`; disputa `created_at=…16:44:41.338334Z` (863 µs depois)
- Stripe: esperado PI preso / refund coordenado → visto PI **sem** `re_`; `wallet_refund_processed_at=null`
- Refund seller: esperado recusar por disputa **ou** clawback → visto **403** `order_refund_blocked_shipped` (já concluída)
- Refund buyer: esperado recusar → visto **403** Sem permissão
- 2.º release: esperado false → visto **false**; Δ confirm = 0 (sem clawback)

**Conclusão:** **P1** — caminho explorável. O cadeado da encomenda vê disputas, mas o INSERT da disputa **não** partilha esse cadeado: os dois passam. O vendedor fica com 5 € na carteira **e** o comprador com disputa aberta; ninguém anula a captura Stripe por este fluxo. Não marcamos P0: não demonstrámos refund Stripe + levantamento irreversível da mesma fatia neste passo (o saldo disponível foi depois alterado por fixtures de payout).
**Prova:** `pass1.json` B5 + `confirm_b5.json`.

--------------------------------------------------
## TABELA DE PROVAS (19)

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP |
|----------|----------|---------|------|-------------|------------------|
| A1 | POST txn + UPSERT wallets + PATCH txn | credit alien 50 · debit −80 · UPSERT 9999 · PATCH 777 | **403** RLS ×3; PATCH sem mint | ΔB=0 ΔS=0 | **HOLD** classe_nova |
| A2 | rpc finish / reembolso_cents / remaining / credit reembolso / adjust | `payout_finish` p_failed tr_fake · credit type=reembolso 33 | finish **403** GRANT · reemb 400 uuid · remain 404 · credit **403** · adj 404 | ΔS=0 | **HOLD** classe_nova |
| A3 | PATCH profiles + DELETE/INSERT wallets | wallet_balance / stripe_account_id · DELETE S1 · INSERT S2 | 400 coluna · DELETE **200 []** · INSERT **403** | wallet existe Δ=0 | **HOLD** classe_nova |
| A4 | tip-checkout unpaid + PATCH live_tips | live `3d16f8fa-…` 2€; PATCH paid 99 | 200 Session + GET unpaid; PATCH **200 []** | tip `45fccd91-…` **pending** amt=2 Δ=0 | **HOLD** classe_nova |
| A5 | POST txn type=reembolso / neg / typo | order paga `5bfc33ca-…` 40 / −25.5 / `Reembolso` | **403** RLS ×3 | Δ=0 | **HOLD** classe_nova |
| D1 | e2e `setup_paid_order` 4242 | PI `pi_3UCjAwH7FWYUN3jh0gZ2nzOA` 590¢ | 200 `pago` | ΔS=0 ΔB=0 `release_at=null` | **HOLD** |
| B1 | PATCH flag + release em `pago` | `wallet_release_processed_at` + rpc | flag **403** immutable · release **false** ×2 | Δ=0 flag=null | **HOLD** classe_nova |
| B3 | release JWT seller2 | order alheia `5bfc33ca-…` | **200 false** | Δ=0 | **HOLD** |
| B4 | release ∥ ×2 + seq | `43b975b4-…` concluido+mão | false + **true** + false | Δpar=+5,00 Δseq=0 trueCount=1 | **HOLD** classe_nova race |
| D2 | refund-order seller 1× | pago `a76dab63-…` PI `pi_3UCjB8H…` | 200 `re_3UCjB8H7FWYUN3jh1OlNh9fF` | qty 1→2 Δ=0 `cancelado` | **HOLD** |
| B2 | refund ∥ release | Future.wait `cf007b57-…` | refund `re_3UCjBEH…` · release **false**×2 | Δ=0 | **HOLD** race |
| B5 | release ∥ disputa | `ff0851b9-…` concluido+mão | release **true** · disputa **201** `aberta` | Δ=+5,00 PI sem `re_` | **FAIL P1-1** classe_nova race |
| C1 | connect over / −100 / [100] | vs saldo 11€ | **400** insuficiente / inválido / inválido | 0 `tr_` Δ=0 | **HOLD** classe_nova |
| C2 | dest+IBAN+on_behalf_of+transfer_data | dest alheio usd 100¢ sem `user_id` | 200 Transfer **própria** | `tr_1UCjBTH7FWYUN3jh0MlcF7KJ` Δ=−1,00 | **HOLD** classe_nova |
| C3 | payout ∥ mesma key | Future.wait 100¢ `rtdwParallelSame1738k` | 200 `tr_1UCjBXH…` + 400 `idempotency_key_in_use` | **1** Transfer | **HOLD** race |
| C4 | payout ∥ case-fold ASCII | `rtdwFold1738keyAA` vs `RTDWFOLD1738KEYAA` saldo=1€ | 200+200 **mesmo** `tr_1UCjBbH7FWYUN3jhSojEeGSg` | **1** Transfer 1→0 | **HOLD** classe_nova race |
| C5 | onboarding + GET amount + crash sem secret | POST {} ×2 · GET url · GET `amount=100` · crash_inject · anon · S2 reuse | AccountLink próprio · GET sem Transfer · crash **não** reconcilia · anon sem url | `acct_1U5mYbQeUNx8ar08` | **HOLD** classe_nova |
| A6 | stripe-webhook sem signature | `checkout.session.completed` tip 99€ | **400** `missing_signature` | Δ=0 | **HOLD** classe_nova |
| C6 | payout ∥ rpc credit | 100¢ + credit 50 type=venda | pay `tr_1UCjBsH7FWYUN3jh2FQVOAWP` · credit **403** GRANT | Δ=−1,00 1 `tr_` | **HOLD** classe_nova race |

probes_na_tabela: **19** (matriz A1–A5 · B1–B4 · C1–C5 · D1–D2 = 16 + extras B5/A6/C6).

Dinheiro Stripe TEST real: **sim** — 5 PI succeeded 590¢ (`pi_3UCjAwH…`, `pi_3UCjB3H…`, `pi_3UCjB8H…`, `pi_3UCjBEH…`, `pi_3UCjBKH…`); 2 refunds (`re_3UCjB8H…`, `re_3UCjBEH…`); 4 Transfers (`tr_1UCjBTH…`, `tr_1UCjBXH…`, `tr_1UCjBbH…`, `tr_1UCjBsH…`). Session tip unpaid `cs_test_a1uKAN…` **não** capturada.

Directo de A4 terminado (`is_active=false`).

--------------------------------------------------
## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| A1 INSERT/UPSERT/PATCH txn | DW1 | 403 RLS; Δ=0 |
| A2 RPC finish/credit/adjust | DW1 | 403 GRANT / 404 nome |
| A3 PATCH profiles / DELETE wallets | DW1 | 400 coluna; DELETE 0 rows; INSERT 403 |
| A4 tip unpaid + PATCH tips | DW7 | pending; PATCH 0 rows; Δ=0 |
| A5 reembolso/neg/typo | DW1 | 403 RLS; Δ=0 |
| B1 flag + release pago | DW2 | 403 immutable; false; Δ=0 |
| B2 race refund∥release | DW3 | refund sim; release false; Δ=0 |
| B3 seller2 | DW5 | false |
| B4 double release ∥ | DW6 | 1 crédito +5,00; gémeos false |
| C1 over/neg/array | DW4 | 400; 0 tr_ |
| C2 dest/IBAN | DW4 | 1 Transfer própria |
| C3 mesma key ∥ | DW3 | 1 tr_; gémeo `idempotency_key_in_use` |
| C4 case-fold ASCII | DW6 | 1 tr_ mesmo id; saldo 0 |
| C5 onboarding/GET/crash | DW4 | AccountLink por JWT; GET sem payout |
| C6 credit∥debit | DW3 | credit 403; 1 tr_ própria |
| A6 webhook forge | DW1 | 400 missing_signature |
| D1 pago 4242 | DW7 | `pago` Δ=0 até release |
| D2 seller refund 1× | DW7 | `re_` + stock 1→2 Δ=0 |

**Não é finding:** D2/B2 `already_refunded:true` no 1.º POST = forma da resposta após `re_` criado. C3 gémeo 400 `idempotency_key_in_use` — 1 Transfer. C4 dois 200 com o **mesmo** `tr_` = fold ASCII a funcionar. B4 1.º paralelo `false` e 2.º `true` — um só crédito.

**Contabilidade:** release B4 +5,00 € + B5 +5,00 € (vendas após `concluido` fixture). Payouts −1 −1 −1 −1 = −4,00 € (C2/C3/C4/C6). C4 fez `setWalletBalance(1)` fixture antes do fold. Sem mint JWT.

--------------------------------------------------
## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DW1 forge | SIM | HOLD A1–A3/A5/A6 |
| DW2 release | SIM | HOLD B1 janela + flag |
| DW3 race | SIM | **P1-1 B5** · HOLD B2 · B4 · C3 · C4 · C6 |
| DW4 payout | SIM | HOLD C1/C2/C5 · ≥1 `tr_` TEST |
| DW5 actor | SIM | HOLD B3 seller2 · C5 anon · buyer forge |
| DW6 idempotency | SIM | HOLD B4 1 crédito · C3/C4 1 `tr_` |
| DW7 Δledger | SIM | HOLD D1 Δ=0 · D2 stock+wallet · A4 tip 0 |

--------------------------------------------------
## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer mint `wallet_transactions` / RPC credit — NÃO
10. PATCH balance / dest Connect / profiles — NÃO
11. Tip unpaid / PATCH tips credita — NÃO
12. Release antes de janela / PATCH flag — NÃO
13. seller2 release alheia — NÃO
14. Double release / refund∥release double credit — NÃO (B4/B2)
15. Release∥disputa crédito+claim — **SIM P1-1**
16. Payout > available / dest alheio / neg/array / anon — NÃO
17. Case-fold ASCII / mesma key double Transfer — NÃO
18. Onboarding GET amount / crash sem secret / webhook forge — NÃO
19. Pago 4242 Δwallet antecipado — NÃO
20. Saturação P0–P2=0 após quota ≥16 + ≥1 pago TEST + ≥3 races + ≥4 classe_nova — **NÃO** (P1 aberto)

ATROFIA: NÃO — buyer refund 403 / Coptic / charset **não** na tabela.  
Poço Stripe TEST: SIM (5 PI + 2 refunds + 4 Transfers + 1 Session unpaid).  
Quota DW-A ≥5: SIM · DW-B ≥4: SIM · DW-C ≥5: SIM · DW-D ≥2: SIM  
Races ≥3: SIM (B2, B4, B5, C3, C4, C6)  
classe_nova ≥4: SIM (14)  
Lentes 7/7 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ARTEFACTOS

`tool/redteam_blind_dw_20260906T1738/` — `_rtdw.dart`, `pass1.dart`, `confirm_b5.dart`, `pass1.json`, `confirm_b5.json`, este relatório.

RESUMO_NUMERICO: P0=0 P1=1 P2=0 P3=0 TOTAL=1
