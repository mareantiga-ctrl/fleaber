# FROZEN_REPORT — RED TEAM CEGO EC · Wallet / release / disputa / payout / Connect · POS_DTDY

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
AUDITOR: REDTEAM_BLIND_EC_WALLET_POS_DTDY_v1
probes_na_tabela: 22 · classes_novas: 19 · races: 7
VEREDICTO: PASS_CEGO_SATURADO
```

```
FROZEN_AT: 2026-09-06T18:32:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [EC1, EC2, EC3, EC4, EC5, EC6, EC7]
prefix: RTEC-20260906T1822
staging: fxdknzrqjenzqcvnwqqq
```

buyer `refund-order` 403 · Coptic payout key · charset 400 = **não corridos** (HOLD anti-atrofia). B3 clássico 0ms só 1 efeito = **1 linha reteste**. Residual 1/22 = 5% ≪ 40%. **Não** ATROFIA_ABORT.

--------------------------------------------------
## Missão

`Future.wait` release∥disputa: **não** (crédito líquido **e** disputa aberta). Um dos dois ganha; se o release já creditou, disputa negada **ou** clawback. Buyer nunca mint/force release/payout.

**Resposta:** **Fechou o P1-1 do DW.** Oráculo `net>0 ∧ disputa aberta` = **falso** em 0ms, 50ms e na corrida a 3. Em paralelo com payout (A8) o release devolveu `true` e a disputa `201 aberta`, mas o cadeado DTDY fez **clawback** `estorno` 5,00 € (`eeab770a-…`) contra a `venda` 5,00 € (`965836b8-…`): **net=0**, `wallet_release_processed_at=null`, levantamento Connect **400** insuficiente. Em 0ms/50ms o release ganhou e a disputa caiu **403 RLS** (`wallet_release_processed_at` já preenchido) — 1 efeito, crédito sem claim. Sequencial (A7): disputa **negada** depois do crédito. Resto da matriz HOLD: INSERT estorno/ledger **403 RLS**; clawback/credit/debit JWT **403 GRANT**; PATCH wallets dest/balance **200 []**; tip unpaid Δ=0; type typo/neg **403**; release em pago **false**; seller2 release false + disputa 403; double release **1** crédito; refund∥release Δ=0 `re_`; smuggle recusada não creditou (disputa ficou `aberta`, Δ=0); refund pós-release **403** shipped; over/dest **400**; payout∥ **1** `tr_` (dois 200, mesmo id); seller2 `user_id` S1 **400**. **Mint JWT não.**

--------------------------------------------------
## Findings abertos

Nenhum. P0=0 P1=0 P2=0 P3=0.

**Prova do fecho DW (não é finding):** A8 order `e07fcff6-6e2f-408f-bd17-930942bc286b` PI `pi_3UCjsFH7FWYUN3jh1piXKEoS` · disputa `16388d5f-d10f-4fdb-8319-1c401d55612d` `aberta` · txn venda `965836b8-…` +5,00 · txn estorno `eeab770a-…` +5,00 (clawback) · net 0 · `confirm_a8.json`.

--------------------------------------------------
## TABELA DE PROVAS (22)

| probe_id | edge/rpc | payload | HTTP | Stripe/BD Δ | HOLD\|FAIL\|SKIP |
|----------|----------|---------|------|-------------|------------------|
| A1 | POST txn estorno + ledger + PATCH wallets.balance | poison 999 · tr_fake · bal 8888 JWT | **403** RLS ×2; PATCH **200 []** | ΔB=0 ΔS=0 | **HOLD** classe_nova |
| A2 | rpc clawback_dispute / clawback_order / payout_debit / credit | fakeOid · debit 100¢ · credit 40 | **403 GRANT** ×4 | ΔS=0 | **HOLD** classe_nova |
| A3 | PATCH wallets.stripe_account_id + profiles | dest alheio `acct_1UChok…` | wallets **200 []**; profiles 400 coluna | acct próprio `acct_1U5mYb…` | **HOLD** classe_nova |
| A4 | tip-checkout unpaid + GET settle | live `43897088-…` 2€ | 200 Session `cs_test_a1CWlU…`; GET sem sid parse | tip unpaid Δ=0 | **HOLD** classe_nova |
| A5 | POST txn Estorno/venda neg/reembolso | −25.5 / −12 / +80 | **403** RLS ×3 | Δ=0 | **HOLD** classe_nova |
| D1a | e2e `setup_paid_order` 4242 | PI `pi_3UCjrkH7FWYUN3jh0UQpBx94` | 200 `pago` | Δ=0 até release | **HOLD** |
| B1 | release cedo em `pago` | buyer+seller rpc | **200 false** ×2 | Δ=0 | **HOLD** classe_nova |
| B4 | seller2 release + disputa alheia | order `59d92ae6-…` | rel **false** · disp **403 RLS** | Δ=0 | **HOLD** classe_nova |
| D1 | pago 4242 + release legítimo | concluido+mão `59d92ae6-…` | **200 true** | **Δ=+5,00** txn `ab007fdd-…` | **HOLD** |
| D3 | refund após release | seller+buyer | S **403** shipped · B **403** perm | Δ=0 sem `re_` | **HOLD** classe_nova |
| B5 | double release ∥ ×2 + seq | `818733e3-…` | true + false + false | Δpar=+5,00 Δseq=0 trueCount=1 | **HOLD** classe_nova race |
| B2 | refund ∥ release | `df94f627-…` | `re_3UCjrvH…` · release **false** | Δ=0 | **HOLD** classe_nova race |
| B3 | release ∥ disputa **0ms** | `cc88bd28-…` | rel **true** · disp **403 RLS** | Δ=+5,00 open_n=0 both=false | **HOLD** reteste 1 efeito |
| B3b | release ∥ disputa **50ms** | `f35649a9-…` | rel **true** · disp **403 RLS** | Δ=+5,00 open_n=0 both=false | **HOLD** classe_nova race |
| D2 | oráculo pós-B3 | 0ms+50ms | both0=false both50=false | 1 crédito/order; sem open | **HOLD** classe_nova |
| A6 | INSERT recusada → release → PATCH aberta | `55a5d7c3-…` disp `4c9801fa-…` | ins **201** · rel **false** · patch 200 | net=0 open=`aberta` both=false | **HOLD** classe_nova |
| A7 | release seq → disputa → PATCH recusada → 2.º release | `b8dbec69-…` | rel1 **true** · disp **403** · rel2 **false** | Δrel2=0; disputa **negada** | **HOLD** classe_nova |
| A8 | release ∥ disputa ∥ payout 5€ | `e07fcff6-…` saldo 0,50 | rel **true** · disp **201** · pay **400** | venda 5 + estorno 5 **net=0** 0 `tr_` | **HOLD** classe_nova race |
| A9 | payout ∥ clawback JWT | 100¢ + rpc clawback | pay `tr_1UCjsMH…` · claw **403 GRANT** | Δ=−1,00 1 `tr_` | **HOLD** classe_nova race |
| C1 | overbalance + dest `user_id` S2 | 99999999 · dest alheio 100¢ | **400** insuficiente / another user | 0 `tr_` Δ=0 | **HOLD** classe_nova |
| C2 | payout ∥ mesma key | `rtecParallelSame1822k` | 200+200 **mesmo** `tr_1UCjsSH…` | **1** Transfer Δ=−1,00 | **HOLD** classe_nova race |
| C3 | Connect seller2 hostil | S2 onb + payout `user_id` S1 | onb AccountLink próprio · pay **400** | S1 bal intacto | **HOLD** classe_nova |

probes_na_tabela: **22** (matriz A1–A5 · B1–B5 · C1–C3 · D1–D3 = 16 + D1a/B3b/A6–A9).

Dinheiro Stripe TEST real: **sim** — 8 PI succeeded 590¢ (`pi_3UCjrkH…`, `pi_3UCjrrH…`, `pi_3UCjrvH…`, `pi_3UCjs1H…`, `pi_3UCjs4H…`, `pi_3UCjs7H…`, `pi_3UCjsBH…`, `pi_3UCjsFH…`); 1 refund (`re_3UCjrvH7FWYUN3jh1ftkPXL8`); 2 Transfers (`tr_1UCjsMH7FWYUN3jh7gGGwG1w`, `tr_1UCjsSH7FWYUN3jhByRO8Klp`). Session tip unpaid `cs_test_a1CWlU…` **não** capturada.

Directo de A4 terminado (`is_active=false`).

--------------------------------------------------
## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| A1 estorno/ledger/PATCH bal | EC1 | 403 RLS; 200 [] Δ=0 |
| A2 clawback/credit/debit JWT | EC1 | 403 GRANT |
| A3 PATCH dest wallets | EC1 | 0 rows; acct próprio |
| A4 tip unpaid | EC7 | pending Session; Δ=0 |
| A5 typo/neg/reembolso | EC1 | 403 RLS |
| B1 release pago | EC2 | false Δ=0 |
| B2 race refund∥release | EC3 | `re_` + release false Δ=0 |
| B3 0ms clássico | EC3 | 1 efeito (crédito; disputa 403) |
| B3b 50ms | EC3 | 1 efeito (crédito; disputa 403) |
| B4 seller2 | EC6 | false + 403 |
| B5 double release | EC2 | 1 crédito +5,00 |
| C1 over/dest | EC4 | 400; 0 tr_ |
| C2 mesma key ∥ | EC4 | 1 tr_ dois 200 mesmo id |
| C3 seller2 Connect | EC6 | payout S1 400 |
| A6 smuggle recusada | EC3 | Δ=0; disputa aberta (release false) |
| A7 seq após crédito | EC5 | disputa 403 (negada); 2.º release false |
| A8 triple + clawback | EC4 | net=0; 0 tr_; disputa aberta |
| A9 credit∥debit | EC3 | clawback 403; 1 tr_ própria |
| D1 pago+release | EC7 | Δ=+5,00 só após concluido |
| D1a pago | EC7 | Δ=0 em `pago` |
| D2 pós-B3 | EC7 | sem both / sem double |
| D3 refund pós-release | EC5 | 403 shipped Δ=0 |

**Não é finding:** D3 buyer 403 «Sem permissão» é o HOLD anti-atrofia (não linha extra). C2 dois 200 com o **mesmo** `tr_` = idempotency. A6 INSERT com `status=recusada` ficou `aberta` (coluna/default) — o release viu disputa e recusou; não houve crédito+claim. A8 `release=true` **e** `disputa=201` **com** clawback: missão cumprida (não crédito líquido + claim).

**Contabilidade:** releases D1/B5/B3/B3b/A7 +5 cada; A8 +5 venda −5 estorno = 0; A6 0. Payouts A9 −1 + C2 −1. Sem mint JWT.

--------------------------------------------------
## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| EC1 forge | SIM | HOLD A1–A5 |
| EC2 release | SIM | HOLD B1 · B5 |
| EC3 disputa race | SIM | HOLD B3 · B3b · A6 · A8 (clawback) |
| EC4 payout | SIM | HOLD C1/C2/C3/A8 · ≥1 `tr_` TEST |
| EC5 clawback | SIM | HOLD A7 disputa negada · A8 estorno · D3 deny |
| EC6 actor | SIM | HOLD B4 seller2 · C3 S2 |
| EC7 caixa | SIM | HOLD D1 Δ=+5,00 · D1a/D2 · A4 tip 0 |

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
10. PATCH balance / dest Connect / profiles — NÃO
11. Tip unpaid / GET settle credita — NÃO
12. Release antes de janela — NÃO
13. seller2 release/disputa alheia — NÃO
14. Double release / refund∥release double credit — NÃO (B5/B2)
15. Release∥disputa crédito líquido+claim — **NÃO** (B3 1 efeito; A8 clawback net=0)
16. Payout > available / dest alheio / seller2 — NÃO
17. Mesma key double Transfer — NÃO
18. Clawback JWT / estorno poison — NÃO
19. Pago 4242 Δwallet antecipado — NÃO
20. Saturação P0–P2=0 após quota ≥16 + ≥1 pago TEST + ≥3 races + ≥4 classe_nova — **SIM**

ATROFIA: NÃO — buyer refund 403 / Coptic / charset **não** na tabela; B3 clássico = 1/22.  
Poço Stripe TEST: SIM (8 PI + 1 refund + 2 Transfers + 1 Session unpaid).  
Quota EC-A ≥5: SIM · EC-B ≥5: SIM · EC-C ≥3: SIM · EC-D ≥3: SIM  
Races ≥3: SIM (B2, B3, B3b, B5, A8, A9, C2)  
classe_nova ≥4: SIM (19)  
Lentes 7/7 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ARTEFACTOS

`tool/redteam_blind_ec_20260906T1822/` — `_rtec.dart`, `pass1.dart`, `confirm_a8.dart`, `pass1.json`, `confirm_a8.json`, este relatório.

RESUMO_NUMERICO: P0=0 P1=0 P2=0 P3=0 TOTAL=0
