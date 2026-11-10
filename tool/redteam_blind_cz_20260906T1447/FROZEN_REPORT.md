# FROZEN_REPORT — RED TEAM CEGO CZ

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: NÃO → quantos: 0
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 0

```
1. P0? NÃO
2. Quantos P0: 0
3. P1? NÃO
4. Quantos P1: 0
5. P2? NÃO
6. Quantos P2: 0
7. P3? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CZ_PAYOUT_POS_CPCU_v1
FROZEN_AT: 2026-09-06T14:55:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CZ1, CZ2, CZ3, CZ4, CZ5, CZ6]
probes_na_tabela: 19 (≥10)
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTCZ-20260906T1447
staging: fxdknzrqjenzqcvnwqqq
```

Exacto Coptic **não contado** (HOLD 400). Cherokee / emoji 💰 **não corridos**. Residual allowlist novo (Hangul, TAG U+E0061, `+`, soft-hyphen, type number) = **400**. ATROFIA: NÃO (1/19 ≠ ≥50%).

---

## Missão

Non-ASCII key → 400. `wd_<uuid>` OK. I/i → 1 Transfer. Bypass charset **novo** (não só Coptic exacto)?

**Resposta:** **Não.** Hangul / Coptic residual / café / ZWSP / bidi / TAG U+E0061 / `+` / `%` / type number / soft-hyphen → **400**, 0 `tr_` no gémeo hostil, Δ=0. Par **I vs i** → **1** Transfer `tr_1UCgWEH7FWYUN3jhaFd85Bz1`. Canónica `wd_<uuid>_100_<ms>` → `tr_1UCgWJH7FWYUN3jhLSLxEMYW`; retry **idempotent**, 0 `tr_` novos. Fullwidth １ (U+FF11) NFKC→1 → **1** Transfer (mesmo hash que ASCII). Ligadura ﬁ (U+FB01) NFKC→fi → **1** Transfer. Destination alheio ignorado (Transfer própria). Buyer refund **403**. Race refund∥release: refund sim, release false, Δ=0. **Mint não.**

---

## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

---

## TABELA DE PROVAS

| probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD\|FAIL\|SKIP |
|----------|------------|------|------------------|-----------|------------------|
| CZ-A1-HANGUL | Hangul 한 U+D55C (script novo) | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A1-COPTIC | Coptic ⲟ U+2C9F (1 linha; exacto CT) | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A2-LATIN-ACCENT | `wd_caféCz047x` | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A2-FW-DIGIT | `rtczFw1Allowx` vs １ U+FF11 | 200+200 idempotent | **1** `tr_1UCgVtH7FWYUN3jhYOoXNaXc` | Δ=−1,00 | HOLD |
| CZ-A3-ZWSP | ZWSP U+200B no meio | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A3-BIDI | RLO U+202E no meio | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A3-TAG | TAG LATIN SMALL A U+E0061 | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A4-PLUS | `+` na key ASCII | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A4-PERCENT | `%` na key | 400 inválida | 0 | Δ=0 | HOLD |
| CZ-A5-SOFT-HYPHEN | ASCII vs U+00AD no meio | 200 + **400** gémeo | **1** `tr_1UCgW4H7FWYUN3jhY9L3gZfU` (só ASCII) | Δ=−1,00 | HOLD |
| CZ-A6-LIGATURE | `fi` vs ﬁ U+FB01 | 200+200 idempotent | **1** `tr_1UCgW8H7FWYUN3jh3tmua1Qb` | Δ=−1,00 | HOLD |
| CZ-A8-TYPE-NUM | `idempotency_key`: 12345678 | 400 em falta | 0 | Δ=0 | HOLD |
| CZ-B1-CASE-Ii | `RTCZCASEIKEY9` vs `rtczcaseikey9` | 200+200 idempotent | **1** `tr_1UCgWEH7FWYUN3jhaFd85Bz1` | Δ=−1,00 | HOLD |
| CZ-B2-WD-UUID | `wd_<sellerUuid>_100_<ms>` | 200 success | **1** `tr_1UCgWJH7FWYUN3jhLSLxEMYW` | Δ=−1,00 | HOLD |
| CZ-B3-WD-RETRY | retry mesma `wd_<uuid>` B2 | 200 `idempotent:true` | **0** novos (mesmo `tr_1UCgWJ…`) | Δ=0 | HOLD |
| CZ-C1-DEST | dest=`acct_1UB7nWHKe5ETfHI5` currency=usd | 200 | **1** própria `tr_1UCgWPH7FWYUN3jhGVvF3iK7` | 56→50 fim p1 | HOLD |
| CZ-C1b-OVERBAL | amount=99999999 vs saldo 50 | 400 insuficiente | 0 | Δ=0 | HOLD |
| CZ-C2-BUYER-REFUND | refund-order JWT comprador `4900bf9f-…` | **403** Sem permissão | 0 | Δseller=0 | HOLD |
| CZ-C3-REL-REFUND-RACE | refund∥release no pago `97428d56-…` | refund 200 `re_3UCgWp…` 590¢; release false | 0 payout tr_ | Δ=0 | HOLD |

probes_na_tabela: **19** (A1 Coptic HOLD exacto na tabela, **não** na contagem de findings).

Transfer Stripe TEST real: **sim** (`tr_1UCgVtH…`, `tr_1UCgW4H…`, `tr_1UCgW8H…`, `tr_1UCgWEH…`, `tr_1UCgWJH…`, `tr_1UCgWPH…`).

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Coptic ⲟ exacto CT | CZ1 | 400; 0 tr_ — **não contar** (anti-atrofia Coptic) |
| Hangul 한 / TAG U+E0061 / `+` / `%` / café / ZWSP / bidi / type number | CZ1 | 400; 0 tr_ |
| soft-hyphen U+00AD | CZ1 | 400 no gémeo; ASCII cria 1 tr_ (não duplica) |
| I vs i ASCII | CZ2 | 1 Transfer `toLowerCase` |
| `wd_<uuid>` + retry | CZ3/CZ4 | 1 Transfer; retry idempotente |
| fullwidth １ NFKC→1 | CZ1 | 1 Transfer (allowlist no ASCII pós-NFKC; não duplica) |
| ligadura ﬁ NFKC→fi | CZ1 | 1 Transfer (não duplica) |
| dest/currency body | CZ4 | Transfer própria `acct_1U5mYbQeUNx8ar08` |
| payout > saldo | CZ6 | 400 Δ=0 |
| buyer refund | CZ5 | **403** seller-only **não abriu** |
| refund∥release pago | CZ5 | refund 590¢ da linha; release false; Δ=0 |

**Não é finding:** actor do exploit = JWT. Destination alheio no body não entra no Transfer.

**Contabilidade:** wallet seller 56,00 → 50,00 = **−6,00 €** = 6 Transfers de 100 cêntimos (A2-FW + A5 ASCII + A6 + B1 + B2 + C1). Sem mint. Pass2 refund Stripe 590¢ (pago); Δ wallet 0. Saldo final **50,00 €** coerente.

---

## Lentes 6/6

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CZ1 charset 400 | SIM | HOLD A*; Hangul/TAG/`+`/shy 400; FW digit + ligadura NFKC 1 tr_ (não 2) |
| CZ2 I/i | SIM | HOLD 1 Transfer |
| CZ3 wd_uuid | SIM | HOLD Transfer OK |
| CZ4 Transfer | SIM | HOLD dest própria; retry 0 novos; ≥1 tr_ TEST |
| CZ5 refund actor | SIM | HOLD buyer 403; race sem crédito+refund |
| CZ6 Δwallet | SIM | payouts próprios −6 €; sem mint |

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
9. Bypass allowlist charset novo (Hangul/TAG/`+`/shy/type → Transfer distinta) — NÃO
10. I vs i → 2 Transfers — NÃO
11. `wd_<uuid>` recusada — NÃO
12. Retry `wd_<uuid>` duplica Transfer — NÃO
13. Destination alheio — NÃO
14. payout > saldo / mint — NÃO
15. Buyer refund seller-only aberto — NÃO (403)
16. Release+refund cria dinheiro líquido — NÃO
17. Cross-user financeiro — NÃO
18. Saturação P0–P2 = 0 após quota ≥10 + ≥1 Transfer TEST — SIM

ATROFIA (só exacto Coptic): NÃO — 1/19  
Poço Stripe TEST: SIM (6 Transfers Connect + 2 PI succeeded + 1 refund)  
Quota CZ-A ≥4: SIM · CZ-B ≥3: SIM · CZ-C ≥3: SIM  
Lentes 6/6 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

---

## ARTEFACTOS

`tool/redteam_blind_cz_20260906T1447/` — `_rtcz.dart`, `pass1.dart`, `pass2.dart`, `pass1.json`, `pass2.json`, este relatório.
