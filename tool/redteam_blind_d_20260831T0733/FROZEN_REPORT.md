AUDITOR: REDTEAM_BLIND_D_COSTURA_v1
FROZEN_AT: 2026-08-31T06:50:00Z
production_touched: false
fase4: false
corrections_applied: false

# RED TEAM CEGO D — Costura / pós-caixa / identidade
Prefixo fixtures: `RTD-20260831T0733-`  
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · service_role só setup/observação/cleanup.

---

## Mapa de ataque (costura)

| Zona | LIVE observado |
|------|----------------|
| Pós-pago FSM | `reserva_pendente` → (`pago` via settle/off-platform) → `enviado` (seller) → `concluido` (buyer; carrier exige `enviado`; mão permite `pago`→`concluido`). JWT não cancela após pago. Seller não marca `concluido`. |
| Settle / return / webhook | `create-payment-intent` GET `verify_jwt=false`; sessão inventada → 400 «ainda não confirmado». Burst 6× = 400. `stripe-webhook` exige `stripe-signature` (sem sig / sig lixo → 400). Replay GET com PI no lugar de `session_id` → 400. |
| Chat ↔ order | `chat_messages` RLS participante. INSERT `FLEABER_JSON_V1` kinds allowlist: **sem `order_id` passa** (`seguro_fleaber_paid`, `reservation_accepted`, …). Kind server-only (`marketplace_bag_paid`) 403. UPDATE JSON 403 `chat_system_card_immutable`. Order de outro par 400 mismatch. |
| Off-platform | Seller JWT `PATCH status=pago` em MB WAY: **stock 3→2**, `stock_units_applied=1`, `amount_paid_cents` null. Buyer `concluido` + RPC release → **Δwallet 0** (sem fundos de plataforma). |
| Feedback / reviews | Review alheia 403 `review_order_not_yours`. Review própria após `concluido` 201. B2 PATCH review B1 → 200 `[]` (sem mutação). Auto-feedback DEFINER cron; JWT não executa a RPC. |
| Shipping / label | Após captura, `PATCH shipping_method` → 403 `order_shipping_frozen_after_payment`. Sem colunas `tracking_*` no schema LIVE de `orders`. `prize_shipping` em order normal → 400 «not a raffle prize». |
| Identidade body | Checkout `buyer_id` ≠ JWT → 400. `order_id` de outro buyer → 400. Ghost sale seller atribui `buyer_id` alheio → 403 `order_buyer_attribution_denied`. Connect `user_id` swap → 400. Refund buyer/S2 em order S1 → 403. |
| Soft-delete / orphan | DELETE product com order → 200 `[]`, row permanece. |
| Rate / enum | `ingest-ocr` sem token 401; token lixo + body completo 401 `invalid_token`. Pairing `000000` 400. Heartbeat token lixo 200 `{ok:false}`. Egress cleanup sem segredo 401. Meta deletion lixo 403. `find_user_id_by_email` JWT → `null`. |

Atores: B1 `bfcbeeee-…7c96` · S1 `980f4fa1-…9588` · B2 `69bead0c-…4c7c` · S2 `4cc92e57-…f927`.

Captura TEST: harness `sec-fase2-e2e-oversell` `setup_paid_order` (sk_test_ na Edge, **não** actor). PI `pm_card_visa` succeeded 590¢. Checkout Session da app (`cs_test_`) emitida; GET settle sobre Session **não paga** não marca `pago`.

---

## Findings

### RTD-0733-D1-01 — P1 — Seller `refund-order` após `concluido` (e com disputa aberta) reverte captura e restock

**Actor:** S1 JWT (Edge `refund-order`, `verify_jwt=true`, seller-only).  
**Pré:** Order plataforma `pago` 590¢, produto qty=1 → após settle qty=0 `is_sold=true`. Seller `enviado`. Buyer `concluido`. Variante: disputa `aberta` (`reason=danificado`).  
**Request:** `POST /functions/v1/refund-order` `{"order_id":"<uuid>"}` com JWT do vendedor.  
**Antes (order D `742b2493-…5ab5` / product `f9bf0c0d-…1d7f`):** `status=concluido`, `stock_units_applied=1`, `stripe_refund_id=null`, product `quantity=0` `is_sold=true`.  
**Depois:** HTTP 200 Stripe refund `re_3UAP04H7FWYUN3jh0sFFA9pQ` 590¢ `succeeded`; order `cancelado`; `stock_units_applied=null`; product **qty=1** `is_sold=false`. B2 INSERT order no mesmo SKU 201 + Checkout Session `cs_test_` 200.  
**Variante disputa (order `cc7e4011-…3ae`):** INSERT disputa 201 `aberta`; seller close → 403 `dispute_close_buyer_only`; RPC release → `false`; **mesmo assim** `refund-order` 200, order `cancelado`, refund `re_3UAP0BH7FWYUN3jh0YHbxvs3`.  
**Impacto:** A Edge não consulta FSM pós-pago nem disputa aberta. Após receção confirmada o vendedor desfaz a captura Stripe e **repor stock**, abrindo venda a um segundo comprador. A disputa retém a wallet (`release=false`) mas **não** o refund Stripe.  
**Repro:** setup_paid_order → PATCH `enviado` (S) → PATCH `concluido` (B) → [opcional POST `order_disputes` reason=`danificado`] → POST `refund-order` (S) → observar qty 0→1 e Session B2.  
**Sev:** P1 (pós-caixa + costura disputa∥refund). Não P0: segunda captura B2 não foi liquidada (Session sem pay); net Stripe desta linha = refund da primeira captura; sem mint wallet.

### RTD-0733-D4-02 — P2 — INSERT de cards `FLEABER_JSON_V1` sem `order_id`

Participante do chat insere kinds `reservation_order_completed`, `seguro_fleaber_paid`, `reservation_accepted`, `price_offer_outcome`, `bundle_direct_payment_details` **sem** `order_id` → 201. Guard só valida papel quando há UUID de order. UPDATE posterior 403 (imutável). Sem Δ wallet/stock. UI mentirosa.

### RTD-0733-D1-03 — P2 — JWT grava `completed_at` no passado ao entrar em `concluido`

`PATCH {status:concluido, completed_at:2020-01-01}` persistiu `completed_at=2020-01-01`. Cron/RPC `batata_generate_auto_feedback` (service_role observação) gerou reviews automáticas 5★ `purchase_verified=true` e marcou `wallet_release`. O buyer JWT já pode chamar `batata_release_seller_wallet_for_order` imediatamente após `concluido` (sem disputa) — o atalho extra é saltar a janela 48h de auto-feedback/reviews. Sem mint extra.

---

## Races

| X ∥ Y | Resultado |
|-------|-----------|
| `PATCH concluido` ∥ `INSERT order_disputes` (status ainda `enviado`) | Confirm 200 → `concluido`; disputa 403 RLS (só `concluido`/`entregue`). Sem dois efeitos económicos. |
| Release ∥ disputa aberta | Release `false`; disputa permanece até buyer fechar. Seller refund **fura** este hold (P1 acima). |

## Stripe TEST

| PI | Resultado |
|----|-----------|
| `pi_3UAOvIH7FWYUN3jh0amVdd6Q` | pago 590¢ → enviado → concluido → release wallet S1 +5.00 |
| `pi_3UAOvLH7FWYUN3jh0yvWSWka` | pago → enviado → concluido backdate → auto-feedback + release +5.00 |
| `pi_3UAOxEH7FWYUN3jh0GZxx4LQ` | pago → enviado → concluido → refund seller (pass2) |
| `pi_3UAP04H7FWYUN3jh0oUfXPxj` | pago qty=1 → concluido → **refund 590¢ + restock 0→1** (P1) |
| `pi_3UAP0BH7FWYUN3jh0XyE02Gj` | pago → concluido → disputa aberta → **refund 590¢** (P1) |

Webhooks hostis: não exploráveis sem assinatura.

## Lacunas

- Sem `STRIPE_SECRET_KEY` local: Session Checkout B2 no SKU restock **não** foi paga com 4242 (segunda captura permanente = NÃO COMPROVADO).
- OpenAPI anon 401; RPCs mapeadas com service_role (182 funções).
- Disputa recusada em `pago`/`enviado` (RLS) — comprador só disputa depois de `concluido` (janela curta; costura com P1).
- `already_refunded:true` na resposta da Edge = persistência antecipada do `stripe_refund_id` + finalize idempotente; o refund Stripe foi criado nesta chamada (PI fresco, `stripe_refund_id` era null).

## Saturação

Lentes exercitadas: **D1 D2 D3 D4 D5 D6 D7 D8 D9 D10** (≥4).  
Último ciclo (pass 3) encontrou **classe nova P1** (refund pós-`concluido` / durante disputa). **Não saturado.**

---

```
P0 encontrados: 0
P1 encontrados: 1
P2 encontrados: 2

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe bypass de identidade (JWT≠recurso): NÃO
Existe cross-user: NÃO
Existe race P0/P1: NÃO
Existe cadeia costura→caixa P0/P1: SIM
Existe falha parcial explorável pós-pago: SIM
Existe webhook/return explorável: NÃO

Dois buyers + dois sellers exercitados: SIM
Fluxo pós-pago exercitado: SIM
Último ciclo encontrou nova classe P0/P1: SIM
SATURAÇÃO: NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P1
```
