# FROZEN_REPORT — RED TEAM CEGO I (SAÍDA DE DINHEIRO / CONNECT / PAYOUT)

```
AUDITOR: REDTEAM_BLIND_I_SAIDA_DINHEIRO_v1
FROZEN_AT: 2026-08-31T16:20:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [I1, I2, I3, I4, I5, I6, I7]
VEREDICTO: FAIL_P0
prefixo_fixtures: RTI-20260831T1706-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**

Provas em `tool/redteam_blind_i_20260831T1706/pass{1,2,3,4,5}.json`.

Anti-atrofia: Pass 1 **não** repetiu dual Session, bag unlist, cancel hold, nem review 5★. 0% dessas classes.

---

## Veredicto

A fronteira JWT / Edge de **levantamento** aguenta o ataque clássico: débito e finish só `service_role`, `user_id` cruzado recusado, amount inválido recusado, `stripe_account_id` imutável pelo cliente, refund-order só do vendedor e bloqueado após envio, webhooks Transfer sem assinatura mortos, idempotência da mesma key (incluindo crash inject) devolve o **mesmo** `transferId`.

Falham o **líquido depois do dinheiro já ter saído**:

1. **P0** — o vendedor com Connect pronto levanta **todo** o saldo (Stripe Transfer TEST real). Depois `devolvida` **minta** a carteira do comprador (5,90 €), **não** cria refund do PaymentIntent, e o clawback **escreve estorno de 5,00 € no livro com a carteira a 0,00 €** (`greatest(saldo − montante, 0)`).
2. **P1** — o mesmo mecanismo com carteira já a zero (seller2 sem IBAN; drain por fixture). Confirma que o clamp não depende do Connect.

Não é a classe saturada (dual Session / offer / tip / invite).

---

## Contabilidade (Stripe TEST)

| Momento | Wallet buyer | Wallet seller (Connect pronto) |
|---------|--------------|--------------------------------|
| Início pass1 | 22,75 € | 244,60 € |
| Após pass3 (payout 5,00 € + clawback com pool) | 28,65 € | 246,10 € |
| **Fim pass5 (payout total 256,10 €)** | **40,45 €** | **0,00 €** |

PI TEST (captura 590¢, **nenhum** `stripe_refund_id` nas orders `devolvida` deste ciclo):

- `pi_3UAXshH7FWYUN3jh0ulq5U7j` · order `207d5aff-…` (pass3)
- `pi_3UAXvSH7FWYUN3jh1uAUjhTD` · order `ff185820-…` (pass5 seller2)
- `pi_3UAXvaH7FWYUN3jh1Us2Ysr1` · order `7a02b4e4-…` (**P0**)

Transfer Connect (seller `acct_1U5mYbQeUNx8ar08`):

- `tr_1UAXrgH7FWYUN3jh2dHNzA5R` 100¢ (mesma key ∥ — **um** id)
- `tr_1UAXrjH7FWYUN3jhQcqFID0o` / `tr_1UAXrjH7FWYUN3jhLk2r0a0u` 100¢+100¢ (keys distintas, saldo cobria)
- `tr_1UAXrqH7FWYUN3jh0AyGSNxJ` 50¢ (retry pós `crash_inject`)
- `tr_1UAXsoH7FWYUN3jhk50TAQfF` 500¢ (pass3, só o release)
- **`tr_1UAXviH7FWYUN3jhsgouM4qN` 25610¢** (pass5, saldo inteiro → 0)

A carteira do vendedor de staging ficou a **0,00 €**. Não foi restabelecida (seria mint em cima do Transfer).

---

## Findings

### RTI-I3-008 · I3 / I7 · P0

**Título:** Levantamento total para Connect + `devolvida` minta o comprador; o PI não é reembolsado; o clawback clampa a zero.

**Actor:** vendedor JWT (`create-connect-account`) + caminho `devolvida` (aqui `service_role`, o mesmo trigger que um fecho de disputa/admin).

**Passos**
1. Fixture Stripe TEST `setup_paid_order` → `pago` (590¢) · order `7a02b4e4-43e5-46de-9e36-68843493f25b`.
2. Vendedor `enviado` → comprador `concluido`. Comprador JWT `batata_release_seller_wallet_for_order` → **+5,00 €** venda (taxa 0,90 €). Saldo 251,10 → 256,10 €.
3. `POST create-connect-account` `amount=25610` `idempotency_key` nova → **200** `transferId=tr_1UAXviH7FWYUN3jhsgouM4qN`, `balance=0`.
4. `PATCH orders status=devolvida`.

**Esperado:** ou o Transfer é revertido / a carteira fica negativa / o comprador **não** recebe wallet se o PI continua capturado; ou o PI é refundido **e** o vendedor é cobrado de verdade.

**Obtido**
- Buyer wallet +5,90 € (`reembolso`, txn `88d29e0a-…`)
- Seller wallet **0,00 €** (inalterado pelo clawback)
- Livro: `venda` 5,00 € + `estorno` 5,00 € (txn `c13031df-…`) — o estorno **não moveu saldo**
- `stripe_refund_id` = **null** · PI `pi_3UAXvaH7FWYUN3jh1Us2Ysr1` continua capturado
- Connect: +256,10 € TEST (inclui os 5,00 € desta venda)

**Líquido desta encomenda:** plataforma ficou com o PI (5,90 €) **e** já enviou ~5,00 € no Transfer **e** passou a dever 5,90 € ao comprador em carteira. O clawback mentiu no livro.

**Prova:** `pass5.json` `full_drain_books` + finding `RTI-I3-008`.

**Porquê P0:** dinheiro TEST **saiu** para Connect; o reembolso interno não o recupera e cria um segundo passivo. Em produção o vendedor levanta e desaparece.

---

### RTI-I3-007 · I3 · P1

**Título:** Mesmo clamp com carteira vazia (seller2 sem IBAN).

**Actor:** buyer JWT release + fixture `balance=0` (Connect seller2: «Falta associar a conta bancária») + `devolvida`.

**Passos**
1. `setup_paid_order` `seller_id=seller2` · PI `pi_3UAXvSH7FWYUN3jh1uAUjhTD` · order `ff185820-…`.
2. Release +5,00 € (0 → 5,00). Payout Edge **400** (sem IBAN).
3. Fixture `PATCH wallets balance=0`. `devolvida`.

**Obtido:** buyer +5,90 €; seller2 0,00 €; estorno 5,00 € no livro; `stripe_refund_id` null.

**Porquê P1 e não P0:** o zero foi fixture (Connect não pronto). O mecanismo é o mesmo que I3-008. Prova: `pass5.json` `books`.

---

## Lentes — o que segurou

| Lente | Resultado | Prova |
|-------|-----------|--------|
| **I1** JWT `payout_debit` / `payout_finish` / `clawback` | 403 `42501` | pass1 |
| **I1** Edge `user_id` cruzado | 400 *Cannot create another user* | pass1 / pass4 |
| **I1** amount −500 / 5,90 / 999999999 / sem key | 400 | pass1 |
| **I1** PATCH `wallets.balance` / INSERT `wallet_payout_ledger` | `200 []` / 403 RLS | pass1 |
| **I1** crash `after_debit_before_stripe` + retry mesma key | 500 → 200 **mesmo** fluxo, 1 Transfer | pass2 |
| **I2** GET `web_return_origin=https://evil.com` | 200 HTML carteira, **sem** Location evil | pass1 / pass4 |
| **I2** POST origin hostil | AccountLink Stripe (`connect.stripe.com`), return_url na Edge | pass1 |
| **I2** PATCH `stripe_account_id` próprio ou alheio | `200 []` | pass1 |
| **I4** 2× mesma `idempotency_key` ∥ | **um** `tr_1UAXrg…` , 2.º 200 idempotente | pass2 |
| **I4** replay mesma key com amount maior | `idempotent: true`, amount original | pass2 |
| **I4** webhook `transfer.created` / `payout.paid` / `charge.refunded` forjado | 400 `invalid_signature` / `missing_signature`; Δwallet 0 | pass4 |
| **I5** `refund-order` após `concluido`+release | 403 `order_refund_blocked_status` | pass2 / pass3 |
| **I6** buyer / buyer2 / seller2 `refund-order` | 403 *Sem permissão* | pass1 |
| **I6** buyer2 `refund_buyer_wallet` | `false`; INSERT disputa oferta forjada 403 RLS | pass1 / pass3 |
| **I3** 2.º release / 2.º `refund_buyer_wallet` | `false`; sem segundo mint no replay | pass2 / pass3 |
| **I3** buyer2 release alheio; seller self-release | `false` | pass2 |

Contraste pass3 (ainda havia **pool** na carteira): payout só dos 5,00 € libertados (`tr_1UAXso…`); `devolvida` **conseguiu** debitar 5,00 € de outro saldo (251,10 → 246,10). O buraco só aparece quando o vendedor **já tirou tudo**.

---

## Notas de âmbito

- `devolvida` neste ciclo foi `service_role` (JWT comprador **não** inicia cadeia de devolução após release — isso é outra frente). O trigger `batata_wallet_order_status_trigger` corre na mesma quando o estado chega lá por disputa/admin.
- Flutter **não** é fronteira: o cliente manda cêntimos + `idempotency_key`; o P0 é Edge+SQL+Stripe.
- Seller2 criou conta Connect `acct_1UAXuBHqvLlXvegU` no onboarding (sem transfers active) — payout recusado como esperado.

---

## Veredicto final

**FAIL_P0** — I3-008 provado com Transfer Stripe TEST real e Δwallet fechado. I1/I2/I4/I5/I6 saturados em defesa neste ciclo; não reabrir JWT 403 de `payout_debit` como finding.
