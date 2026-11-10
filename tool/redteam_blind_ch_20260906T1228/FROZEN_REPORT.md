# FROZEN_REPORT — RED TEAM CEGO CH

## CONTAGEM

P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0

TOTAL P0–P3 abertos: 2

```
1. P0? NÃO
2. Quantos P0: 0
3. P1? NÃO
4. Quantos P1: 0
5. P2? SIM
6. Quantos P2: 2
7. P3? NÃO
8. Quantos P3: 0
```

```
AUDITOR: REDTEAM_BLIND_CH_PAYOUT_POS_BXCC_v1
FROZEN_AT: 2026-09-06T11:42:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CH1, CH2, CH3, CH4, CH5, CH6, CH7]
VEREDICTO: FAIL_P2
prefix: RTCH-20260906T1228
staging: fxdknzrqjenzqcvnwqqq
```

Exactos BXCC **não contados** (HOLD LIVE): Greek α/ο/ρ → **1** Transfer; cirílico `а`→`a` → **1** Transfer; NBSP mid-key → **1** Transfer.

---

## Missão

Depois do fold grego α/ο/ρ (BXCC), ainda 2 Transfers, mint wallet, refund>captura, ou desvio de destination?

**Resposta:** **2 Transfers sim**, com homóglifos **fora** do denylist grego/cirílico (arménio օ, georgiano ო, combining acute, İ, grego υ) — o fold mapeia um subconjunto e **apaga** o resto non-ASCII, por isso a substituição visual **não** colapsa com a chave latina. **Casefold I vs i** também → 2 Transfers (sem `toLowerCase`; prova Stripe). Mint **não**; refund body 999999 → **590 cêntimos** da linha; destination no body **ignorado** (Transfer própria `acct_1U5mYbQeUNx8ar08`); seller-only refund **mantém-se** (buyer/seller2 403).

---

## Findings abertos

### CH-P2-01 — homóglifo fora do fold grego/cirílico → 2 Transfers

- **Sev:** P2 · **Lente:** CH1/CH4 · **Actor:** seller JWT
- **Pré:** `payoutIdempotencyKey` = NFKC + strip ZWJ/BOM + compactar whitespace + fold **lista** cirílico/grego (incl. α/ο/ρ BXCC) + **apagar** `[^\x20-\x7E]`. Sem confusable arménio/georgiano/combining/İ/υ. Sem `toLowerCase`.
- **Repro (arménio):**
  1. POST `create-connect-account` `{amount:100, idempotency_key:"rtchoARMN88"}`
  2. POST mesma conta `{amount:100, idempotency_key:"rtchօARMN88"}` (U+0585 no lugar do «o»)
- **Esperado:** 1 intenção se a chave visual é a mesma (mapear օ→o) **ou** documentar Unicode distinto
- **Obtido:** 2 Transfers `tr_1UCeO6H7FWYUN3jh708yyQsT` + `tr_1UCeO8H7FWYUN3jhNR7Xkiwh`; wallet 62.33 → 60.33 (−2,00 €); `idempotentB=false`
- **Mesma classe (não contar extra):**
  - georgiano ო vs o (`rtchoGEOR88` / `rtchოGEOR88` U+10DD) → `tr_1UCeODH7FWYUN3jhc63B8iPd` + `tr_1UCeOFH7FWYUN3jhduY0gkpI` Δ −2 €
  - o + combining acute U+0301 vs o (`rtchoCOMB88`) → `tr_1UCeOXH7FWYUN3jhlsxON2XQ` + `tr_1UCeOaH7FWYUN3jhAObZD3N9` Δ −2 €
  - İ (U+0130) vs I (`rtchIkeyx88` / `rtchİkeyx88`) → strip İ deixa `rtchkeyx88` ≠ `rtchIkeyx88` → `tr_1UCeOiH7FWYUN3jhU0JBFQyc` + `tr_1UCeOkH7FWYUN3jh728jsIgU` Δ −2 €
  - grego υ vs u (fora do exacto α/ο/ρ) (`rtchuUPSL88`) → `tr_1UCeOoH7FWYUN3jhGFJGJy9F` + `tr_1UCeOqH7FWYUN3jh8cuRtLe2` Δ −2 €
  - race `Future.wait` o vs օ → `tr_1UCeP8H7FWYUN3jhoD9Fqj0m` + `tr_1UCeP8H7FWYUN3jhC1eXaZcC` Δ −2 €
- **Porquê:** apagar օ/ო/́/İ/υ deixa ASCII diferente da chave latina. Fold α/ο/ρ **não** cobre estes scripts/marcas.
- **Impacto:** levantamento **próprio** duplicado com chave visivelmente quase igual. Sem mint, sem cross-user.
- **Prova:** `pass1.json` findings `CH-P2-ARMENIAN-OH` + pares `count` mesma classe

Uma classe, vários payloads — **conta 1**.

### CH-P2-02 — casefold I vs i → 2 Transfers

- **Sev:** P2 · **Lente:** CH1 · **Actor:** seller JWT
- **Pré:** `payoutIdempotencyKey` **não** faz `toLowerCase` (comentário: case-sensitive por desenho). Pedido CH: contar se houver prova de 2 payouts.
- **Repro:** POST `{amount:100, idempotency_key:"rtchIcase88"}` depois `"rtchicase88"`
- **Obtido:** 2 Transfers `tr_1UCeOuH7FWYUN3jhM461YZGk` + `tr_1UCeOwH7FWYUN3jhxnGYEoBn`; Δ −2,00 €; `idempotentB=false`
- **Porquê:** `I` e `i` são ambos ASCII; o hash inclui o userId+folded sem casefold.
- **Impacto:** cliente hostil gera duas keys que diferem só em maiúsculas; app Flutter usa `wd_{uuid}_{cents}_{ms}` (uuid hex minúsculo) — o gap é no Edge, não no gerador normal.
- **Prova:** `pass1.json` `CH-P2-CASEFOLD-Ii`

**Conta 1** (mecanismo distinto do strip Unicode).

---

## HOLD (não contar)

| ID | Lente | Resultado |
|----|--------|-----------|
| Exact grego α→a | CH1 | 1 Transfer `tr_1UCeNqH7FWYUN3jhke7KVvKK` (fold BXCC LIVE) |
| Exact cirílico `а`→`a` | CH1 | 1 Transfer `tr_1UCeNwH7FWYUN3jhx1PXpptr` |
| Exact NBSP mid-key | CH1 | 1 Transfer `tr_1UCeO1H7FWYUN3jhjwgjad9I` |
| Math bold 𝐨 vs o | CH1 | 1 Transfer `tr_1UCeOIH7FWYUN3jh63HGYNXX` (NFKC) |
| Math mono 𝚊 vs a | CH1 | 1 Transfer `tr_1UCeOOH7FWYUN3jhiP7tb7VE` (NFKC) |
| Fullwidth ｏ vs o | CH1 | 1 Transfer `tr_1UCeOTH7FWYUN3jhEikoaL2A` (NFKC) |
| CGJ U+034F mid-key | CH1 | 1 Transfer `tr_1UCeOdH7FWYUN3jhWKVWX81o` (catch-all) |
| Key 7 chars | CH1 | 400 `idempotency_key em falta` |
| 8× combining vs ASCII distinta | CH1 | 2 Transfers — **não lookalike** (intenções diferentes; não contar) |
| Race 3× mesma key | CH1 | 1 Transfer `tr_1UCeP5H7FWYUN3jhA6eWd1Zx` |
| crash_inject **sem** secret | CH4 | ignorado; payout 200 `tr_1UCeNeH7FWYUN3jhPwMk3YEP` |
| crash after_debit + retry | CH4 | 500 órfão → retry 1 Transfer `tr_1UCeNiH7FWYUN3jh1qXT7Bs6` |
| crash after_stripe + retry | CH4 | mesmo `tr_1UCeNlH7FWYUN3jhhEHmUi2R` |
| crash after_finish + retry | CH4 | 1 Transfer `tr_1UCeQqH7FWYUN3jh0XowjyeS` |
| webhook `transfer.created` antigo sem sig | CH4 | 400 `missing_signature` |
| webhook `checkout.session.completed` t=2020 sig lixo | CH4 | 400 `invalid_signature` |
| body destination acct outro seller + currency usd | CH4 | Transfer **própria** `tr_1UCeNUH7FWYUN3jh49F5nRek`; logs sem acct alheio |
| JWT PATCH `stripe_account_id` | CH4 | 200 `[]` 0 rows; wallet continua `acct_1U5mYbQeUNx8ar08` |
| amount `[100]` / −100 / 100.5 / `"100.5"` / `0x64` / object | CH4 | 400 inválido |
| amount `"100"` | CH4 | aceite 100 cêntimos (desenho JS) — 1 Transfer `tr_1UCeNcH7FWYUN3jhcS4XsArR` |
| payout 99999999c > saldo | CH7 | 400 insuficiente; Δ=0 |
| JWT INSERT wallets (própria / alheia) | CH5 | 403 `42501` permission denied |
| JWT PATCH balance própria | CH5 | 200 `[]` Δ=0 |
| JWT PATCH balance buyer (pass1 `200 []`) | CH6 | **falso positivo**: buyer ficou **61,10 €** ≠ 66666; `updated_at` 2026-09-01 |
| JWT INSERT `wallet_payout_ledger` | CH5 | 403 RLS |
| JWT `batata_finalize_stripe_order_refund` | CH6 | 403 GRANT |
| POST/GET `web_return_origin` novos (IDN а, 。, javascript, unicode slash, CRLF, %00, suffix evil.pt, localhost.evil, next=, #@) | CH2 | Stripe url só connect.stripe.com; GET sem Location hostil (allowlist → `/wallet` ou HTML) |
| buyer `refund-order` | CH6 | 403 Sem permissão (**seller-only mantém-se**) |
| seller2 `refund-order` venda seller1 | CH6 | 403 |
| refund body amount 999999 | CH3 | refund **590 cêntimos** da linha (`re_3UCeQGH7FWYUN3jh1mhm561h`) |
| release JWT em `pago` | CH3 | `false`, Δ=0 |
| race refund∥release em `pago` | CH3 | refund sim; release false; Δ=0 |
| race refund∥release após enviado→concluido | CH3 | refund 403 `order_refund_blocked_shipped`; release `true` Δ **+5,00 €** (crédito legítimo, não ambos) |
| refund crash after_stripe_before_db + retry | CH3 | 1 `re_3UCeQtH7FWYUN3jh0HPFSUYr` |
| Δwallet vs ledger pass3 (script limit 40 vs 50) | CH7 | **falso positivo**: Δ −1,00 € = 1 Transfer novo `tr_1UCeQq…`; tids extra são corrida CB `tr_1UCdZ…` |

**Não é finding:** `service_role` a financiar wallet (fixture). Actor do exploit = JWT.

**Falsos positivos descartados:** PATCH alheio 200 vazio PostgREST; composição pass3 mix de ledger antigo; 8 combining marks vs ASCII (não homóglifo).

**Contabilidade payout pass1:** wallet seller 70.33 → 41.33 = **−29,00 €** = 29 Transfers de 100 cêntimos (incl. pares homóglifo + casefold + HOLD 1×). Sem mint. Pass2 release +5,00 € (ciclo concluido). Pass3 −1,00 € (1 Transfer crash-finish). Saldo final 45.33 coerente.

---

## Lentes 7/7

| Lente | Exercitada | Aberto |
|-------|------------|--------|
| CH1 Connect/idempotency | SIM | **P2 homóglifo novo**; **P2 casefold**; α/NFKC/CGJ/race mesma key HOLD |
| CH2 return hijack | SIM | HOLD origens novas sem url/Location hostil |
| CH3 release+refund | SIM | HOLD (buyer 403; release cedo Δ=0; race sem crédito+refund; refund blocked shipped) |
| CH4 Transfer/webhook | SIM | dest/crash/webhook/amount HOLD; Transfers reais TEST |
| CH5 wallet FSM/RLS | SIM | HOLD INSERT/PATCH/ledger JWT |
| CH6 actor cruzado | SIM | HOLD user dest PATCH; buyer/seller2 refund 403; finalize 403 |
| CH7 Δwallet | SIM | payouts próprios −29 €; release +5 € 1×; sem mint |

---

## CHECKLIST

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (INSERT 403; PATCH Δ=0; 2.º crédito só no release legítimo 1×)
13. Refund excede captura — NÃO (body 999999 → 590 cêntimos)
14. Release+refund cria dinheiro líquido — NÃO
15. Payout duplica Transfer indevidamente — PARCIAL: sim em keys lookalike novas + casefold (P2); não na mesma key (race/crash); não em α/cirílico/NBSP/NFKC math/fullwidth/CGJ
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
28. Saturação / último passe classe nova P0/P1 — NÃO (pass3 só crash-finish + falso Δ)

ATROFIA (só exactos Greek α/ο/ρ / cirílico / NBSP): NÃO  
Poço Stripe TEST pago: SIM (`setup_paid_order` + Transfers Connect TEST)  
Poços A–D: SIM · Lentes 7/7 · Tácticas 1–4: SIM

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**
