# FROZEN REPORT — RED TEAM CEGO AL
## Auditor independente · PÓS-FECHO AEAFAG · PAYOUT / WALLET / REFUND · v1

## CONTAGEM

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: NÃO          → quantos: 0
P4 aberto: NÃO          → quantos: 0  (fora de âmbito salvo pedido)
```

```
AUDITOR: REDTEAM_BLIND_AL_PAYOUT_POS_AEAFAG_v1
FROZEN_AT: 2026-09-02T07:50:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [AL1, AL2, AL3, AL4, AL5, AL6, AL7]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors JWT buyer `bfcbeeee-…` · seller `980f4fa1-…` · buyer2 `RTAL-…-b2` · seller2 `RTAL-…-s2`.  
`service_role` só fixture (`setup_paid_order`, `shipping_method` mão, observação). Prefixo `RTAL-20260902T0730-`.  
Provas: `pass1.json`, `pass2.json`, `pass3.json`. Repro: `dart run tool/redteam_blind_al_20260902T0730/probe.dart` (+ `pass2.dart`, `pass3.dart`).

**Missão.** O dinheiro que já está (ou parece estar) na carteira / Connect — consigo tirá-lo duas vezes, para a conta errada, ou sem direito?

**Resposta.** Não neste poço: débito/finish/finalize JWT 403; Connect `user_id` cruzado 400; `destination` no body ignorado; mesma key com amount maior idempotente; webhooks Transfer sem assinatura 400; refund-order só do vendedor e bloqueado em enviado/concluido; chat cancel exige refund Stripe; parcial de plataforma capturada agora recusa mint wallet (`dispute_partial_refund_requires_stripe`). Contabilidade buyer Δ **0,00 €**. Um P2 de higiene no PATCH `cancelado`.

Não é ATROFIA_ABORT (0/1 achados = dual Session / bag unlist / cancel hold / review 5★ / payout idempotency clássico).

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — NÃO
8. Quantos P3: 0
9. Buyer manipula preço autoritativo — NÃO (fora do poço payout; não re-provado)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`debit`/`credit`/`finalize` 403; `refund_buyer_wallet` 200 false; PATCH `wallets.balance` 200 [])
13. Refund excede captura — NÃO (`body.amount=99999` ignorado; refund 590¢ = `amount_paid_cents`)
14. Release+refund cria dinheiro líquido — NÃO (refund-order 403 em concluido; Δbuyer 0; race: refund perde, release +5,00 € seller, PI sem refund)
15. Payout duplica Transfer — NÃO (mesma key + amount 500 → `idempotent` mesmo `transferId`; 2 keys // = 2 levantamentos de 100¢ sobre saldo que cobria)
16. Stock=1 duas vendas válidas — NÃO COMPROVADO (fora da lente)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO COMPROVADO
19. Cross-user financeiro — NÃO (buyer Connect do seller 400; B2 disputa 403 RLS; B2 `process_partial` `not_allowed`; B2 refund-order 403)
20. Cross-user dados sensíveis — NÃO (GET `wallets`/`wallet_payout_ledger` seller → 200 [])
21. Buyer assume seller/admin — NÃO
22. Seller assume buyer/admin — NÃO
23. Reviews forjadas — NÃO (não exercitado; classe atrofia)
24. RPC SECURITY DEFINER perigoso executável — NÃO (`payout_debit`/`finish`/`finalize`/`clawback`/`credit` 42501). `refund_buyer_wallet` e `process_partial` são executáveis por JWT mas fail-closed (`false` / `dispute_*_requires_stripe` / `not_allowed`)
25. RLS crítico quebrado — NÃO (INSERT txn/ledger 403; PATCH Connect id 200 [])
26. Edge confia total do cliente — NÃO (`destination`/`return_url` no body ignorados; amount ≤0 / 5.90 recusados; `crash_inject` sem secret ignorado)
27. Regressão funcional (happy path partido) — NÃO (refund-order em `pago` 200; release buyer JWT `true`; payout 100¢ Transfer real)
28. Saturação atingida — NÃO (P2 aberto; seller2 sem IBAN não chega a `idempotency_key_foreign`; Stripe retrieve Transfer sem `sk_test_` local)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## ACHADO
--------------------------------------------------

### P2 · AL5-cancel-silent-200

**Lentes:** AL5  
**Actor:** buyer JWT

**O quê:** Depois de `concluido` (entrega em mão), `PATCH orders status=cancelado` devolve **HTTP 200** com representação da linha. O estado na BD e no body continua **`concluido`**. Não minta carteira, não cria `stripe_refund_id`, não anula o PI.

**Não é** cancel-hold de stock, dual Session, nem mint `devolvida`.

**Prova (pass2):** order `2fea95a5-…` · PI `pi_3UB7rUH7FWYUN3jh1tIY5lC3` · `status` GET = `concluido` · `bodyStatus` = `concluido` · HTTP 200 com 1 row.

**Esperado:** 403 / 200 com 0 rows quando o fecho AEAFAG recusa `cancelado` pós-pago.  
**Obtido:** 200 com a row inalterada — cliente que só olha ao HTTP pode achar que cancelou.

--------------------------------------------------
## LENTES (esperado vs obtido)
--------------------------------------------------

### AL1 · Payout / `wallet_payout_debit` JWT ou Edge hostil

| Ataque | Obtido |
|--------|--------|
| JWT `batata_wallet_payout_debit` / `finish` / `clawback` / `credit_wallet_once` / `finalize_stripe_order_refund` | **403** 42501 |
| JWT `batata_refund_buyer_wallet_for_order` (uuid dummy e order concluida) | **200 false** |
| JWT `batata_ensure_wallet` p_user_id=seller | **403**; Δseller 0 |
| PATCH `wallets.balance=9999.99` | **200 []**; saldo inalterado |
| INSERT `wallet_transactions` / `wallet_payout_ledger` | **403** RLS |
| Edge `amount=-100` / `0` / `5.90` | **400** |
| Edge `amount="100"` (string) | **200** Transfer 100¢ (coerção para inteiro) |
| Edge `amount="1e2"` | **200** Transfer 100¢ (`Number("1e2")===100`) |
| Edge `amount=2147483647` | **400** insufficient_balance |
| `crash_inject` sem secret | payout **normal** 100¢, sem `needs_reconcile` |

### AL2 · Connect return_url / onboarding hijack

| Ataque | Obtido |
|--------|--------|
| GET `web_return_origin=https://evil.com` (e variantes fleaber.pt.evil, javascript:, userinfo) | **200** HTML da Edge **sem** Location hostil; corpo sem `evil.com` |
| GET `https://fleaber.pt` / `www` | **303** `{origin}/wallet` (query `next=` descartada) |
| GET `http://127.0.0.1` / `localhost` | **303** loopback `/wallet` — allowlist de dev; **sem** tokens; nota, não finding |
| POST `user_id`=seller (buyer JWT) | **400** `Cannot create another user Stripe account.` |
| POST payout `destination`/`stripe_account_id`/`return_url` hostis | **200** Transfer na conta Connect **do JWT** (`acct_1U5mYbQeUNx8ar08`); body ignorado |
| PATCH `wallets.stripe_account_id` | **200 []** |

### AL3 · Release + refund + clawback = líquido

Venda `b2a1c4ed-…` PI `pi_3UB7nEH7FWYUN3jh1l4Y53lt` captura **590¢**. Buyer `concluido` + `batata_release_seller_wallet_for_order` JWT → **true**, seller **+5,00 €**. 2.ª chamada / buyer2 → **false**. Disputa pós-release **403** RLS. `refund-order` **403** `order_refund_blocked_status`. PATCH `devolvida` seller **403** `order_concluido_immutable_for_seller`. Clawback JWT **403**. `refund_buyer_wallet` **false**. Δbuyer **0**.

Parcial pré-release (pass2, vs R que mintava 40% em wallet): oferta 200% → **403** `dispute_full_refund_requires_stripe`; oferta 40% → **403** `dispute_partial_refund_requires_stripe`; Δ **0**. Residual `finalize refund` / parcial plataforma **fechado** (não é o mint I-P0).

### AL4 · Transfer duplicado / replay webhook

- Webhook `transfer.created` / `payout.paid` / `charge.refunded` / `account.updated` sem assinatura → **400** `missing_signature`.
- Replay mesma key com **amount 500** → **200** `idempotent: true`, mesmo `tr_1UB7nKH7FWYUN3jhdT2MqTd0` (não é o replay clássico do mesmo montante; variante nova).
- 2 keys // 100¢ com saldo ≥2,00 € → **2** Transfers (`tr_1UB7nPH7…sK5J5n2l`, `tr_1UB7nPH7…M7nmfg5z`) — dois levantamentos legítimos, não o mesmo cêntimo.
- Seller2 reusa key do seller1 → **400** falta IBAN Connect (não herda Transfer).
- Ledger `debited` órfão: **[]**.

### AL5 · Seller refund após release

`refund-order` em **concluido** e em **enviado** → **403** (`order_refund_blocked_status` / `order_refund_blocked_shipped`). Chat `cancel_request_outcome` sem `stripe_refund_id` → **400** `chat_system_card_cancel_not_refunded`. Happy path: refund em **pago** `e7604510-…` / `4532a7a4-…` → **200** `re_3UB7n7…` / `re_3UB7nc…`, 590¢, `cancelado`.

### AL6 · Buyer força reembolso alheio / parcial > captura

Buyer / buyer2 `refund-order` → **403** Sem permissão. `finalize` JWT com refund inventado ou `re_` de outro pedido → **403**. PATCH `stripe_refund_id` → **403** `order_money_fields_immutable`. Buyer2 disputa limpa → **403** RLS. Buyer2 `process_partial` → **403** `not_allowed`. Buyer PATCH oferta `seller_refund_percent=40` + `seller_offer_set_by=seller` → 200 representação mas `process_partial` **400** `dispute_refund_offer_required` (colunas de oferta não selam como oferta do vendedor). Δbuyer **0**.

### AL7 · Composição até Stripe net / wallet Δ

Race `refund-order` ∥ `PATCH concluido` (`d292b316-…` / `pi_3UB7rNH7FWYUN3jh0SgPeSBm`): refund **403** (concluido ganhou); release **+5,00 €** seller; Δbuyer **0**; PI **sem** `stripe_refund_id`. Sem coexistência Transfer desta venda + refund Stripe no mesmo `order_id`.

Buyer wallet início **61,10 €** · fim pass3 **61,10 €**. Seller: payouts TEST reais (não drenámos o saldo inteiro). Sem mint comprador sem PI refundido.

--------------------------------------------------
## Transfers Stripe TEST (observação, não findings)
--------------------------------------------------

Conta Connect seller `acct_1U5mYbQeUNx8ar08`. Desta ronda (100¢ cada, salvo indicação):  
`tr_1UB7n4H7FWYUN3jhhGwUl9H6` (body `destination` hostil **ignorado**), `tr_1UB7nKH7FWYUN3jhdT2MqTd0`, `tr_1UB7nPH7FWYUN3jhsK5J5n2l`, `tr_1UB7nPH7FWYUN3jhM7nmfg5z`, `tr_1UB7nSH7FWYUN3jhwcuc4MVO`, `tr_1UB7nVH7FWYUN3jhFEh8Ggwr`, `tr_1UB7raH7FWYUN3jhfr8exIch` (`amount="1e2"` → 100¢).

Refunds: `re_3UB7n7H7FWYUN3jh1ihnoCtX`, `re_3UB7ncH7FWYUN3jh0n7EtOKb`.

--------------------------------------------------
## Anti-atrofia
--------------------------------------------------

Exercício: Stripe TEST pago → release → Transfer; refund em `pago`; refund bloqueado após enviado/concluido; JWT hostil em RPC de saída; `destination` / `user_id` cruzado; mesma key amount≠; 2 keys //; webhooks unsigned; disputa 200%/40% pós-fecho parcial-Stripe; race refund∥release; chat cancel; oferta forjada; B2 disputa.  
0/1 findings na lista exacta dual Session · bag unlist · cancel hold · review 5★ · payout idempotency clássico (replay da **mesma** key+montante). A variante same-key **amount maior** foi tentada e fechou idempotente.

--------------------------------------------------
## Notas (não HOLD)
--------------------------------------------------

- Primeiro `refund-order` feliz devolve `already_refunded: true` porque o Edge sela `stripe_refund_id` **antes** do finalize — flag de retry no happy path; o PI foi reembolsado 590¢.
- GET Connect origem recusada = HTML 200 (não 403), igual à nota R; não redirecciona.
- `http://127.0.0.1` está na allowlist de `web_return_origin` → 303 `/wallet` sem query. Desenho web local, sem segredo na Location.
- Seller2 sem IBAN não exercita `idempotency_key_foreign` no Edge.
- `process_partial` em captura Stripe **já não minta wallet** (R mintava 40%). Fecho residual pré-Fase 4 confirmado no poço AL.
- I-P0 (`devolvida` mint buyer após payout total, clawback clamp 0) **não** reproduzível por JWT: `devolvida` bloqueada; `refund_buyer_wallet` exige `devolvida` e, em plataforma capturada sem `stripe_refund_id`, não minta.
