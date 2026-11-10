# FROZEN_REPORT — RED TEAM CEGO CN

## CONTAGEM

P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
P4 aberto: NÃO → quantos: 0

TOTAL P0–P3 abertos: 1

```
1. P0? NÃO
2. Quantos P0: 0
3. P1? NÃO
4. Quantos P1: 0
5. P2? SIM
6. Quantos P2: 1
7. P3? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CN_PAYOUT_POS_CDCI_v1
FROZEN_AT: 2026-09-06T13:28:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CN1, CN2, CN3, CN4, CN5, CN6, CN7]
probes_na_tabela: 34 (≥24)
VEREDICTO: FAIL_P2
prefix: RTCN-20260906T1317
staging: fxdknzrqjenzqcvnwqqq
```

Exactos CDCI **não contados** (HOLD LIVE, 1 Transfer): arménio օ→o `tr_1UCf87H7FWYUN3jh0rnRJe5x`; grego α→a `tr_1UCf8CH7FWYUN3jhRw1WTjCk`; I vs i `tr_1UCf8IH7FWYUN3jhFjZ49rpI`. Residual = **3**.

---

## Missão

2 Transfers / mint / refund>captura / release pós-partial — além fold CDCI?

**Resposta:** **2 Transfers sim**, com homóglifos **Coptic e Cherokee** (fora da lista CDCI cirílico/grego/arménio/georgiano). O fold mapeia o subconjunto e **apaga** o resto non-ASCII, por isso `rtcnoCopt01` ≠ `rtcnⲟCopt01` (ⲟ stripped). **Mint não.** Refund body `amount=100` → **590 cêntimos** da linha; release depois **false, Δ=0**. Destination no body **ignorado** (Transfer própria `acct_1U5mYbQeUNx8ar08`). Buyer/seller2 refund **403** (seller-only mantém-se).

---

## Findings abertos

### CN-P2-01 — Coptic/Cherokee fora do fold CDCI → 2 Transfers

- **Sev:** P2 · **Lente:** CN1/CN4 · **Actor:** seller JWT · **ID contagem:** P2-1
- **Pré:** `payoutIdempotencyKey` = NFKC + strip ZW/marks + fold lista cirílico/grego/arménio/georgiano/υ/İ + `toLowerCase` + **apagar** `[^\x20-\x7E]`. Sem Coptic (U+2C80+) nem Cherokee (U+13A0+).
- **Repro (Coptic o):**
  1. POST `create-connect-account` `{amount:100, idempotency_key:"rtcnoCopt01"}`
  2. POST mesma conta `{amount:100, idempotency_key:"rtcnⲟCopt01"}` (U+2C9F no lugar do «o»)
- **Esperado:** 1 Transfer se a chave visual é a mesma (mapear ⲟ→o) **ou** documentar Unicode distinto
- **Obtido:** 2 Transfers `tr_1UCf7KH7FWYUN3jhlxCOPuLh` + `tr_1UCf7NH7FWYUN3jhpebflx4H`; Δ −2,00 €; `idempotentB=false`
- **Mesma classe (não contar extra):**
  - ⲁ vs a → `tr_1UCf7QH7FWYUN3jhPs3aVFic` + `tr_1UCf7TH7FWYUN3jh9MessCQx`
  - ⲣ vs p → `tr_1UCf7XH7FWYUN3jh1xgiiE7p` + `tr_1UCf7aH7FWYUN3jhE1rI4WLR`
  - ⲉ vs e → `tr_1UCf7dH7FWYUN3jhvgX163mM` + `tr_1UCf7fH7FWYUN3jh9Zsy2V1O`
  - ⲓ vs i → `tr_1UCf7jH7FWYUN3jh3LpbjAK0` + `tr_1UCf7lH7FWYUN3jh0DmBc3vc`
  - ⲕ vs k → `tr_1UCf7pH7FWYUN3jhSmJesflT` + `tr_1UCf7rH7FWYUN3jhnUI5nlBQ`
  - Cherokee Ꮎ vs o → `tr_1UCf7vH7FWYUN3jhICWQKBpW` + `tr_1UCf7xH7FWYUN3jhUjMjHFw2`
  - Cherokee Ꭺ vs A → `tr_1UCf80H7FWYUN3jhtISLMf6B` + `tr_1UCf83H7FWYUN3jhEUwhSl69`
  - race `Future.wait` o vs ⲟ → `tr_1UCf8dH7FWYUN3jhulFCXVEA` + `tr_1UCf8dH7FWYUN3jh8Tf3cHOw`
- **Porquê:** apagar ⲟ/ⲁ/ⲣ/ⲉ/ⲓ/ⲕ/Ꮎ/Ꭺ deixa ASCII diferente da chave latina. Fold CDCI **não** cobre Coptic nem Cherokee.
- **Impacto:** levantamento **próprio** duplicado com chave visivelmente quase igual. Sem mint, sem cross-user.
- **Prova:** `pass1.json` probes `CN-A-COPTIC-*` + `CN-A-CHEROKEE-*` + `CN-A-PAR-NE-FOLD`

Uma classe, vários payloads — **conta 1**.

---

## TABELA DE PROVAS

| ID | payload | HTTP/BD | HOLD\|FAIL |
|----|---------|---------|------------|
| CN-B-DEST | dest=acct_1UB7nWHKe5ETfHI5 currency=usd amount=100 | 200 `tr_1UCf78H7FWYUN3jh5Etqkm6y` própria `acct_1U5mYbQeUNx8ar08` | HOLD |
| CN-B-OVERBAL | amount=99999999 vs saldo 89 | 400 insuficiente Δ=0 | HOLD |
| CN-B-AMT-arr | amount=[100] | 400 valor inválido | HOLD |
| CN-B-AMT-neg | amount=-100 | 400 valor inválido | HOLD |
| CN-B-AMT-usdobj | amount={cents:100,currency:usd} | 400 valor inválido | HOLD |
| CN-C-WH-NOSIG | webhook transfer.created sem sig | 400 `missing_signature` | HOLD |
| CN-C-CRASH-RETRY | crash after_debit + retry mesma key | 500 órfão → 200 `tr_1UCf7HH7FWYUN3jhUMDnwsps` (1 tr) | HOLD |
| CN-A-COPTIC-O | rtcnoCopt01 vs rtcnⲟCopt01 | 2 tr `tr_1UCf7K…`+`tr_1UCf7N…` Δ−2 | FAIL |
| CN-A-COPTIC-A | rtcnaCopt02 vs rtcnⲁCopt02 | 2 tr `tr_1UCf7Q…`+`tr_1UCf7T…` Δ−2 | FAIL |
| CN-A-COPTIC-P | rtcnpCopt03 vs rtcnⲣCopt03 | 2 tr `tr_1UCf7X…`+`tr_1UCf7a…` Δ−2 | FAIL |
| CN-A-COPTIC-E | rtcneCopt04 vs rtcnⲉCopt04 | 2 tr `tr_1UCf7d…`+`tr_1UCf7f…` Δ−2 | FAIL |
| CN-A-COPTIC-I | rtcniCopt05 vs rtcnⲓCopt05 | 2 tr `tr_1UCf7j…`+`tr_1UCf7l…` Δ−2 | FAIL |
| CN-A-COPTIC-K | rtcnkCopt06 vs rtcnⲕCopt06 | 2 tr `tr_1UCf7p…`+`tr_1UCf7r…` Δ−2 | FAIL |
| CN-A-CHEROKEE-O | rtcnoCher07 vs rtcnᎾCher07 | 2 tr `tr_1UCf7v…`+`tr_1UCf7x…` Δ−2 | FAIL |
| CN-A-CHEROKEE-A | rtcnACher08 vs rtcnᎪCher08 | 2 tr `tr_1UCf80…`+`tr_1UCf83…` Δ−2 | FAIL |
| CN-HOLD-ARMENIAN | rtcnoArmR01 vs rtcnօArmR01 | 1 tr `tr_1UCf87H7FWYUN3jh0rnRJe5x` | HOLD |
| CN-HOLD-GREEK-ALPHA | rtcnaGRkR02 vs rtcnαGRkR02 | 1 tr `tr_1UCf8CH7FWYUN3jhRw1WTjCk` | HOLD |
| CN-HOLD-CASE-Ii | rtcnIcaseR3 vs rtcnicaseR3 | 1 tr `tr_1UCf8IH7FWYUN3jhFjZ49rpI` | HOLD |
| CN-A-ZWSP-VS-ASCII | rtcnzwsp088 vs 8×U+200B | n_tr=1; B idempotente (fold-vazio legado) | HOLD |
| CN-A-LEN-MAX-1 | key 254 chars | 200 `tr_1UCf8QH7FWYUN3jhJVe9pHUs` | HOLD |
| CN-A-LEN-MAX | key 255 chars | 200 `tr_1UCf8TH7FWYUN3jhJIhbpXya` | HOLD |
| CN-A-LEN-MAX+1 | key 256 chars | 200 `tr_1UCf8VH7FWYUN3jhs3YrlcFj` | HOLD |
| CN-A-LEN-EMPTY | key "" | 400 idempotency_key em falta | HOLD |
| CN-A-LEN-ZWSP | 8×U+200B | 200 idempotent `tr_1UCeP2H7FWYUN3jhv3iqLRAW` | HOLD |
| CN-A-PAR-EQ-FOLD | Future.wait a vs α | 1 tr `tr_1UCf8aH7FWYUN3jhSHAew0Di` | HOLD |
| CN-A-PAR-NE-FOLD | Future.wait o vs ⲟ | 2 tr `tr_1UCf8d…A`+`tr_1UCf8d…w` | FAIL |
| CN-D-BUYER-REFUND | refund-order JWT comprador | 403 Sem permissão Δ=0 | HOLD |
| CN-D-S2-REFUND | refund-order JWT seller2 | 403 Sem permissão | HOLD |
| CN-D-REL-REFUND-RACE | refund∥release em pago | refund `re_3UCf9A…` 590¢; release false; Δ=0 | HOLD |
| CN-D-PARTIAL-THEN-RELEASE | body amount=100 → ship/concluido/release | refund 590¢ (body ignorado); release false; Δ=0; PATCH status 403 `order_status_denied_after_refund` | HOLD |
| CN-2-WR-EVILPT | web_return_origin fleaber.pt.evil.pt | 200 url `connect.stripe.com` sem evil | HOLD |
| CN-5-WALLET-INS | JWT INSERT wallets 99999 | 403 `42501` | HOLD |
| CN-5-WALLET-PATCH | JWT PATCH balance=77777 | 200 `[]` Δ=0 (62→62) | HOLD |
| CN-C-WH-OLDSIG | webhook t=2020 sig lixo | 400 `invalid_signature` | HOLD |

probes_na_tabela: **34**

CN-A keys com resultado Stripe: 16 (6 pares Coptic + 2 Cherokee) + length + races. Transfer TEST real: sim (`tr_1UCf78…` e seguintes).

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Residual arménio օ | CN1 | 1 Transfer (fold CDCI LIVE) |
| Residual grego α | CN1 | 1 Transfer |
| Residual I/i | CN1 | 1 Transfer (`toLowerCase`) |
| Race α vs a | CN1 | 1 Transfer |
| ZWSP vs ASCII / 8×ZWSP | CN1 | 1 Transfer novo ASCII; ZWSP idempotente no bucket fold-vazio legado `tr_1UCeP2…` |
| Key 254/255/256 | CN1 | 3 Transfers distintas (sem tecto no raw; hash `p_` 64) |
| Key vazia | CN1 | 400 |
| dest/currency body | CN4 | Transfer própria |
| amount array / −100 / object | CN4 | 400 |
| payout > saldo | CN7 | 400 Δ=0 |
| crash after_debit + retry | CN4 | 1 Transfer |
| webhook sem sig / sig lixo | CN4 | 400 |
| buyer / seller2 refund | CN6 | 403 seller-only **não abriu** |
| refund∥release pago | CN3 | refund sim; release false; Δ=0 |
| partial body → release | CN3 | 590¢ da linha; release false |
| web_return evil suffix | CN2 | url só connect.stripe.com |
| JWT INSERT/PATCH wallet | CN5 | 403 / 200 `[]` Δ=0 |

**Não é finding:** `service_role` a financiar wallet (fixture 54.33→90). Actor do exploit = JWT.

**Contabilidade pass1:** wallet seller fixture 90,00 → 62,00 = **−28,00 €** = 28 Transfers de 100 cêntimos (incl. pares Coptic/Cherokee + residual 1× + dest + crash + length 3 + races). Sem mint. Pass2 refund Stripe 590¢ ×2 (unshipped); Δ wallet 0. Pass3 PATCH Δ=0. Saldo final **62,00 €** coerente.

---

## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CN1 Connect/idempotency | SIM | **P2 Coptic/Cherokee**; residual CDCI HOLD; length/ZWSP/race≡fold HOLD |
| CN2 return hijack | SIM | HOLD origin evil → connect.stripe.com |
| CN3 release+refund | SIM | HOLD (buyer 403; race sem crédito+refund; body 100→590¢; release pós-refund false) |
| CN4 Transfer/webhook | SIM | dest/crash/webhook/amount HOLD; Transfers reais TEST |
| CN5 wallet FSM/RLS | SIM | HOLD INSERT 403; PATCH Δ=0 |
| CN6 actor cruzado | SIM | HOLD buyer/seller2 refund 403 |
| CN7 Δwallet | SIM | payouts próprios −28 €; sem mint |

---

## CHECKLIST

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
12. JWT cria saldo/fundos — NÃO (INSERT 403; PATCH Δ=0)
13. Refund excede captura — NÃO (body 100 → 590 cêntimos da linha)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer indevidamente — PARCIAL: sim em keys Coptic/Cherokee (P2); não na mesma key (crash/race≡fold); não em օ/α/I-i CDCI
16. Stock=1 duas vendas válidas — NÃO COMPROVADO (fora poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO
20. Cross-user dados sensíveis — NÃO
21. Buyer assume seller/admin — NÃO (refund-order 403)
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO COMPROVADO (fora poço)
24. RPC SECURITY DEFINER perigoso executável — NÃO
25. RLS crítico quebrado — NÃO
26. Edge confia autoridade do cliente no total — NÃO (`destination`/`currency`/`amount` hostil rejeitados ou ignorados)
27. Conclusão crítica NÃO COMPROVADA — NÃO (Stripe TEST Transfer + refund + release)
28. Saturação / último passe classe nova P0/P1 — NÃO (pass3 só return/RLS/webhook HOLD)

ATROFIA (só exactos CDCI arménio/grego α / I-i): NÃO — 3 controlos residual HOLD  
Poço Stripe TEST pago: SIM (`setup_paid_order` PI succeeded 590¢ + Transfers Connect TEST)  
Quota CN-A ≥16 keys: SIM · CN-B ≥4: SIM · CN-C ≥2: SIM · CN-D ≥4: SIM  
Lentes 7/7 · **NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

---

## ARTEFACTOS

`tool/redteam_blind_cn_20260906T1317/` — `_rtcn.dart`, `pass1.dart`, `pass2.dart`, `pass3.dart`, `pass1.json`, `pass2.json`, `pass3.json`, este relatório.
