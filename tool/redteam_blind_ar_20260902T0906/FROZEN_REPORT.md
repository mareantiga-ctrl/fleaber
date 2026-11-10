# FROZEN REPORT — RED TEAM CEGO AR
## Auditor independente · PÓS-FECHO AHAM · PAYOUT / WALLET / REFUND · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: SIM          → quantos: 1
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 1
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AR_PAYOUT_POS_AHAM_v1
FROZEN_AT: 2026-09-02T09:22:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AR1, AR2, AR3, AR4, AR5, AR6, AR7]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT buyer `bfcbeeee-…` · seller `980f4fa1-…` · buyer2/seller2 `RTAR-20260902T0906-*`.  
`service_role` só fixture (`setup_paid_order`, `shipping_method` mão, `list_stripe_refunds`, observação). Prefixo `RTAR-20260902T0906-`.  
Provas: `pass1.json`, `pass2.json`, `pass3.json`. Repro: `dart run tool/redteam_blind_ar_20260902T0906/probe.dart` (+ `pass2.dart`, `pass3.dart`).

**Missão.** Dinheiro na carteira/Connect — consigo tirar 2×, para conta errada, ou refund/release que minta?

**Resposta.** Não neste poço: débito/finish/finalize/clawback/credit JWT 403; Connect `user_id` cruzado 400; `Stripe-Account` / `return_url` hostis ignorados; webhooks Transfer/refund com assinatura lixo 400; 3× mesma key → 1 Transfer; crash `after_stripe` + retry mesma key → o mesmo `tr_`; refund-order // → 1 `re_`; buyer/B2 refund 403; Δbuyer **0,00 €**. Fechos AHAM provaram-se (cancel pós-pago **403**; stock em `devolvida` **não** restaura sem `stripe_refund_id`; refund terminal `devolvida` **antes** de `shipped_at` → Stripe 590¢). Restam um P1 de FSM (comprador `concluido` a meio da devolução trava refund) e higiene P2/P3.

Não é ATROFIA_ABORT (0/3 achados = cancel silent 200 exact AL5 · dual Session · payout idempotency clássico same-key+montante · review 5★ · mint pós-payout).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — SIM
4. Quantos P1: 1
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 1
9. Buyer manipula preço autoritativo — NÃO (fora do poço payout)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`debit`/`finish`/`credit`/`finalize`/`clawback` 403; `refund_buyer_wallet` 200 false; PATCH `wallets.balance` 200 [])
13. Refund excede captura — NÃO (body `amount=99999` / `reverse_transfer` ignorados; 1 refund 590¢)
14. Release+refund cria dinheiro líquido — NÃO (refund-order 403 em concluido; Δbuyer 0; PI sem `re_` após release)
15. Payout duplica Transfer — NÃO (3× mesma key → 1 `tr_`; crash retry → mesmo `tr_`; prefixo 64 funde 2 keys numa Transfer, não duplica)
16. Stock=1 duas vendas válidas — NÃO (devolvida sem refund: qty 0→0, applied 1)
17. Stock=1 duas capturas líquidas permanentes — NÃO
18. Bypass capacidade/reserva — NÃO
19. Cross-user financeiro — NÃO (buyer Connect S2 400; B2 refund-order 403; S2 `user_id`=S1 400)
20. Cross-user dados sensíveis — NÃO (GET `wallets`/`wallet_payout_ledger` seller → 200 [])
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (classe atrofia, não exercitado)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`payout_*`/`finalize`/`credit`/`clawback` 42501). `refund_buyer_wallet` / `process_partial` JWT fail-closed (`false`)
25. RLS crítico quebrado — NÃO (INSERT txn 403; PATCH Connect/balance 200 [])
26. Edge confia total do cliente — PARCIAL (tipos: `amount:[100]` → `Number([100])===100`, mesma coerção que string AL, **não** finding; `destination`/`Stripe-Account`/`currency` ignorados)
27. Regressão funcional (happy path partido) — NÃO (refund em `pago` 200; refund em `devolvida`+`shipped_at` 200; release buyer JWT; payout 100¢ Transfer real; cancel pós-pago 403 como AHAM)
28. Saturação atingida — NÃO (P1 aberto; S2 sem IBAN continua a não exercitar `idempotency_key_foreign` no Edge)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ACHADOS
--------------------------------------------------

### P1 · AR7-buyer-concluido-durante-devolucao

**Lentes:** AR7, AR5, AR6  
**Actor:** buyer JWT

**O quê:** Com a encomenda em ciclo de devolução (`entregue` → disputa → `pedido_devolucao` → `em_devolucao` → `devolucao_entregue`), o comprador `PATCH status=concluido` é **aceite**. O vendedor que tenta `devolvida` no mesmo instante recebe **403** `order_concluido_immutable_for_seller`. `batata_release_seller_wallet_for_order` → `false` (disputa aberta). `refund-order` → **403** `order_refund_blocked_shipped` com `status=concluido`. PaymentIntent **sem** refund. Δwallet comprador e vendedor **0**.

**Não é** mint pós-payout, dual Session, nem cancel silent 200. O dinheiro fica na captura Stripe; ninguém o tira 2× — mas o vendedor **não consegue** reembolsar nem fechar `devolvida` por JWT.

**Prova (pass3):** order `96437f0f-…` · PI `pi_3UBAKjH7FWYUN3jh0LwGcvA8` · `refund_count=0` · `status=concluido` · `released` null · `stripe_refund_id` null.

**Esperado:** `concluido` recusado enquanto a devolução está em curso (ou refund/devolvida continuam possíveis).  
**Obtido:** `concluido` 200; seller travado; captura 590¢ viva.

---

### P2 · AR5-unship-silent-200

**Lentes:** AR5  
**Actor:** buyer JWT e seller JWT

**O quê:** Depois de `enviado` (`shipped_at` selado), `PATCH shipped_at=null` devolve **HTTP 200** com a row. O valor na BD **não muda**. `refund-order` continua **403** `order_refund_blocked_shipped`.

**Não é** AL5-cancel-silent-200 (coluna e estado diferentes; AHAM já deu 403 em `cancelado`).

**Prova (pass2):** order `5f875635-…` · `before` = `after` = `2026-09-02T09:18:33.648927+00:00` · HTTP 200 buyer e seller · refund 403.

**Esperado:** 403 / 0 rows quando o selo V-P0 recusa unship.  
**Obtido:** 200 representação inalterada.

---

### P3 · AR1-idempotency-prefix-64

**Lentes:** AR1  
**Actor:** seller JWT

**O quê:** A Edge faz `idempotency_key.slice(0, 64)` **antes** do débito. Duas keys distintas no cliente (`'K'*64+'alphaAR1'` vs `'K'*64+'betaAR1x'`) colidem. Uma Transfer `tr_1UBAJZH7FWYUN3jhPgfAqD56`, a segunda `idempotent: true`. Não duplica dinheiro; funde duas intenções.

**Não é** payout idempotency clássico (replay da **mesma** key+montante — esse continua a fechar: 3× // → 1 `tr_1UBAJdH7…`).

**Prova (pass2):** `sameTid: true` · saldo 27,97 € após 100¢ (um débito, não dois).

--------------------------------------------------
## LENTES (esperado vs obtido)
--------------------------------------------------

### AR1 · Payout JWT/Edge hostil · replay idempotency

| Ataque | Obtido |
|--------|--------|
| JWT `payout_debit` / `finish` / `clawback` / `credit` / `finalize` | **403** 42501 |
| JWT `refund_buyer_wallet` / `process_partial` | **200 false** |
| JWT `order_allows_seller_stripe_refund` | **403** |
| PATCH `wallets.balance` / mass `id=in.(B,S)` | **200 []** |
| INSERT `wallet_transactions` | **403** RLS |
| GraphQL `updatewalletsCollection` | 200 `pg_graphql extension is not enabled` |
| Header `Stripe-Account: acct_evil` | onboarding na conta **do JWT** `acct_1U5mYbQeUNx8ar08` |
| PUT sem amount | 200 AccountLink, **sem** Transfer |
| GET `refund-order` | **405** |
| `amount:[100]` | Transfer 100¢ (`Number([100])===100`) — coerção, **não** finding |
| Prefixo 64 chars, 2 keys | **1** Transfer (P3) |
| 3× mesma key // | **1** `tr_1UBAJdH7FWYUN3jhRa1GSVON` |
| crash `after_stripe_before_finish` + retry **mesma** key | mesmo `tr_1UBAJgH7FWYUN3jhdlvyKHFk` |
| crash + **key nova** | 2.ª Transfer 100¢ (2.º levantamento, saldo cobria) — esperado |

### AR2 · Connect return hijack

| Ataque | Obtido |
|--------|--------|
| trailing-dot / CRLF / cyrillic / IPv6 / `fleaber://` / `data:` | HTML 200 **sem** Location hostil |
| `https://fleaber.pt%2f%40evil.com` | **303** `https://fleaber.pt/wallet` (path `@evil` descartado) |
| `X-Forwarded-Host: evil.com` | Cloudflare **403** (não chega à Edge) |
| POST `return_url`/`refresh_url`/`web_return_origin` evil | AccountLink Stripe **sem** `evil.com` |
| POST `user_id`=seller2 (buyer JWT) | **400** `Cannot create another user Stripe account.` |

### AR3 · Release + refund + clawback = líquido

Venda `ab16405d-…` PI `pi_3UBAJtH7…` captura **590¢**. Buyer `concluido` + release JWT → seller **+5,00 €**. Payout 100¢ `tr_1UBAJxH7…`. `pedido_devolucao` **403** `order_return_after_release_denied`. Disputa pós-release **403** RLS. `refund-order` **403** `order_refund_blocked_status`. Clawback JWT **403**. Δbuyer **0**.

Hop `devolvida` **sem** refund: Δbuyer **0** (anti mint I-P0). Depois refund-order (AHAM) → `re_3UBAJlH7…` 590¢, status `cancelado`, **sem** crédito wallet extra.

### AR4 · Transfer duplicado / webhook replay

- `transfer.created` / `payout.paid` / `charge.refunded` / `account.updated` com `stripe-signature` lixo → **400** `invalid_signature`.
- S2 + `user_id` S1 → **400** (não herda Transfer; S2 sem IBAN).
- Ledger `debited` órfão desta ronda: keys `p2payout-a/b-1788096926564-*` **pré-existentes** (não criadas AR) — observação, não finding.

### AR5 · Seller refund após release · parcial > captura · devolvida gate

- `refund-order` em **enviado** (mesmo após PATCH `shipped_at=null` 200) → **403** shipped.
- Hop JWT até `devolvida`: qty **0→0**, `stock_units_applied` **1**, `stripe_refund_id` null — **AHAM stock hold**.
- `refund-order` em `devolvida`+`shipped_at` → **200** `re_3UBAJlH7FWYUN3jh137uYpB4` 590¢ — **AHAM gate terminal**.
- Body `amount`/`reverse_transfer`/`refund_application_fee` ignorados; autoridade = `amount_paid_cents`.

### AR6 · Buyer força refund alheio · cancel pós-pago

- `PATCH cancelado` em **pago** e **concluido** → **403** `order_cancel_denied_post_pay` — **AHAM**, não 200 silencioso AL5.
- Mass `id=in.(order, dummy)` cancelado → **403**.
- Buyer / buyer2 `refund-order` → **403** Sem permissão.
- `finalize` JWT `re_AR_forged` → **403**.
- 2× `refund-order` // : um 200 (já `already_refunded` no selo cedo), outro 500 idempotency Stripe in-progress; `refund_count=1`.

### AR7 · Composição até Δwallet / Stripe net

Buyer início **61,10 €** · fim pass3 **61,10 €**. Seller: payouts TEST 100¢ (prefixo, tri, crash+new, pós-release) + release +5,00 € da venda `ab16405d-…`. Sem mint comprador. Sem coexistência Transfer desta venda + refund Stripe no **mesmo** `order_id` com Δbuyer>0.

Race devolvida ∥ concluido: ver P1.

GET cruzado wallets/ledger: **[]**.

--------------------------------------------------
## Fechos AHAM (controlo, não findings)
--------------------------------------------------

| Fecho | Prova |
|-------|--------|
| cancel pós-pago → 403 | `e521deb3-…` pago e concluido → `order_cancel_denied_post_pay` |
| stock `devolvida` só se off-platform ou já `stripe_refund_id` | `d5d606f0-…` qty 0, applied 1, rid null |
| restore quando refund chega | mesmo pedido, após `re_3UBAJlH7…`, `stock_units_applied` null |
| refund gate `devolvida` **antes** de `shipped_at` | 200 Stripe com `shipped_at` selado |

--------------------------------------------------
## Transfers / refunds Stripe TEST (observação)
--------------------------------------------------

Conta Connect seller `acct_1U5mYbQeUNx8ar08`. Desta ronda (100¢ salvo indicação):  
`tr_1UBAI2H7FWYUN3jhIKgecViO` (pass1 abort PUT/header, 100¢), `tr_1UBAI4H7FWYUN3jhnAgPnnXc` (PUT **com** amount no 1.º abort — 100¢), `tr_1UBAIoH7FWYUN3jhDIxyF822` (`amount:[100]`), `tr_1UBAJZH7FWYUN3jhPgfAqD56` (prefixo 64), `tr_1UBAJdH7FWYUN3jhRa1GSVON` (tri same-key), `tr_1UBAJgH7FWYUN3jhdlvyKHFk` (crash), `tr_1UBAJiH7FWYUN3jhA2qeLtti` (key nova pós-crash), `tr_1UBAJxH7FWYUN3jhp3TB5U2c` (pós-release).

Refunds: `re_3UBAJTH7FWYUN3jh1kTUW2MW` (parallel pago), `re_3UBAJlH7FWYUN3jh137uYpB4` (devolvida terminal).

--------------------------------------------------
## Anti-atrofia
--------------------------------------------------

Exercício: Stripe TEST pago → release → Transfer; refund em `pago` //; refund em `devolvida`+shipped; JWT hostil; `Stripe-Account` / origens IDN/CRLF/IPv6; prefixo 64; 3× same key; crash+retry; unship; cancel 403; B2 refund; race devolvida∥concluido; GraphQL; mass PATCH.  
0/3 findings na lista exacta AL/I (cancel silent 200 · dual Session · payout idempotency clássico · review 5★ · mint pós-payout).

`amount:[100]` **não** entra na CONTAGEM (mesma `Number()` que `amount="100"` já notada em AL, sem cêntimo extra).

--------------------------------------------------
## Notas (não HOLD)
--------------------------------------------------

- Flutter gera `wd_{uuid}_{cents}_{ms}` ≤64 chars no uso normal; o P3 só pega em cliente hostil com keys longas colidentes.
- Crash inject exige secret de staging; a app guarda a key no retry (`needs_reconcile`). Key **nova** após 500 = 2.º levantamento se o saldo cobrir — não é o mesmo cêntimo.
- GET Connect origem recusada = HTML 200 (nota R/AL).
- S2 sem IBAN: `user_id` cruzado cai em 400 antes de `idempotency_key_foreign`.
- Ledger `debited` órfão `p2payout-a/b-*` não é desta ronda.
