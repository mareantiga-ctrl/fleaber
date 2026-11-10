AUDITOR: REDTEAM_BLIND_D_COSTURA_v1
FROZEN_AT: 2026-08-30T18:45:00Z
production_touched: false
fase4: false
corrections_applied: false

# FROZEN — Red Team cego D · COSTURA / PÓS-CAIXA / IDENTIDADE

Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST · prefixo `RTD-20260830T1931`  
Probes: `scripts/probes/rtd_costura_20260830T1931.dart` (+ `_pass2` `_pass3` `_pass3b`)  
Raw: `scripts/probes/out/RTD_20260830T1931_raw.json` · `_pass2.json` · `_pass3.json`

Não se tocou produção. Não se aplicaram correcções. Não se iniciou Fase 4.

--------------------------------------------------
## Mapa de ataque (costura)

| Zona | LIVE observado |
|------|----------------|
| Pós-pago FSM | Trigger `batata_orders_guard_paid_status`: JWT buyer não marca `pago`/`enviado`; `pago→concluido` só mão; carrier exige `enviado`; `pago→cancelado` revertido. Seller off-platform pode `→pago`. Seller não fecha `concluido`. |
| Settle / return / webhook | `create-payment-intent` GET settle `verify_jwt=false` mas Session Stripe tem de estar `paid`. `stripe-webhook` exige `stripe-signature`. Replay GET sessão inventada → 400. Burst 6× → 400. Harness `setup_paid_order` (service_role + sk_test_) liquida PI `pm_card_visa` → `pago` + `amount_paid_cents`. |
| Chat ↔ order | RLS: INSERT mensagem só participante + `sender_id` forçado ao JWT. UPDATE de `FLEABER_JSON_V1` → `chat_system_card_immutable`. INSERT de card sistema por participante **passa**. Confirmar receção na app = PATCH `orders.status=concluido` + RPC release (não há RPC dedicado). |
| Off-platform | Seller PATCH `MB WAY` → `pago` (stock −1). Buyer mão → `concluido`. RPC release devolve `true`; wallet S1 **não** subiu sem captura (base 0). S2: `release_processed_at` set, Δwallet 0. Sem mint. |
| Feedback | INSERT review exige order própria `concluido`/`entregue` + pagamento confirmado. B2 na order B1 → `review_order_not_yours`. Review off-platform após seller→pago **permitida** (stock_units>0). |
| Shipping / label | Após pago: `order_shipping_frozen_after_payment`. Sem coluna `tracking`/`carrier` no schema orders (PGRST204). `prize_shipping` em order normal já `concluido` → checkout bloqueado. |
| Identidade body | POST checkout: JWT deve = `buyer_id`. B2+body B1 → `Invalid checkout user`. Connect `user_id` alheio → recusado. Refund S2 em order S1 → 403. Release B2 em order B1 → `false`. Seller INSERT `buyer_id` alheio + `pago` → `order_buyer_attribution_denied`. |
| Soft-delete | DELETE product JWT após pago → `200 []` (0 rows). Order permanece. |
| Rate / enum / device | Edges `verify_jwt=false`: webhook, settle GET, tip, connect, OCR, pairing, heartbeat, meta, egress. Pairing código inválido 400. OCR token lixo 401. Egress sem secret 401. Meta unsigned 403. `batata_find_user_id_by_email` (S2 com produtos) devolveu UUID do B1. |

Actores: B1 `bfcbeeee-…` (comprador) · S1 `980f4fa1-…` · B2 `68908953-…` · S2 `1a644b6c-…`.  
**Lacuna fixture:** B2 foi criado como segundo buyer; o perfil LIVE ficou `user_type=vendedor` (não `comprador`). Os cruzamentos JWT≠parte mesmo assim correram (B2 não lê/altera orders B1).

--------------------------------------------------
## Lentes exercitadas

Pass 1: D1–D10. Pass 2: D1 D2 D3 D4 D5 D6 D8 D10. Pass 3 (último ciclo, 6 lentes): D1 D3 D4 D6 D7 D8 — **sem classe nova P0/P1**.

Stripe TEST: PI `pi_3UADcSH7FWYUN3jh0swg8CMA` 590¢ `succeeded` → order `896538e4-…` `pago` → `enviado` → `concluido` → release wallet S1 65.34→75.34 (duas liquidações) → `refund-order` seller `already_refunded` + clawback 75.34→70.34. Segundo PI `pi_3UADcVH7FWYUN3jh01lu5BLS` / `pi_3UADfaH7FWYUN3jh0OFpwRRD`.

--------------------------------------------------
## Findings (congelados)

### Retratados (anti-falso-positivo)

**D4-OFFER-ACCEPT-ALIEN (pass 1, P1)** — HTTP `200 []`. Row `29786ec7-…` continua `pending` amount `3.00` (GET B1). B2 GET → `[]`. Sem persistência.

**D3-DEVICE-TOKEN-BUYER (pass 2, P1)** — RPC devolveu token, mas perfil B2 LIVE `user_type=vendedor`. Contrato da RPC é seller. Não é bypass de comprador. OCR com esse token na live S1 `dc7a0dd9-…` → `not_allowed`.

### P2-01 D4-CHAT-FORGE-INSERT

- **Actor:** B1 JWT (participante)
- **Pré:** chat `3772ee4c-…` B1–S1
- **Request:** `POST chat_messages` `sender_id=S1` text `FLEABER_JSON_V1:{"kind":"reservation_seller_confirmed_receipt",…}`
- **Antes:** sem card
- **Depois:** `201` id=819, `sender_id` forçado a B1, texto JSON persistido
- **UPDATE** do mesmo card → `403 chat_system_card_immutable`
- **B2** INSERT no mesmo chat → `403` RLS
- **Impacto:** timeline de sistema forjável por um participante; **não** altera `orders.status` nem wallet
- **Repro:** JWT participante POST `chat_messages` com prefixo `FLEABER_JSON_V1:`
- **Sev:** P2

### P2-02 D3-EMAIL-ORACLE

- **Actor:** S2 JWT (vendedor com produto)
- **Request:** `rpc batata_find_user_id_by_email` email do B1
- **Depois:** `200 "bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96"`
- **Impacto:** enumeração email→UUID (rate 2/h no SQL; 1 hit observado). Sem dados extra (IBAN etc.).
- **Sev:** P2

### P2-03 D6-HEARTBEAT-ALIEN-LIVE

- **Actor:** token device B2 (seller_id B2)
- **Request:** `POST ps-heartbeat` `live_id` = live **ended** do S1 `dc7a0dd9-…`
- **Depois:** `200 {"ok":true}` e row `ps_reader_heartbeats` seller_id=B2, live_id=S1, status=online
- **OCR** no mesmo live_id → `not_allowed` (token seller ≠ live seller)
- **Impacto:** heartbeat grava live alheia sob o seller do token; sem reserva/stock. Possível ruído se um painel listar por `live_id`.
- **Sev:** P2

--------------------------------------------------
## Races

| Par | Resultado |
|-----|-----------|
| `PATCH concluido` ∥ `POST order_disputes` (pass 1, reason inválida) | concluido 200; disputa 403 RLS |
| `entregue` → dispute `reason=outro` → `concluido` → release | disputa `201 aberta`; release `false`; wallet 70.34→70.34 |
| seller `enviado` ∥ buyer `cancelado` (order paga) | final `enviado`; cancel não pega |
| GET settle ×6 sessão fake | 400×6 |

Nenhuma race com ≥2 efeitos económicos no mesmo recurso.

--------------------------------------------------
## Contabilidade (fluxo Stripe TEST)

| | |
|--|--|
| Captura | 590¢ PI succeeded × várias fixtures `setup_paid_order` |
| Stock | qty 3→2 no setup (1 hold/sold) |
| Wallet S1 | 65.34 → 70.34 (1ª confirmação) → 75.34 (2ª) → 70.34 após refund+clawback da 1ª |
| Refund | `re_3UADcSH7FWYUN3jh0FyW5SMa` 590¢ `already_refunded/idempotent` |
| Off-platform | Δwallet 0 apesar de RPC `true` + `wallet_release_processed_at` (sem `amount_paid_cents`) |

Sem criação líquida: crédito wallet alinhado a captura; refund debitou o crédito da order reembolsada.

--------------------------------------------------
## Edges `verify_jwt=false` — 1 payload hostil cada (dinheiro/stock)

| Edge | Hostil | HTTP |
|------|--------|------|
| stripe-webhook | `charge.dispute.created` sig lixo / sem sig | 400 invalid_signature / missing_signature |
| create-payment-intent GET | `session_id=cs_test_rtd_hostile…` | 400 |
| create-payment-intent POST | sem JWT, buyer_id lixo | 400 Invalid checkout user |
| create-connect-account | anon + user_id UUID | 400 Invalid user |
| create-live-tip-checkout | anon sem seller | 400 Missing seller_id |
| ingest-ocr-reservation | token lixo | 401/400; token B2 em live S1 → 400 not_allowed |
| ps-pairing-claim | code 000000 | 400 invalid_or_expired_code |
| ps-heartbeat | token lixo | 200 `ok:false invalid_token`; token B2+live S1 → 200 ok (P2-03) |
| meta-data-deletion | signed_request forjado | 403 |
| livekit-egress-cleanup | sem secret | 401 |
| sec-fase2-e2e-oversell | JWT buyer | 401 Só service_role |

--------------------------------------------------
## Lacunas

- Checkout Session da app (`cs_test_`) **não** paga no browser (sem `sk_test_` local). Captura TEST = harness Edge `setup_paid_order` (PI confirm `pm_card_visa`). GET settle sobre Session não paga não marca `pago` (esperado).
- B2 perfil `vendedor` (fixture), não comprador puro.
- Sem live **activa** S1 para OCR (só `ended`); defesa `not_allowed` mesmo assim disparou.
- Sem coluna tracking para D7 etiqueta alheia.
- `batata_credit_wallet_once` / tip / prize: nomes de params no OpenAPI ≠ chamada; 404 schema — JWT sem grant efectivo nas que responderam 403.

--------------------------------------------------
## Saturação

Último ciclo (pass 3) · lentes D1 D3 D4 D6 D7 D8 · classe nova P0/P1: **não**.  
Pass 2 P1 retratado com prova de perfil. Pass 1 P1 retratado com GET da row.

--------------------------------------------------
## Veredicto (campos obrigatórios)

```
P0 encontrados: 0
P1 encontrados: 0
P2 encontrados: 3

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe bypass de identidade (JWT≠recurso): NÃO
Existe cross-user: NÃO
Existe race P0/P1: NÃO
Existe cadeia costura→caixa P0/P1: NÃO
Existe falha parcial explorável pós-pago: NÃO
Existe webhook/return explorável: NÃO

Dois buyers + dois sellers exercitados: SIM
Fluxo pós-pago exercitado: SIM
Último ciclo encontrou nova classe P0/P1: NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: PASS_CEGO_SATURADO
```
