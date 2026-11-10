AUDITOR: REDTEAM_BLIND_D_COSTURA_v1
FROZEN_AT: 2026-08-30T16:33:20Z
production_touched: false
fase4: false
corrections_applied: false

# Relatório congelado — Red Team cego D (costura)

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTD-20260830T1721`  
Probes: `scripts/probes/rtd_costura_20260830T1721.dart` (+ `_pass2` + `_pass3`)  
Raw: `scripts/probes/out/RTD_20260830T1721_raw.json`, `_pass2.json`, `_pass3.json`

Actores exercitados:
- B1 `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` · S1 `980f4fa1-0004-42f9-abca-69f1a9c29588`
- B2 `ce3f90f6-4ba2-43f8-9251-f4045cb2190f` · S2 `a8956587-5bb2-4640-aae2-0c85efe3344e` (contas criadas neste ciclo)

Captura TEST: PaymentIntent `pm_card_visa` via harness `sec-fase2-e2e-oversell` / `setup_paid_order` (sk_test_ na Edge). Session Checkout da app criada (`cs_test_a167…`) **não** paga no browser; GET settle sobre ela **não** marcou `pago`.

--------------------------------------------------
## Mapa de ataque (costura)
--------------------------------------------------

| Zona | LIVE observado |
|------|----------------|
| Pós-pago FSM | `batata_orders_guard_paid_status`: plataforma JWT não marca `pago` sem captura; seller MB WAY→`pago` permitido; **buyer pode `pago`→`concluido` sem `enviado`**; seller não marca `concluido`; cancel após pago revertido. |
| Settle / return / webhook | `create-payment-intent` GET settle `verify_jwt=false`; `stripe-webhook` exige `stripe-signature`; unsigned / fake sig → 400; GET settle session unpaid → texto «ainda não confirmado», order fica `reserva_pendente`. |
| Chat ↔ order | `chat_messages` INSERT força `sender_id=auth.uid()`; B2 não lê/escreve thread alheia; UPDATE de texto alheio revertido (só `is_read`). Cards `FLEABER_JSON_V1` **não** movem FSM (só UI). |
| Off-platform | Seller `MB WAY`→`pago` consome stock (`stock_units_applied=1`) sem `amount_paid_cents`; buyer não atesta `pago`; plataforma seller→`pago` revertido. Release MB WAY `true` mas **Δwallet=0**. |
| Feedback | INSERT review exige order própria `concluido/entregue` + pagamento confirmado; B2 403 `review_order_not_yours`; PATCH stars/comment congelado. |
| Shipping / label | Seller `enviado` sem `pago` revertido; S2 PATCH shipping alheio → 200 `[]`; `premio_rifa` em order normal revertido. App marca envio por PATCH `orders.status` (sem RPC etiqueta). |
| Identidade body | Checkout `user.id !== body.buyer_id` → 400; refund seller-only 403; connect ignora `user_id` do body (getUser); RPC release só buyer da order (`false` para B2/S2). |
| Disputa | INSERT só buyer da order em `concluido/entregue` e `wallet_release_processed_at is null`. **UPDATE participantes sem máquina de transições** — seller PATCH `resolvida`/`recusada` persiste. Release bloqueia enquanto `aberta`; `resolvida`/`recusada` desbloqueiam. |
| Soft-delete | DELETE product/order JWT → 200 `[]`, rows permanecem. |
| Rate / enum | B2 não enumera orders/chats/disputes/wallets/tokens alheios. `batata_find_user_id_by_email` → `null`. Auto-feedback RPC 403. `ingest-ocr` / pairing / meta / egress sem segredo → 401/400/403. |

Lentes exercitadas: **D1, D2, D3, D4, D5, D6, D7, D8, D9, D10**.

--------------------------------------------------
## Findings P1
--------------------------------------------------

### D1-EARLY-CONFIRM-PAYOUT — P1

- **Actor:** buyer JWT (B1; reproduzido B2×S2)
- **Pré:** order `pago` com captura Stripe TEST (`amount_paid_cents=590`, `stock_units_applied=1`), **nunca `enviado`**
- **Request:** `PATCH /orders {status:concluido}` + `POST rpc/batata_release_seller_wallet_for_order`
- **Antes:** `status=pago` · wallet S1 `28.39` · `wallet_release_processed_at=null`
- **Depois:** `status=concluido` · wallet S1 `33.39` (`+5.00` tipo `venda`) · `wallet_release_processed_at=2026-08-30T16:29:04.423094+00:00` · order `e6e89129-1adf-4fe2-95d3-00095e21c4f0` · PI `pi_3UABbNH7FWYUN3jh1jrHDYLj`
- **Impacto:** hold de envio e janela de disputa saltados. Disputa INSERT em race com release → 403 (RLS exige `wallet_release_processed_at is null`). UI de confirmação de receção **não** chama o RPC; o RPC autenticado sim. Mesma classe em B2×S2: order `3bb09609-c8a6-4ac1-925c-7296024ca7e7`, wallet S2 `null→5.00`, RPC `true`.
- **Repro:** `setup_paid_order` → JWT buyer PATCH `concluido` → RPC release.
- **Sev:** P1 (pós-caixa / hold). Não é mint: captura 5,90 € TEST, crédito 5,00 € (comissão). Refund seller depois fez `estorno` 5,00 € e Stripe `re_3UABbNH7FWYUN3jh1eYTA0x0` — contabilidade fechou nessa order.

### D1-DISPUTE-UPDATE-UNCONSTRAINED — P1

- **Actor:** seller JWT da order (participante)
- **Pré:** order paga TEST, `enviado`→`concluido`, disputa `aberta` pelo buyer, release ainda `false`
- **Request:** `PATCH /order_disputes {status:resolvida, buyer_decision:cancelled}` depois RPC release (buyer)
- **Antes:** disputa `046f72a3-…` `aberta` · order `54330c3a-ee56-40dd-a87f-06cc153714df` `wallet_release=null` · wallet S1 `28.39` · RPC release com disputa aberta = `false`
- **Depois:** disputa `resolvida` · RPC `true` · wallet S1 `33.39` · `wallet_release_processed_at=2026-08-30T16:31:37.993041+00:00`
- **Impacto:** o vendedor encerra a disputa sem o comprador aceitar e desbloqueia o payout. A política UPDATE só exige ser buyer **ou** seller da order — sem transições. Pass 3: o mesmo UPDATE aceita `recusada` (order `ce5e0486-…`, disputa `739eee8b-…`). RPC de release trata `recusada`/`resolvida` como não bloqueantes.
- **Repro:** fluxo pós-pago até disputa `aberta`; JWT seller PATCH `status=resolvida`; JWT buyer RPC release.
- **Sev:** P1 (autoridade pós-caixa). B2 PATCH da mesma disputa → 200 `[]` (não cross-user).

--------------------------------------------------
## P2 (não sobem)
--------------------------------------------------

| ID | Nota |
|----|------|
| D4-JSON-CARD-SELF | Buyer INSERT `FLEABER_JSON_V1` `reservation_order_shipped` com `sender_id` spoofado → persistido com `sender_id=B1`. Não altera `orders`. Spoof de UI. |
| D1-DISPUTE-REOPEN | Após seller `recusada`, buyer INSERT segunda disputa `aberta` (`bc380875-…`) 201. Griefing de hold; INSERT novo exige ainda `wallet_release is null`. |
| RLS-SILENT-200 | PATCH alheio em orders/disputes devolve 200 `[]` (0 rows) — não é bypass. |
| SETTLE-200-UNPAID | GET settle `cs_test_a167…` HTTP 200 HTML «não confirmado»; order `95a4f30b-…` ficou `reserva_pendente`. |
| D10-MBWAY-NO-MINT | Seller MB WAY→pago→enviado→concluido→release `true`, `wallet_release` preenchido, **Δwallet 0** (sem `amount_paid_cents`). Stock 1 consumido — caminho off-platform atestado pelo seller, não captura. |

--------------------------------------------------
## Races (D2)
--------------------------------------------------

| X ∥ Y | Resultado |
|-------|-----------|
| INSERT disputa ∥ RPC release (já `concluido`) | release `true` (+5 €); disputa 403 |
| seller `enviado` ∥ buyer `cancelado` (order paga) | final `enviado`; cancel revertido; sem `stripe_refund_id` |
| GET settle ×6 sessions fake | 400 em todas; sem `pago` |

Nenhum race com **dois** efeitos económicos válidos no mesmo recurso → não P0/P1 de race.

--------------------------------------------------
## Stripe TEST (contabilidade)
--------------------------------------------------

| PI | Order | Captura | Wallet | Refund |
|----|-------|---------|--------|--------|
| `pi_3UABbNH7FWYUN3jh1jrHDYLj` | `e6e89129-…` | 590 c | +5,00 depois −5,00 estorno | `re_3UABbNH7FWYUN3jh1eYTA0x0` succeeded |
| `pi_3UABbRH7FWYUN3jh1pJrYbB3` | `7b33b252-…` | 590 c | — | — (ficou `enviado`) |
| `pi_3UABdqH7FWYUN3jh0BDU5aEE` | `54330c3a-…` | 590 c | +5,00 após seller fechar disputa | residual deste P1 |
| `pi_3UABdvH7FWYUN3jh1BB74Qyl` | `3bb09609-…` B2×S2 | 590 c | S2 +5,00 early confirm | residual mesma classe |
| `pi_3UABf7H7FWYUN3jh1YmbxHqu` | `ce5e0486-…` | 590 c | — | disputa reaberta; release não chamado |

Não há PI cobrado **e** creditado **e** reembolsado sem estorno na primeira order. As orders `54330c3a` e `3bb09609` ficam com crédito wallet correspondente a captura real (payout antecipado / disputa morta) — impacto P1, não mint ex nihilo.

--------------------------------------------------
## Identidade / cross-user (D3) — bloqueados
--------------------------------------------------

Checkout JWT B2 + `buyer_id=B1` → `Invalid checkout user.`  
Refund S2/B1 em order S1 → 403 `Sem permissão.`  
Review/dispute/chat B2 em recurso B1 → 403.  
RPC release B2/S2 em order B1 → `false`.  
Seller INSERT order `buyer_id=B2` → 403 `order_buyer_attribution_denied`.  
Connect body `user_id=S1` com JWT B1 → erro de conta Stripe do **user JWT**, não do UUID no body.

--------------------------------------------------
## Edges `verify_jwt=false` — payload hostil
--------------------------------------------------

| Edge | Payload | HTTP / efeito |
|------|---------|----------------|
| stripe-webhook | sem sig / sig lixo + `charge.dispute` / session paid falsa | 400 missing/invalid_signature · sem Δ |
| create-payment-intent GET | `session_id=cs_test_rtd_hostile` e cs unpaid real | 400 ou 200 «não confirmado» · sem `pago` |
| ingest-ocr-reservation | sem token / token forjado | 401 |
| ps-pairing-claim | `000000` | 400 invalid_or_expired |
| meta-data-deletion | signed_request lixo | 403 |
| livekit-egress-cleanup | sem secret | 401 |
| create-connect-account | sem JWT | 400 Missing authorization |
| create-live-tip-checkout GET | session fake | 400 No such checkout.session |

--------------------------------------------------
## Lacunas
--------------------------------------------------

- Sem `STRIPE_SECRET_KEY` local: Session Checkout da app não foi paga com 4242 no browser (PI TEST via harness).
- OpenAPI PostgREST `/rest/v1/` com Accept openapi devolveu 0 RPCs (401 no root sem Accept certo) — inventário de RPCs pelo código SQL + tentativas hostis.
- `batata_process_partial_refund_dispute` 403 `not_allowed` fora do turno «oferta aceite» — fluxo parcial completo não saturado.
- Cron `batata_generate_auto_feedback` (48 h) não esperado neste ciclo; JWT 403.
- Transfer Connect / payout real não corrido (saldo Connect).

--------------------------------------------------
## Saturação
--------------------------------------------------

4+ lentes D* (10). Pós-pago + IDs cruzados exercitados.  
Pass 1: classe P1 early-confirm. Pass 2: classe P1 dispute UPDATE. Pass 3: `recusada` = **mesma** superfície UPDATE; reopen = P2; saltos `pedido_devolucao` / ship unpaid / identidade INSERT **não** persistiram.  
Último ciclo **sem nova classe P0/P1**.

Não se adaptou a relatórios de outros auditores.
