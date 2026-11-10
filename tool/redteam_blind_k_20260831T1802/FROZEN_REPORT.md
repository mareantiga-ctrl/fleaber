# FROZEN_REPORT — REDTEAM_BLIND_K_POS_HIJ_v1

```
AUDITOR: REDTEAM_BLIND_K_POS_HIJ_v1
FROZEN_AT: 2026-08-31T17:13:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [K1, K2, K3, K4, K5, K6, K7]
VEREDICTO: FAIL_P1
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors: anon, buyer JWT, seller JWT, 2.º buyer, 2.º seller.  
`service_role` só fixture / observação. Prefixo `RTK-20260831T1802-`.  
Provas: `probe.json`, `pass2.json`. Repro: `dart run tool/redteam_blind_k_20260831T1802/probe.dart` e `pass2.dart`.

**Missão.** Depois dos fechos I (levantamento → `devolvida` sem mint) e J (plain→JSON): (1) mintar carteira / estorno fantasma após levantamento, ou (2) forjar recibo de sistema no chat?

**Resposta.** (1) **não** — payout Connect real + `devolvida` não creditou o comprador; clawback fail-closed sem estorno fantasma; `refund-order` Stripe TEST ainda devolve o cartão depois de `devolvida`. (2) **sim** — recibo «Seguro Fleaber pago» persistido no chat sem captura.

Não é ATROFIA_ABORT (findings não são dual Session / bag unlist / offer morto / pairing / Hub paused / invite enum / cancel hold / review 5★ / tip mismatch / helper escalate).

--------------------------------------------------
## Findings
--------------------------------------------------

### K-P1-001 · K4 + K6 · Recibo JSON `seguro_fleaber_paid` em MB WAY «pago» sem captura

**Actor:** buyer JWT  
**Severidade:** P1  

**Passos**
1. Comprador cria hold `payment_method=MB WAY`, `shipping_method=mao`, sem PaymentIntent (`amount_paid_cents` null).
2. Vendedor PATCH `status=pago` (off-platform, permitido).
3. Comprador INSERT `chat_messages.text = FLEABER_JSON_V1:{"kind":"seguro_fleaber_paid","order_id":"…","total":3.5}`.

**Esperado:** recusa (`chat_system_card_order_not_paid`) — o kind afirma pagamento plataforma.  
**Obtido:** HTTP **201**, mensagem id **895**. Ordem `916b1667-fb33-4216-a640-dda3dc22c861` continua sem PI / sem `amount_paid_cents`. Chat `2852d2af-4f03-4d84-a0b2-fd472f0bf0cd`.

**Porquê P1:** o guard `needs_paid` trata `status ∈ {pago, enviado, concluido, …}` como pago. Off-platform o vendedor marca `pago` sem Stripe; o JSON que J bloqueia em hold `reserva_pendente` passa. A app desenha `_buildSeguroFleaberPaidCard` («Comprado!» / «Venda paga» / «Paga através do Seguro Fleaber»). Sem Δwallet — não é P0.

**Não é Flutter-only:** o INSERT REST é a prova; o cliente só renderiza o que já está gravado.

---

### K-P1-002 · K4 · Texto legado «Compra paga através do Seguro Fleaber» (bypass JSON)

**Actor:** buyer JWT  
**Severidade:** P1  

**Passos**
1. No mesmo chat, INSERT texto plano (sem prefixo `FLEABER_JSON_V1:`):  
   `Compra paga através do Seguro Fleaber (8888.88 €) [order:<hold_não_pago>]`
2. Idem com total 3,50 € na ordem MB WAY.
3. Idem `Compra em conjunto paga através do Seguro Fleaber (99.00 €)`.

**Esperado:** ou recusa, ou bolha de chat normal — não o card de sistema.  
**Obtido:** HTTP **201** ids **901**, **902**, **903**. Hold `a093d3ef-9ff6-4336-8f96-cccbaeaa9187` nunca teve captura.

**Porquê P1:** o trigger J só valida linhas `FLEABER_JSON_V1:%`. O cliente (`_isLegacySeguroFleaberPaidPlainText`) promove este prefixo a card de sistema com total parseado do texto. Caminho explorável sem qualquer ordem paga. Sem movimento de dinheiro.

---

### K-P2-003 · K4/K6 · Outros kinds «pós-pago» na mesma ordem MB WAY

**Actor:** buyer JWT / seller JWT  
**Severidade:** P2  

INSERT 201: `reservation_order_completed` (904, buyer), `reservation_order_shipped` (905, seller), `reservation_seller_confirmed_receipt` (906, seller) na ordem MB WAY sem captura. Oracle `needs_paid` = status `concluido`/`pago`. Cards operacionais, não o recibo Seguro; hygiene.

`order_paid` / `raffle_prize_awarded` recusados (403 `server_only` / `kind_denied`).

---

## Lentes — o que segurou (INFO, prova LIVE)

### K1 — Payout total → `devolvida` sem mint

Stripe TEST `setup_paid_order` 5,90 € · PI `pi_3UAYiWH7FWYUN3jh0YjkrwP2` · ordem `e4ef5d03-ba15-4749-92c7-d6a994f8d877`.

- Seller `enviado` + buyer `concluido` + RPC release: seller **0 → 5,00 €** (tx `venda` 5,00).
- `create-connect-account` amount=500, idempotency `RTK-20260831T1802-payout-e4ef5d03-…` → HTTP 200, seller **5,00 → 0** (`drained_via: connect`).
- JWT seller PATCH `devolvida` → **403**. JWT buyer PATCH → HTTP 200 mas status **permanece `concluido`** (revert silencioso). RPC `batata_refund_buyer_wallet_for_order` JWT buyer → `false`.
- Fixture `service_role` PATCH `devolvida`: status `devolvida`, **Δbuyer = 0** (40,45 → 40,45), 0 tx `reembolso`, 0 tx `estorno`, `stripe_refund_id` null, `wallet_refund_processed_at` null (clawback incompleto → fail-closed, sem carimbar).

### K2 — Clawback saldo 0

Após Connect a 0: **nenhuma** linha `estorno`. Δseller 0. Sem livro fantasma.

### K3 — `refund-order` Stripe (anti-regressão)

| Estado | Actor | Resultado |
|--------|--------|-----------|
| `pago` | seller | HTTP 200 `ok=true` `re_3UAYiOH7FWYUN3jh1jKq1yZt` status `cancelado` · PI `pi_3UAYiOH7FWYUN3jh1E8O9TDL` |
| qualquer | buyer / 2.º seller | HTTP 403 Sem permissão |
| `concluido` pós-release | seller | HTTP 403 `order_refund_blocked_status` (esperado: já enviada) |
| `devolvida` pós-payout | seller | HTTP 200, refund **590 cêntimos**, `re_3UAYiWH7FWYUN3jh0apy8awO`, `status_stripe=succeeded` |

Caminho legítimo de recuperação do cartão **funciona** depois de `devolvida`. Não há prisão de fundos no PI.

### K4 / K5 — JSON J (exceto P1 acima)

INSERT kinds servidor (`order_paid`, `marketplace_bag_paid`, `auto_feedback_generated`, `raffle_prize`, `premio_rifa`) → 403 `chat_system_card_server_only`.  
INSERT `seguro_fleaber_paid` em hold `reserva_pendente` → 400 `order_not_paid`.  
2.º buyer no chat alheio → 403 `not_participant`. anon → 401.  
UPDATE plain → JSON servidor / seguro unpaid → 403/400.  
UPDATE JSON já gravado → 403 `chat_system_card_immutable`. Contraparte PATCH HTTP 200 mas texto **inalterado**.

BOM / `fleaber_json_v1:` minúsculo: INSERT 201 como texto solto; o parse Flutter exige prefixo exacto — não renderiza card. Não é recibo.

### K6 — Off-platform / mão

MB WAY `pago` → `concluido` (buyer JWT) **ainda funciona**.  
Release nessa ordem: RPC `false`, saldo seller 85,00 → 85,00 (sem mint; fundos plataforma = 0).  
`devolvida` wallet em plataforma capturada: só faz sentido via Stripe (K3/K7), não via mint — confirmado.

### K7 — Composição até Stripe net

Drain Connect + `devolvida` sem mint + `refund-order` seller → cartão reembolsado 5,90 €.  
JWT `batata_credit_wallet_once` → 403 permission denied.  
JWT `payment_method` / `stripe_refund_id` → 403 `order_money_fields_immutable`.

Não se partiu: mão→`concluido`; seller `enviado`; não se cancelou hold crítico além do cleanup `reserva_pendente` de fixture.

--------------------------------------------------
## Contabilidade fechada (K1/K7)

| Peça | Valor |
|------|--------|
| Buyer wallet | 40,45 € inalterado no mint |
| Seller wallet | 0 → 5,00 (release) → 0 (Connect) |
| PI | `pi_3UAYiWH7FWYUN3jh0YjkrwP2` captura 590 → refund `re_3UAYiWH7FWYUN3jh0apy8awO` |
| `stripe_refund_id` após K7 | preenchido |
| Tx `reembolso` buyer na ordem | 0 |

--------------------------------------------------
## O que não é P0

HTTP 200 no PATCH buyer `devolvida` sem mudança de estado ≠ P0.  
`refund-order` 403 em `concluido` é o gate pós-envio, não regressão do fluxo `pago` nem do fluxo `devolvida`.  
Payout Connect + refund do PI deixa o seller com o Transfer e o comprador com o cartão — custo de disputa pós-levantamento na plataforma, **não** mint de carteira.

--------------------------------------------------
## Limites desta ronda

Não se abriu a UI Flutter para screenshot do card 895/901 — o caminho de render é o código actual (`seguro_fleaber_paid` + `_isLegacySeguroFleaberPaidPlainText`).  
Não se tocou produção. Não se aplicou correcção.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
