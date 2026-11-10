# FROZEN_REPORT — RED TEAM CEGO DF

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
AUDITOR: REDTEAM_BLIND_DF_PAYOUT_POS_CVDA_v1
FROZEN_AT: 2026-09-06T15:45:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [DF1, DF2, DF3, DF4, DF5, DF6]
probes_na_tabela: 29 (≥10)
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTDF-20260906T1538
staging: fxdknzrqjenzqcvnwqqq
```

Exacto café NFC **não contado** (HOLD 400). Coptic / emoji 💰 **não corridos**. Residual allowlist novo (Arabic, NFD combining, Kelvin, math bold, circled, ZWNJ/WJ/LRM, TAB/CR/`.`, Turkish İ, dotless ı, type array/null) = **400** ou **1** `tr_` NFKC. BOM prefixo/sufixo = **1** hash (trim U+FEFF), meio **400**. ATROFIA: NÃO (1/29 ≠ ≥50%).

---

## Missão

Non-ASCII key → 400. `wd_<uuid>` OK. I/i → 1 Transfer. Bypass charset **novo** (não Coptic / 💰 / café NFC exacto CZ)?

**Resposta:** **Não.** Arabic / café NFC / NFD combining / ZWNJ / WJ / LRM / TAB / CR / `.` / Turkish İ / dotless ı / type array/null → **400**, 0 `tr_` no gémeo hostil, Δ=0. Pares NFKC (fullwidth hyphen, math bold 𝐚, Kelvin K, circled ①) → **1** Transfer cada. BOM U+FEFF prefixo/sufixo → **1** Transfer (mesmo hash que ASCII); BOM no meio → **400**. Par **I vs i** → **1** Transfer `tr_1UChHeH7FWYUN3jhnQEIgXLv`. Canónica `wd_<uuid>_100_<ms>` → `tr_1UChHjH7FWYUN3jhWYPNfKCU`; retry **idempotent**, 0 `tr_` novos. Header `Idempotency-Key` não duplicou. Destination alheio ignorado (Transfer própria). Buyer refund **403**. Race refund∥release: refund sim, release false, Δ=0. **Mint não.**

---

## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

`pass1.json` marcou `DF-A3-BOM` FAIL no primeiro POST (BOM prefixo → 200 + 1 `tr_`). Confirmação `confirm_bom.dart`: prefixo e sufixo **colidem** com ASCII (`n_tr=1`, `idempotent:true`); BOM no meio → 400. Reclassificado **HOLD** (trim/canónico, igual a fullwidth NFKC) — **não contar**.

---

## TABELA DE PROVAS

| probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD\|FAIL\|SKIP |
|----------|------------|------|------------------|-----------|------------------|
| DF-A1-ARABIC | Arabic Yeh ي U+064A | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A1-CAFE-CTRL | `wd_caféDf047x` NFC (exacto CZ; não contar) | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A2-FW-HYPHEN | `-` vs － U+FF0D | 200+200 idempotent | **1** `tr_1UChGxH7FWYUN3jhjTSCTCwB` | Δ=−1,00 | HOLD |
| DF-A2-MATH-BOLD | `a` vs 𝐚 U+1D41A | 200+200 idempotent | **1** `tr_1UChH2H7FWYUN3jh8YpfOnr8` | Δ=−1,00 | HOLD |
| DF-A2-NFD-ACUTE | `rtdfcafeNfd1` vs e+U+0301 | 200 + **400** gémeo | **1** `tr_1UChH7H7FWYUN3jhRTRDkj1B` (só ASCII) | Δ=−1,00 | HOLD |
| DF-A2-KELVIN | `K` vs K U+212A | 200+200 idempotent | **1** `tr_1UChHCH7FWYUN3jhhqBThSur` | Δ=−1,00 | HOLD |
| DF-A2-CIRCLED | `1` vs ① U+2460 | 200+200 idempotent | **1** `tr_1UChHGH7FWYUN3jhiWpH8mZY` | Δ=−1,00 | HOLD |
| DF-A3-ZWNJ | ZWNJ U+200C no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A3-WJ | Word Joiner U+2060 no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A3-LRM | bidi LRM U+200E no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A3-BOM | BOM U+FEFF prefixo (1.º POST) | 200 success | **1** `tr_1UChHPH7FWYUN3jhp9E9s0VQ` | Δ=−1,00 | HOLD |
| DF-A3-BOM-PREFIX-PAIR | ASCII vs BOM+ASCII | 200+200 idempotent | **1** `tr_1UChIWH7FWYUN3jhNHal9uWw` | Δ=−1,00 | HOLD |
| DF-A3-BOM-SUFFIX-PAIR | ASCII vs ASCII+BOM | 200+200 idempotent | **1** `tr_1UChIbH7FWYUN3jhlCmiggWS` | Δ=−1,00 | HOLD |
| DF-A3-BOM-MIDDLE | BOM U+FEFF no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A4-TAB | TAB U+0009 no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A4-CR | CR U+000D no meio | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A4-DOT | `.` ASCII na key | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A5-TURKISH-I | İ U+0130 | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A5-DOTLESS-I | ı U+0131 | 400 inválida | 0 | Δ=0 | HOLD |
| DF-A8-TYPE-ARR | `idempotency_key`: array | 400 em falta | 0 | Δ=0 | HOLD |
| DF-A8-TYPE-NULL | `idempotency_key`: null | 400 em falta | 0 | Δ=0 | HOLD |
| DF-A9-HEADER | body + header `Idempotency-Key` | 200 | **1** `tr_1UChHaH7FWYUN3jhKwkzN8L7` | Δ=−1,00 | HOLD |
| DF-B1-CASE-Ii | `RTDFCASEIKEY9` vs `rtdfcaseikey9` | 200+200 idempotent | **1** `tr_1UChHeH7FWYUN3jhnQEIgXLv` | Δ=−1,00 | HOLD |
| DF-B2-WD-UUID | `wd_<sellerUuid>_100_<ms>` | 200 success | **1** `tr_1UChHjH7FWYUN3jhWYPNfKCU` | Δ=−1,00 | HOLD |
| DF-B3-WD-RETRY | retry mesma `wd_<uuid>` B2 | 200 `idempotent:true` | **0** novos (mesmo `tr_1UChHj…`) | Δ=0 | HOLD |
| DF-C1-DEST | dest=`acct_1UB7nWHKe5ETfHI5` currency=usd | 200 | **1** própria `tr_1UChHpH7FWYUN3jhl4Vc57mx` | 49→39 fim p1 | HOLD |
| DF-C1b-OVERBAL | amount=99999999 vs saldo 39 | 400 insuficiente | 0 | Δ=0 | HOLD |
| DF-C2-BUYER-REFUND | refund-order JWT comprador `87f9640c-…` | **403** Sem permissão | 0 | Δseller=0 | HOLD |
| DF-C3-REL-REFUND-RACE | refund∥release no pago `75085c2b-…` | refund 200 `re_3UChIv…` 590¢; release false | 0 payout tr_ | Δ=0 | HOLD |

probes_na_tabela: **29** (A1 café HOLD exacto na tabela, **não** na contagem de findings).

Transfer Stripe TEST real: **sim** (`tr_1UChGxH…`, `tr_1UChH2H…`, `tr_1UChH7H…`, `tr_1UChHCH…`, `tr_1UChHGH…`, `tr_1UChHPH…`, `tr_1UChHaH…`, `tr_1UChHeH…`, `tr_1UChHjH…`, `tr_1UChHpH…`, `tr_1UChIWH…`, `tr_1UChIbH…`).

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| café NFC exacto CZ | DF1 | 400; 0 tr_ — **não contar** (anti-atrofia café) |
| Arabic / NFD combining / ZWNJ / WJ / LRM / TAB / CR / `.` / İ / ı / type array/null | DF1 | 400; 0 tr_ |
| fullwidth hyphen / math bold / Kelvin / circled | DF1 | 1 Transfer (allowlist no ASCII pós-NFKC; não duplica) |
| BOM U+FEFF prefixo/sufixo | DF1 | 1 Transfer (trim; par ASCII idempotent); meio 400 |
| I vs i ASCII | DF2 | 1 Transfer `toLowerCase` |
| `wd_<uuid>` + retry | DF3/DF4 | 1 Transfer; retry idempotente |
| header `Idempotency-Key` | DF1/DF4 | 1 Transfer do body; header não duplicou |
| dest/currency body | DF4 | Transfer própria `acct_1U5mYbQeUNx8ar08` |
| payout > saldo | DF6 | 400 Δ=0 |
| buyer refund | DF5 | **403** seller-only **não abriu** |
| refund∥release pago | DF5 | refund 590¢ da linha; release false; Δ=0 |

**Não é finding:** actor do exploit = JWT. Destination alheio no body não entra no Transfer. BOM aceite nas pontas = canónico, não 2.º payout.

**Contabilidade:** wallet seller 49,00 → 37,00 = **−12,00 €** = 12 Transfers de 100 cêntimos (5 NFKC pares + BOM 1.º + header + B1 + B2 + C1 + 2 BOM confirm). Sem mint. Pass2 refund Stripe 590¢ (pago); Δ wallet 0. Saldo final **37,00 €** coerente.

---

## Lentes 6/6

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| DF1 charset 400 | SIM | HOLD A*; residual novo 400; NFKC compatibility 1 tr_ (não 2); BOM trim 1 tr_ |
| DF2 I/i | SIM | HOLD 1 Transfer |
| DF3 wd_uuid | SIM | HOLD Transfer OK |
| DF4 Transfer | SIM | HOLD dest própria; retry 0 novos; ≥1 tr_ TEST |
| DF5 refund actor | SIM | HOLD buyer 403; race sem crédito+refund |
| DF6 Δwallet | SIM | payouts próprios −12 €; sem mint |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — NÃO
6. Quantos P2: 0
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Bypass allowlist charset novo (Arabic/NFD/Kelvin/math/ZWNJ/BOM-meio/İ → Transfer distinta) — NÃO
10. I vs i → 2 Transfers — NÃO
11. `wd_<uuid>` recusada — NÃO
12. Retry `wd_<uuid>` duplica Transfer — NÃO
13. Destination alheio — NÃO
14. payout > saldo / mint — NÃO
15. Buyer refund seller-only aberto — NÃO (403)
16. Release+refund cria dinheiro líquido — NÃO
17. Cross-user financeiro — NÃO
18. Saturação P0–P2 = 0 após quota ≥10 + ≥1 Transfer TEST — SIM

ATROFIA (só exacto café): NÃO — 1/29  
Poço Stripe TEST: SIM (12 Transfers Connect + 2 PI succeeded + 1 refund)  
Quota DF-A ≥4: SIM · DF-B ≥3: SIM · DF-C ≥3: SIM  
Lentes 6/6 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

---

## ARTEFACTOS

`tool/redteam_blind_df_20260906T1538/` — `_rtdf.dart`, `pass1.dart`, `pass2.dart`, `confirm_bom.dart`, `pass1.json`, `pass2.json`, `confirm_bom.json`, este relatório.
