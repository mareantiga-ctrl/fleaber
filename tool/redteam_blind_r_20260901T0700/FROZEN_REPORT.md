# FROZEN_REPORT — REDTEAM_BLIND_R_CONNECT_PAYOUT_v1

```
AUDITOR: REDTEAM_BLIND_R_CONNECT_PAYOUT_v1
FROZEN_AT: 2026-09-01T06:09:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [R1, R2, R3, R4, R5, R6, R7, R8]
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors: anon, buyer JWT `bfcbeeee-…`, seller JWT `980f4fa1-…`, 2.º buyer `fcb84316-…`, 2.º seller `f54fd65e-…`.  
`service_role` só fixture / observação. Prefixo `RTR-20260901T0700`.  
Provas: `probe.json`, `pass2.json`, `pass3.json`. Repro: `dart run tool/redteam_blind_r_20260901T0700/probe.dart` (+ `pass2.dart`, `pass3.dart`).

**Missão.** Consigo levantar, manter, ou duplicar dinheiro na carteira / Connect depois de venda, refund, disputa ou cancelamento?

**Resposta.** Não neste poço. Venda Stripe TEST até release e Transfer Connect reais; refund, disputa parcial, races e JWT hostil recusam ou fecham o ledger. Último ciclo sem classe nova P0/P1.

Não é ATROFIA_ABORT (não se parou em wallet INSERT anon / preço Session body / oversell última unidade / mint `devolvida` sem Stripe / tip mismatch / review 5★).

--------------------------------------------------
## Findings P0/P1
--------------------------------------------------

Nenhum confirmado.

`probe.json` chegou a emitir `RTR-R6-double-transfer` (duas Transfers em paralelo). **Retratado:** cada pedido era 5,00 € sobre saldo 15,00 € (10,00 pré-existente + 5,00 do release) — dois levantamentos legítimos, não duplicação do mesmo cêntimo. Reteste do saldo **inteiro** (pass2): 1 Transfer `tr_1UAkqlH7FWYUN3jhsn013sZn` + 2× `Saldo disponível insuficiente`.

--------------------------------------------------
## Lentes (esperado vs obtido)
--------------------------------------------------

### R1 · Release → payout → refund buyer

Venda `eda407f7-…` PI `pi_3UAknuH7FWYUN3jh1wNbHJ63` captura **590¢**. Buyer confirma mão → `batata_release_seller_wallet_for_order` **true**, seller **+5,00 €** (5,90 − comissão). 2.ª chamada / seller / buyer2 → **false**.

`refund-order` pós-concluido: seller **403** `order_refund_blocked_status`; buyer/B2 **403** Sem permissão. PATCH `devolvida` JWT: status permanece `concluido`. Após Transfer, o mesmo 403. Sem coexistência Transfer + `stripe_refund_id` no mesmo pedido.

### R2 · Refund-order pós-release / clawback / drain

JWT `batata_clawback_seller_wallet_for_order` / `batata_credit_wallet_once` / `batata_wallet_payout_debit` / `finish`: **403/401** permission denied.  
`refund_buyer_wallet` em concluido: **false**.  
Após payout total (saldo 0, Transfer `tr_1UAkr9H7FWYUN3jhvdwA2eL2`): PATCH `cancelado` JWT não muda o estado; refund-order **403**; refund-wallet **false**; Δbuyer/Δseller **0**. Clawback fail-closed — sem mint comprador quando o vendedor já tirou o dinheiro.

Caminho **legítimo** não partido: `refund-order` em `pago` (`2fd6072b-…` / `pi_3UAkoJH7FWYUN3jh0ix74NbS`) → **200** `re_3UAkoJH7FWYUN3jh0HrJByNE`, 590¢, status `cancelado`.

### R3 · Partial dispute wallet

Disputa **depois** do release: INSERT **403** RLS (`wallet_release_processed_at` tem de ser null).  
Disputa **antes** do release (`846f5316-…`): INSERT **201**. Oferta 40% → `process_partial` **true**. Ledger: buyer **+2,36 €** reembolso + seller **+2,64 €** residual = **5,00 €** sobre captura **5,90 €** (0,90 € comissão plataforma). Release posterior **false**. 2.º comprador na mesma disputa: **409** `dispute_already_exists_for_order` (não abriu linha alheia).

Oferta **100%** plataforma (`c3002ead-…`): **403** `dispute_full_refund_requires_stripe`. Δwallet **0**. Sem mint de reembolso total em carteira.

### R4 · Cancel ∥ release

`Future.wait` `refund-order` ∥ `PATCH concluido` + release (`a4370d90-…` / `pi_3UAknoH7FWYUN3jh0H18da9W`): refund **200** `re_3UAknoH7FWYUN3jh0jB0cbQZ`; release **false**; Δwallet **0**; status `cancelado`; flags release+refund gravados como selo anti-mint.

`Future.wait` disputa INSERT ∥ release (`ddb3d2d3-…`): disputa **201**, release **false**, Δseller **0**, `wallet_release_processed_at` continua null (disputa aberta bloqueia libertação).

### R5 · Connect onboarding

| Ataque | Obtido |
|--------|--------|
| GET `web_return_origin=https://evil.com` | **200** HTML da Edge, **sem** Location hostil |
| GET `fleaber.pt.evil.com` | **200** sem Location hostil |
| GET `javascript:alert(1)` | **403** |
| GET origem `fleaber.pt` | **303** `https://fleaber.pt/wallet` |
| POST `user_id` = seller (buyer / seller2) | **400** `Cannot create another user Stripe account.` |
| Webhook `payout.paid` / `transfer.created` sem assinatura | **400** `missing_signature` |

Sem open redirect, sem takeover de conta Connect.

### R6 · Payout idempotency

- RPC debit/finish JWT: **403**. PATCH `wallets.balance` / `stripe_account_id`: **200 []**. INSERT `wallet_transactions` / `wallet_payout_ledger`: **403** RLS.
- Replay da mesma key: **200** `idempotent: true`, mesmo `transferId`.
- 3× saldo inteiro (10,00 €) keys distintas: **1** Transfer + **2×** insufficient.
- Sem key / negativo / acima do saldo: **400**.
- `crash_inject` sem segredo: **ignorado** (payout normal 1,00 €, sem `needs_reconcile`).
- Seller2 a reutilizar key do seller1: falha no Connect (conta bancária em falta) **antes** do débito — não herda Transfer alheia.

### R7 · MB WAY vs Seguro

Order `298af234-…` MB WAY, seller `pago`, buyer `concluido`, release **true** mas Δwallet **0** (`amount_paid_cents` null). `refund-order` **403** pelo estado concluido (não cria refund Stripe). Off-platform não alimenta carteira de plataforma.

### R8 · Composição venda → release → payout → disputa → refund

Na venda já libertada e (parcialmente) levantada: disputa **403**; parcial **400** `dispute_refund_offer_required`; refund-order **403**. Sem Transfer + refund Stripe no mesmo `order_id`. Cadeia pára no segundo elo.

--------------------------------------------------
## Transfers Stripe TEST (observação)
--------------------------------------------------

Conta Connect seller `acct_1U5mYbQeUNx8ar08`. Transfers desta ronda (não são findings):  
`tr_1UAko4H7FWYUN3jhnUBXobRU`, `tr_1UAko4H7FWYUN3jh1Xk0SAib`, `tr_1UAkoAH7FWYUN3jhRAadqhkW`, `tr_1UAkqlH7FWYUN3jhsn013sZn`, `tr_1UAkr9H7FWYUN3jhvdwA2eL2`, `tr_1UAksTH7FWYUN3jhQfYs5F4h`.

--------------------------------------------------
## Anti-atrofia
--------------------------------------------------

Exercício: Stripe TEST até release + Transfer; ledger buyer/seller/`wallet_transactions`/PI/refund; races payout, refund∥release, disputa∥release; drain pós-release; refund-order legítimo em `pago` intacto.  
Não se parou nas classes proibidas do prompt.

--------------------------------------------------
## Notas (não HOLD)
--------------------------------------------------

- GET Connect com origem recusada devolve HTML 200 em vez de 403 — não redirecciona para hostil.
- Seller2 sem IBAN Connect não chega ao check `idempotency_key_foreign` no Edge; o RPC debit continua `service_role` only.
- `crash_inject` de payout só com secret de staging + `sk_test_` (não exercitado com secret; sem secret não arma).
