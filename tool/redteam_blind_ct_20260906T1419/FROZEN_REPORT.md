# FROZEN_REPORT — RED TEAM CEGO CT

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
AUDITOR: REDTEAM_BLIND_CT_PAYOUT_POS_ALLOW_v1
FROZEN_AT: 2026-09-06T14:20:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CT1, CT2, CT3, CT4, CT5, CT6]
probes_na_tabela: 17 (≥10)
VEREDICTO: PASS_CEGO_SATURADO
prefix: RTCT-20260906T1419
staging: fxdknzrqjenzqcvnwqqq
```

Exacto Coptic **não contado** (HOLD 400). Residual allowlist = **1** (A1). ATROFIA: NÃO (1/17 ≠ ≥50%).

---

## Missão

Key non-ASCII → 400 (allowlist charset). I vs i (ASCII) → 1 Transfer. Key legítima `wd_<uuid>` → funciona. Bypass da allowlist charset?

**Resposta:** **Não.** Coptic/emoji/cirílico/acento/ZWSP/bidi/`%`/espaço/newline → **400**, 0 `tr_`, Δ=0. Par **I vs i** → **1** Transfer `tr_1UCfwMH7FWYUN3jhzxNcheqk`. Canónica `wd_<uuid>_100_<ms>` → `tr_1UCfwRH7FWYUN3jhSdbpUFO5`; retry **idempotent**, 0 `tr_` novos. Fullwidth ｏ (U+FF4F) NFKC→o → **1** Transfer (mesmo hash que ASCII; não é 2.º payout). Destination alheio ignorado (Transfer própria). Buyer refund **403**. Race refund∥release: refund sim, release false, Δ=0. **Mint não.**

---

## Findings abertos

Nenhum. TOTAL P0–P3 = 0.

---

## TABELA DE PROVAS

| probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD\|FAIL\|SKIP |
|----------|------------|------|------------------|-----------|------------------|
| CT-A1-COPTIC | Coptic ⲟ U+2C9F (1 linha; exacto CN) | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A1b-EMOJI | ASCII+💰 U+1F4B0 | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A1c-CYRILLIC | cirílico е U+0435 | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A2-LATIN-ACCENT | `wd_caféAllow04` | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A3-ZWSP | ZWSP U+200B no meio | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A3b-BIDI | RLO U+202E no meio | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A4-PERCENT | `%` na key | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A4-SPACE | espaço na key | 400 inválida | 0 | Δ=0 | HOLD |
| CT-A4-NEWLINE | newline na key | 400 inválida | 0 | Δ=0 | HOLD |
| CT-B1-CASE-Ii | `RTCTCASEIKEY9` vs `rtctcaseikey9` | 200+200 idempotent | **1** `tr_1UCfwMH7FWYUN3jhzxNcheqk` | Δ=−1,00 | HOLD |
| CT-B2-WD-UUID | `wd_<sellerUuid>_100_<ms>` | 200 success | **1** `tr_1UCfwRH7FWYUN3jhSdbpUFO5` | Δ=−1,00 | HOLD |
| CT-B3-WD-RETRY | retry mesma `wd_<uuid>` B2 | 200 `idempotent:true` | **0** novos (mesmo `tr_1UCfwRH…`) | Δ=0 | HOLD |
| CT-A7-FULLWIDTH-NFKC | `rtctoFwAllow1` vs `rtctｏFwAllow1` U+FF4F | 200+200 | **1** `tr_1UCfwXH7FWYUN3jhWyJs1JU1` | Δ=−1,00 | HOLD |
| CT-C1-DEST | dest=`acct_1UB7nWHKe5ETfHI5` currency=usd | 200 | **1** própria `tr_1UCfwbH7FWYUN3jh88oBkZU4` | 61→57 fim p1 | HOLD |
| CT-C1b-OVERBAL | amount=99999999 vs saldo 57 | 400 insuficiente | 0 | Δ=0 | HOLD |
| CT-C2-BUYER-REFUND | refund-order JWT comprador `4a9b0a8e-…` | **403** Sem permissão | 0 | Δseller=0 | HOLD |
| CT-C3-REL-REFUND-RACE | refund∥release no pago `f52f009f-…` | refund 200 `re_3UCfww…` 590¢; release false | 0 payout tr_ | Δ=0 | HOLD |

probes_na_tabela: **17** (A1 Coptic HOLD exacto na tabela, **não** na contagem de findings).

Transfer Stripe TEST real: **sim** (`tr_1UCfwMH…`, `tr_1UCfwRH…`, `tr_1UCfwXH…`, `tr_1UCfwbH…`).

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Coptic ⲟ exacto CN | CT1 | 400; 0 tr_ — **não contar** (anti-atrofia Coptic) |
| emoji / cirílico / café / ZWSP / bidi / `%` / espaço / newline | CT1 | 400; 0 tr_ |
| I vs i ASCII | CT2 | 1 Transfer `toLowerCase` |
| `wd_<uuid>` + retry | CT3/CT4 | 1 Transfer; retry idempotente |
| fullwidth ｏ NFKC→o | CT1 | 1 Transfer (allowlist no ASCII pós-NFKC; não duplica) |
| dest/currency body | CT4 | Transfer própria `acct_1U5mYbQeUNx8ar08` |
| payout > saldo | CT6 | 400 Δ=0 |
| buyer refund | CT5 | **403** seller-only **não abriu** |
| refund∥release pago | CT5 | refund 590¢ da linha; release false; Δ=0 |

**Não é finding:** `service_role` a garantir saldo ≥25 (já estava 61). Actor do exploit = JWT.

**Contabilidade:** wallet seller 61,00 → 57,00 = **−4,00 €** = 4 Transfers de 100 cêntimos (B1 + B2 + A7 + C1). Sem mint. Pass2 refund Stripe 590¢ (unshipped); Δ wallet 0. Saldo final **57,00 €** coerente.

---

## Lentes 6/6

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CT1 charset 400 | SIM | HOLD A*; fullwidth NFKC 1 tr_ (não 2) |
| CT2 I/i | SIM | HOLD 1 Transfer |
| CT3 wd_uuid | SIM | HOLD Transfer OK |
| CT4 Transfer | SIM | HOLD dest própria; retry 0 novos; ≥1 tr_ TEST |
| CT5 refund actor | SIM | HOLD buyer 403; race sem crédito+refund |
| CT6 Δwallet | SIM | payouts próprios −4 €; sem mint |

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
9. Bypass allowlist charset (non-ASCII → Transfer distinta) — NÃO
10. I vs i → 2 Transfers — NÃO
11. `wd_<uuid>` recusada — NÃO
12. Retry `wd_<uuid>` duplica Transfer — NÃO
13. Destination alheio — NÃO
14. payout > saldo / mint — NÃO
15. Buyer refund seller-only aberto — NÃO (403)
16. Release+refund cria dinheiro líquido — NÃO
17. Cross-user financeiro — NÃO
18. Saturação P0–P2 = 0 após quota ≥10 + ≥1 Transfer TEST — SIM

ATROFIA (só exacto Coptic): NÃO — 1/17  
Poço Stripe TEST: SIM (4 Transfers Connect + 2 PI succeeded + 1 refund)  
Quota CT-A ≥4: SIM · CT-B ≥3: SIM · CT-C ≥3: SIM  
Lentes 6/6 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

---

## ARTEFACTOS

`tool/redteam_blind_ct_20260906T1419/` — `_rtct.dart`, `pass1.dart`, `pass2.dart`, `pass1.json`, `pass2.json`, este relatório.
