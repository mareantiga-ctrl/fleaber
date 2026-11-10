# FROZEN_REPORT — REDTEAM_BLIND_BD_PAYOUT_POS_ANAS_v1

AUDITOR: REDTEAM_BLIND_BD_PAYOUT_POS_ANAS_v1
FROZEN_AT: 2026-09-02T16:16:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [BD1, BD2, BD3, BD4, BD5, BD6, BD7]
VEREDICTO: FAIL_P2

--------------------------------------------------
## CONTAGEM
--------------------------------------------------

```
P0 aberto: NÃO          → quantos: 0
P1 aberto: NÃO          → quantos: 0
P2 aberto: SIM          → quantos: 1
P3 aberto: SIM          → quantos: 2
P4 aberto: NÃO          → quantos: 0
TOTAL P0–P3 abertos: 3
```

**VEREDICTO:** P0–P1 fechados + P2 aberto → `FAIL_P2`.

Anti-atrofia: 0 achados = exactos AR/AL (JWT debit, prefixo-64, dual Session, review 5★). Relatório AX **não lido**. Variantes novas. Stripe TEST **pago** (vários PaymentIntents 5,90 €).

Falso-positivo pass1 `BD1-body-destination` **retirado**: extra `destination`/`currency` no body **não** foram honrados; a Transfer foi 100 ¢ para o Connect do JWT (saldo −1,00 €). Seller2 sem `acct_` — se o campo tivesse sido usado, a Transfer falharia.

--------------------------------------------------
## CHECKLIST
--------------------------------------------------

1. P0 dinheiro irreversível encontrado — NÃO
2. Quantos P0: 0
3. P1 caminho explorável encontrado — NÃO
4. Quantos P1: 0
5. P2 hygiene encontrado — SIM
6. Quantos P2: 1
7. P3 baixo risco encontrado — SIM
8. Quantos P3: 2
9. Buyer manipula preço autoritativo — NÃO (fora do poço payout; checkout não foi o alvo)
10. Buyer manipula qty autoritativa — NÃO
11. Seller falsifica pagamento plataforma — NÃO
12. JWT cria saldo/fundos — NÃO (`batata_credit_wallet_once` / debit / finish / clawback / finalize 403)
13. Refund excede captura — NÃO (extra `amount=99999` → `amount_cents:590`)
14. Release+refund cria dinheiro líquido — NÃO (ciclo limpo: release +5,00 €; refund pós-envio **403** `order_refund_blocked_shipped`; clawback N/A)
15. Payout duplica Transfer — NÃO (mesma key → mesmo `tr_…` + `idempotent:true`; 2× saldo inteiro → 1 Transfer + insufficient)
16. Stock=1 duas vendas válidas — NÃO COMPROVADO (fora do poço)
17. Stock=1 duas capturas líquidas permanentes — NÃO COMPROVADO
18. Bypass capacidade/reserva — NÃO COMPROVADO (fora do poço)
19. Cross-user financeiro — NÃO (`user_id` alheio 400; release buyer2 `false`; refund buyer2 403)
20. Cross-user dados sensíveis — NÃO (ledger seller2 `[]`)
21. Buyer assume seller/admin — NÃO (refund-order 403; payout buyer sem Connect)
22. Seller assume buyer/admin — NÃO (release seller `false`)
23. Reviews forjadas — NÃO (fora de âmbito)
24. RPC SECURITY DEFINER perigoso executável — NÃO (debit/finish/credit/clawback/finalize 403)
25. RLS crítico quebrado — NÃO (ledger INSERT 42501; wallets PATCH 0 rows; txn INSERT 403)
26. Edge confia total do cliente — NÃO (`destination`/`currency` ignorados; `crash_inject` sem secret ignorado)
27. Regressão funcional (happy path partido) — NÃO (código não alterado)
28. Saturação atingida — SIM (7/7 lentes; pass4 sem classe nova P0/P1)

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. FASE 4 NÃO INICIADA.**

--------------------------------------------------
## LENTES
--------------------------------------------------

| # | Lente (variante nova) |
|---|--------|
| BD1 | Destination / identidade: `user_id` alheio, PATCH `stripe_account_id`, amount hostil, campos extra destination/currency |
| BD2 | Ledger REST + mint RPC (INSERT ledger/txn, PATCH balance, credit/debit/finish/clawback/finalize JWT) |
| BD3 | Release mentiroso: freeze shipping, unship, concluido sem envio, seller/buyer2 release |
| BD4 | Refund mentiroso: extra amount, buyer/buyer2 refund-order, PATCH `stripe_refund_id` |
| BD5 | Connect bind / open-redirect `web_return_origin` |
| BD6 | Race keys distintas, overdraft 2× saldo, unicode/NUL key, crash_inject sem secret |
| BD7 | Composição pago→envio→release→payout→refund; return FSM; webhook sem assinatura |

--------------------------------------------------
## ÂMBITO E ACTORS
--------------------------------------------------

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · JWT buyer/seller + buyer2/seller2 (fixture admin) · `service_role` só fixture/observe.

Prefixo: `RTBD-20260902T1608`.

Probes: `tool/redteam_blind_bd_20260902T1608/` (`pass1`–`pass4`, `_rtbd.dart`).

Stripe TEST pago: `setup_paid_order` PI `pi_3UBFr0H7FWYUN3jh0J1kVODA`, `pi_3UBFrxH7FWYUN3jh1oaiVCXv`, `pi_3UBFsIH7FWYUN3jh0xQFAjim` (590 ¢ cada, `pm_card_visa`).

--------------------------------------------------
## ACHADO P2
--------------------------------------------------

### BD-P2-01 — Encomenda reembolsada no Stripe ainda vai a `enviado` / `concluido`

**Lente:** BD7 / BD4  
**Actor:** seller JWT (enviado) + buyer JWT (entregue/concluido)  
**Pre:** order `8e2e3644-9657-4dbd-8272-79e7df87fcf4` em `pago`; seller `refund-order` → PI `pi_3UBFr0H7FWYUN3jh0J1kVODA` refund `re_3UBFr0H7FWYUN3jh0eDahLKT` (590 ¢ = captura). Edge respondeu `status: cancelado`.  
**Repro:** após refund, `PATCH status=enviado` (seller) → `entregue` → `concluido` (buyer).  
**Esperado:** FSM recusar hop pós-reembolso (encomenda anulada).  
**Obtido:** `status=concluido`, `shipped_at` selado, `stripe_refund_id` preenchido, `wallet_release_processed_at` e `wallet_refund_processed_at` selados. Release RPC `false`, **Δwallet vendedor = 0**.  
**Impacto:** estado mente (venda «concluída» já estornada). Sem mint / sem 2.ª captura. Não é P0/P1.  
**Prova:** `pass2.json` `bd7.hop.row`.

--------------------------------------------------
## ACHADOS P3
--------------------------------------------------

### BD-P3-01 — `amount` string `"1e2"` coerção → 100 ¢ e Transfer

Edge faz `Number("1e2")` = 100 (inteiro). Levantamento legítimo de 1,00 € (`tr_1UBFqHH7FWYUN3jheQZjF5Mn`, saldo 33,97 → 32,97). Não é mint. Higiene de tipos (cliente pode pensar em euros).

### BD-P3-02 — `amount=1e21` → 400 `22P02` com `error: "[object Object]"`

Fail-closed (sem Transfer). Mensagem pública inútil. Sem dinheiro.

--------------------------------------------------
## HOLDS (prova LIVE)
--------------------------------------------------

**BD1** — `user_id` seller2 → 400 *Cannot create another user*. PATCH `wallets.stripe_account_id` próprio/alheio → 200 `[]` (valor inalterado). Amount 1.5 / −5 / 0 / 2147483647 recusados. Buyer payout sem IBAN. Anon `Invalid user`.

**BD2** — INSERT ledger/txn 403 RLS. PATCH balance 0 rows. RPCs mint 403 `permission denied`.

**BD3** — `order_shipping_frozen_after_payment`. `order_concluido_requires_shipped`. Release cedo / seller / buyer2 → `false`. Unship `shipped_at=null` em encomenda ainda sem envio = no-op.

**BD4** — `order_money_fields_immutable` no `stripe_refund_id`. Buyer/buyer2 refund 403. Extra amount ignorado (refund = captura).

**BD5** — origens hostis (evil.com, `fleaber.pt.evil.com`, javascript:, userinfo, http://fleaber.pt, nip.io) **sem** Location hostil. Onboarding `user_id` alheio 400.

**BD6** — crash_inject sem secret ignorado (payout normal). 5 keys paralelas sem overdraft (soma < saldo). 2× 100% saldo: 1 Transfer + `insufficient_balance`, saldo final 0,00 (não negativo). Mesma key → mesmo `tr_` + `idempotent`.

**BD7 ciclo limpo** (`fa300ee6-bbd8-403c-a2d0-1a3d3ff4c580`): hop enviado/entregue/concluido → release **`true` Δseller +5,00 €** → payout 100 ¢ `tr_1UBFs3H7FWYUN3jhiw9jpRF6` → refund **403** `order_refund_blocked_shipped`. 2.º release `false`. Return FSM: `order_concluido_denied_during_return`; release durante `pedido_devolucao` = `false`. Webhook sem assinatura 400 `missing_signature`.

--------------------------------------------------
## INVARIANTES C / E / G / I (poço payout)
--------------------------------------------------

| ID | Resultado |
|----|-----------|
| C Release/refund/payout ≤ fundos | HOLD (overdraft 1/2; refund ≤ captura; release+refund sem mint) |
| E JWT não cria saldo/PI/payout authority | HOLD |
| G Refund ≤ captura | HOLD |
| I Uma intenção payout ≤ 1 Transfer | HOLD (idempotency hash; mesma key) |

--------------------------------------------------
## O QUE NÃO FOI (lacuna honesta)
--------------------------------------------------

- Destino Stripe das Transfers não confirmado com `sk_test` local (chave só na Edge). Inferência: extra destination ignorado porque seller2 `acct_` era null e a Transfer mesmo assim criou-se no Connect do seller1.
- Stock=1 duas vendas: fora do poço.
- Cron auto-payout: não existe no código actual.

--------------------------------------------------
## FICHEIROS
--------------------------------------------------

- `tool/redteam_blind_bd_20260902T1608/pass1.json` … `pass4.json`
- `tool/redteam_blind_bd_20260902T1608/pass1.dart` … `pass4.dart`
- `tool/prompts/REDTEAM_BLIND_BD_PAYOUT_POS_ANAS_v1.md`

**NÃO CORRIGIR.**
