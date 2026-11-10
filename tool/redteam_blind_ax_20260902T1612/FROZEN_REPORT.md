# FROZEN REPORT — RED TEAM CEGO AX
## Auditor independente · PÓS-FECHO ANAS · PAYOUT / WALLET / REFUND · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 2
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)

TOTAL P0–P3 abertos: 4
```

```
AUDITOR: REDTEAM_BLIND_AX_PAYOUT_POS_ANAS_v1
FROZEN_AT: 2026-09-02T15:22:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AX1, AX2, AX3, AX4, AX5, AX6, AX7]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT buyer `bfcbeeee-…` · seller `980f4fa1-…` · buyer2/seller2 `RTAX-20260902T1612-*`.  
`service_role` só fixture (`setup_paid_order`, `shipping_method` mão, top-up saldo seller 0→20 €, `list_stripe_refunds`, observação). Prefixo `RTAX-20260902T1612-`.  
Provas: `pass1.json`, `pass2.json`, `pass3.json`, `observe.json`. Repro: `dart run tool/redteam_blind_ax_20260902T1612/probe.dart` (+ `pass2.dart`, `pass3.dart`, `observe.dart`).

**Missão.** Dinheiro na carteira/Connect — consigo tirar 2×, para conta errada, ou refund/release que minta?

**Resposta.** Não neste poço: débito/finish/finalize/clawback/credit JWT 403; `generate_auto_feedback` JWT 403; Connect `user_id` cruzado 400; webhooks Transfer/refund/payout com assinatura lixo 400; 3× mesma key hash → 1 Transfer; crash `after_stripe` + retry mesma key → o mesmo `tr_`; prefixo 64 (exact AR-P3) agora **2** Transfers distintos; short key / não-string 400; 2 users mesma raw key não herda Transfer (S2 sem IBAN 400); buyer concluido during return **403** `order_concluido_denied_during_return`; seller concluido **403** `order_seller_cannot_mark_concluido`; unship JWT **403** `order_shipped_at_immutable`; regression enviado→pendente **403**; release sem envio/mão **false**; 2.ª release **false**; refund pós-release **403**; buyer/B2 refund **403**; parcial 200% **403** `not_allowed`; Δbuyer **0,00 €**. Happy path: PI 590¢ + mão + release seller **+5,00 €**; refund em `pago` `re_3UBFwhH7…` 590¢. Restam higiene P2 (métodos HTTP + `shipped_at` forjado no hop `enviado`) e P3 de coerção `Number()`.

Não é ATROFIA_ABORT (0/6 achados = buyer concluido during return exact AR7 · unship silent 200 exact AR5 · prefixo 64 exact AR-P3 · cancel silent 200 AL5 · dual Session · mint pós-payout).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 2
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (fora do poço payout)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`debit`/`finish`/`credit`/`finalize`/`clawback`/`ensure_wallet`/`generate_auto_feedback` 403; `refund_buyer_wallet` / `process_partial` 200 false / 403; PATCH `wallets.balance` 200 [])
13. Refund excede captura — NÃO (body `amount=99999` / `reverse_transfer` ignorados; refund em `pago` 590¢)
14. Release+refund cria dinheiro líquido — NÃO (refund-order 403 em concluido; race: refund perde, release +5,00 € seller; Δbuyer 0; PI sem `re_` após release)
15. Payout duplica Transfer — NÃO (3× mesma key hash → 1 `tr_`; crash retry → mesmo `tr_`; prefixo 64 agora 2 Transfer **distintos**; 2 users mesma raw key não partilha `tr_`)
16. Stock=1 duas vendas válidas — NÃO (refund pago: 1 captura, 1 `re_`)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (S2 `user_id`=S1 400; B/B2 refund-order 403)
20. Cross-user dados sensíveis — NÃO (GET `wallet_payout_ledger` seller → 200 [])
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (classe atrofia; cron `generate_auto_feedback` JWT 403)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`payout_*`/`finalize`/`credit`/`clawback`/`auto_feedback` 42501). `refund_buyer_wallet` fail-closed (`false`)
25. RLS crítico quebrado — NÃO (INSERT txn 403; PATCH Connect/balance 200 [])
26. Edge confia total do cliente — PARCIAL (`amount:true` / `amount:"0x64"` → Transfer via `Number()` — P3; PUT/PATCH/DELETE com amount pagam — P2; `destination`/`return_url` ignorados)
27. Regressão funcional (happy path partido) — NÃO (refund em `pago` 200; release buyer JWT `true`; payout 100¢ Transfer real; fechos ANAS 403)
28. Saturação atingida — NÃO (P2 aberto; S2 sem IBAN continua a não exercitar `idempotency_key_foreign` no Edge)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P2 · AX1-payout-non-POST-methods

**Lentes:** AX1  
**Actor:** seller JWT

**O quê:** `create-connect-account` trata PUT, PATCH e DELETE **com** `amount` + `idempotency_key` como um levantamento. Cada um criou Transfer Stripe TEST de 100¢ na Connect do JWT. AR só tinha testado PUT **sem** amount (AccountLink, sem Transfer).

**Não é** duplicar o mesmo cêntimo (keys distintas); não é mint. O vendedor tira o próprio saldo por um verbo HTTP que deveria ser 405.

**Prova (pass2):** `tr_1UBFvmH7FWYUN3jhp2SAPnYq` (PUT) · `tr_1UBFvpH7FWYUN3jhrdHln3DQ` (PATCH) · `tr_1UBFvrH7FWYUN3jhHMKn4IJE` (DELETE). Um único root cause → **1** P2 na CONTAGEM.

**Esperado:** 405 Method Not Allowed (só POST levanta).  
**Obtido:** 200 + Transfer.

---

### P2 · AX5-shipped-at-backdate-on-enviado

**Lentes:** AX5  
**Actor:** seller JWT

**O quê:** No hop `pago` → `enviado`, o trigger ANAS `order_shipped_at_immutable` **salta** quando `OLD.shipped_at` é null e o status passa a `enviado`. Se o cliente envia `shipped_at=2020-01-02` no mesmo PATCH, o ramo `NEW.shipped_at is null → now()` não corre e o relógio **fica em 2020**. Unship JWT continua **403** (exact AR5 fechado). Release continua a exigir `concluido` + envio/mão — **não** liberta carteira sozinho.

**Não é** unship silent 200 exact AR5. É forjar a data de envio no único instante em que o selo é permitido.

**Prova (observe.json):** order `a4818f9c-…` · PI `pi_3UBFwNH7FWYUN3jh1M4c7Fre` · `status=enviado` · `shipped_at=2020-01-02T00:00:00+00:00`.

**Esperado:** `shipped_at := now()` (ignorar o cliente).  
**Obtido:** selo 2020 persistido.

---

### P3 · AX1-amount-true

**Lentes:** AX1  
**Actor:** seller JWT

**O quê:** `amount: true` (boolean JSON) passa `Number(true)===1` e `Number.isInteger(1)`. Transfer **1¢**.

**Não é** `amount:[100]` AR nem `"1e2"` AL.

**Prova (pass1):** `tr_1UBFuzH7FWYUN3jhp1bhkpl1`.

**Esperado:** 400 valor inválido.  
**Obtido:** 200 Transfer 1¢.

---

### P3 · AX1-amount-hex

**Lentes:** AX1  
**Actor:** seller JWT

**O quê:** `amount: "0x64"` passa `Number("0x64")===100`. Transfer **100¢**. Variante nova vs `"1e2"` AL (mesmo `Number()`, literal hex).

**Prova (pass1):** `tr_1UBFv2H7FWYUN3jhg8fizMAG`.

**Esperado:** 400 / só cêntimos decimais.  
**Obtido:** 200 Transfer 100¢.

--------------------------------------------------
## LENTES (esperado vs obtido)
--------------------------------------------------

### AX1 · Payout JWT/Edge hostil · replay idempotency hash

| Ataque | Obtido |
|--------|--------|
| JWT `payout_debit` / `finish` / `clawback` / `credit` / `finalize` | **403** 42501 |
| JWT `refund_buyer_wallet` | **200 false** |
| JWT `process_partial` dummy | **200 false** |
| JWT `generate_auto_feedback` `p_now+400d` | **403** 42501 |
| JWT debit key `p_`+62 hex | **403** |
| PATCH `wallets.balance` | **200 []** |
| INSERT `wallet_transactions` | **403** RLS |
| GraphQL `updatewalletsCollection` | 200 `pg_graphql extension is not enabled` |
| Key 7 chars / whitespace / empty / number / array | **400** `idempotency_key em falta` |
| NFC vs NFD `café` | **2** Transfers `tr_1UBFudH7…` / `tr_1UBFugH7…` (hash diverge) |
| Prefixo 64 chars, 2 keys (exact AR-P3) | **2** Transfers `tr_1UBFujH7…` / `tr_1UBFulH7…` — hash **fecha** o slice |
| 3× mesma key // | **1** `tr_1UBFuoH7FWYUN3jh7fZL5TIT` |
| 2 users mesma raw key | S1 Transfer; S2 **400** IBAN; buyer **400** |
| crash `after_stripe_before_finish` + retry mesma key | mesmo `tr_1UBFvdH7FWYUN3jhdxNjQYLo` (ledger `p_36603e7c9f0fed57…`) |
| mesma key amount 100 depois 500 | **idempotent** mesmo `tr_1UBFviH7…` |
| PUT/PATCH/DELETE **com** amount | Transfer (P2) |
| `amount:true` / `"0x64"` | Transfer 1¢ / 100¢ (P3) |

### AX2 · Connect return hijack

| Ataque | Obtido |
|--------|--------|
| `next=https://evil.com` / backslash / Origin+Forwarded | **303** `https://fleaber.pt/wallet` **sem** evil |
| punycode / `fleaber.pt:443.evil.com` | HTML **200** sem Location hostil |
| POST `return_url`/`refresh_url`/`web_return_origin`/`stripe_account_id` evil | AccountLink `acct_1U5mYbQeUNx8ar08` **sem** `evil.com` |
| S2 `user_id`=S1 | **400** `Cannot create another user Stripe account.` |
| PATCH `wallets.stripe_account_id` | **200 []** |

### AX3 · Release + refund + clawback = líquido

Venda `02700afa-…` PI `pi_3UBFwYH7FWYUN3jh0neVjQSs` captura **590¢**, `shipping_method` mão. Buyer `concluido` + `batata_release_seller_wallet_for_order` → **true**, seller **+5,00 €**. 2.ª chamada → **false**. `refund-order` **403** `order_refund_blocked_status`. Clawback JWT **403**. Δbuyer **0**.

Pago CTT sem envio: `PATCH concluido` **403** `order_concluido_requires_shipped`; release **false**.

### AX4 · Transfer duplicado / webhook replay

`transfer.created` / `transfer.reversed` / `payout.paid` / `payout.failed` / `charge.refunded` / `charge.dispute.created` / `account.updated` / `checkout.session.completed`: sem assinatura → **400** `missing_signature`; `stripe-signature: t=1,v1=cafebabe` → **400** `invalid_signature`. O handler só settle `checkout.session.*` **depois** de verificar whsec — replay Transfer não minta wallet.

### AX5 · Seller refund após release · parcial > captura · devolvida gate

| Ataque | Obtido |
|--------|--------|
| Unship JWT `shipped_at=null` | **403** `order_shipped_at_immutable` (order `d136607e-…` selo intacto) |
| Regression `enviado`→`pendente` | **403** |
| `enviado` + `shipped_at=2020-01-02` | selo **2020** persistido (P2) |
| service_role unship (observe, não actor) | `92e85c19-…` `shipped_at=null` `status=enviado`; refund JWT **403** `order_refund_blocked_status` |
| refund-order após release | **403** `order_refund_blocked_status` |
| `process_partial` 200% | **403** `not_allowed` |
| refund em `pago` | **200** `re_3UBFwhH7FWYUN3jh1Cf7xDsO` 590¢ `cancelado` · Δbuyer/seller **0** |
| refund em `pedido_devolucao` | **403** `order_refund_blocked_shipped` |

### AX6 · Buyer força refund alheio · cancel pós-pago · FSM return

| Ataque | Obtido |
|--------|--------|
| Seller `enviado`→`concluido` | **403** `order_seller_cannot_mark_concluido`; release **false** |
| PATCH `completed_at` −50h + cron JWT | completed_at **null** (não recuou); cron **403**; HTTP PATCH 200 representação inalterada — **não** HOLD (fail-closed; não é unship AR5) |
| Buyer `concluido` em `pedido_devolucao` | **403** `order_concluido_denied_during_return` (ANAS fecha AR7) |
| Seller `concluido` em devolução | **403** `order_return_in_progress` |
| Buyer `cancelado` em devolução | **403** (não silent 200 AL5) |
| Buyer / B2 `refund-order` | **403** Sem permissão |
| Seller `pedido_devolucao`→`devolvida` | **403** `order_devolvida_denied` |

### AX7 · Composição até Δwallet / Stripe net

Race `refund-order` ∥ `PATCH concluido` (`a0be355c-…` / `pi_3UBFwsH7FWYUN3jh07odoLH3`): refund **403** (concluido ganhou); release **true** seller **+5,00 €**; Δbuyer **0**; sem `stripe_refund_id`. Sem coexistência Transfer desta venda + refund Stripe no mesmo `order_id`.

Buyer wallet início **61,10 €** · fim pass3 **61,10 €**. Seller: fixture top-up 20 € + releases − payouts TEST (não drenámos produção). Sem mint comprador sem PI refundido.

Pass3 `orderRow` inicial pedia `return_delivered_at` (coluna **não existe** → GET 400). `observe.dart` relê sem essa coluna; fechos ANAS confirmados no GET.

--------------------------------------------------
## Transfers Stripe TEST (observação, não findings extra)
--------------------------------------------------

Conta Connect seller `acct_1U5mYbQeUNx8ar08`. Desta ronda (100¢ salvo indicação):  
NFC `tr_1UBFudH7…`, NFD `tr_1UBFugH7…`, prefix-64 `tr_1UBFujH7…` / `tr_1UBFulH7…`, replay `tr_1UBFuoH7…`, shared S1 `tr_1UBFuqH7…`, amount true 1¢ `tr_1UBFuzH7…`, hex `tr_1UBFv2H7…`, crash/retry `tr_1UBFvdH7…`, grow `tr_1UBFviH7…`, PUT/PATCH/DELETE (P2), pós-release `tr_1UBFwxH7FWYUN3jhSihGt2Pe`.

Refunds: `re_3UBFwhH7FWYUN3jh1Cf7xDsO` (pago 590¢).

--------------------------------------------------
## Anti-atrofia
--------------------------------------------------

Exercício: Stripe TEST pago → mão → release → Transfer; refund em `pago`; JWT hostil; hash vs prefixo 64; short key; 2 users; crash+retry; seller/buyer concluido em devolução; unship 403; regression; `shipped_at` 2020; cron 48h JWT; webhooks Transfer; PUT/PATCH/DELETE; `amount` boolean/hex.  
0/6 findings na lista exacta AR/AL (buyer concluido during return · unship silent 200 · prefixo 64 · cancel silent 200 · dual Session · mint pós-payout).

`amount:[100]` **não** re-provado (já AL/AR). `"1e2"` **não** re-provado; `"0x64"` e `true` entram como P3 novos.

--------------------------------------------------
## Notas (não HOLD)
--------------------------------------------------

- Flutter gera `wd_{uuid}_{cents}_{ms}`; hash `p_`+62 hex no Edge — prefixo 64 no cliente **já não** funde.
- Crash inject exige secret de staging; retry da **mesma** raw key retoma o mesmo `tr_`.
- S2 sem IBAN: `idempotency_key_foreign` não exercitado (hash inclui `userId`; falha antes em Connect ready).
- `service_role` apaga `shipped_at` (`92e85c19-…`) porque o trigger só corre em `authenticated`. JWT unship 403; refund continua bloqueado por `status=enviado`. Fora de actor JWT — observação pedida pelo prompt, não CONTAGEM.
- Saldo seller estava **0,00 €** ao início (rondas anteriores); fixture service_role top-up **20 €** só para exercitar Transfer. Não é mint JWT.
