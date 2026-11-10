# FROZEN_REPORT — REDTEAM_BLIND_INDEP_v4

```
AUDITOR: REDTEAM_BLIND_INDEP_v4
FROZEN_AT: 2026-08-30T1835Z
production_touched: false
fase4: false
corrections_applied: false
```

Staging `fxdknzrqjenzqcvnwqqq`. Stripe **TEST** 4242 pago 1×. `service_role` só fixture/observação/cleanup. Actor = JWT buyer/seller/fresh + anon.

Prefixo fixtures: `RTI4-1916-`.

Não foram consultados relatórios de outros auditores. Código + schema LIVE + comportamento LIVE.

---

## Poços exercitados

| Poço | LIVE | Estado final |
|------|------|----------------|
| 1 Morto/montra | SIM | captura 14,30 € em SKU unlist; Hub vazio; freeze raffle |
| 2 Pós-caixa | SIM | pago→enviado→concluido; settle dual; refund∥release Δwallet=0 |
| 3 Política fina | SIM | views Hub vs tabela; trigger silent vs raise; Edge vs INSERT |
| 4 Órbita | SIM | crons 401/403; favorites/follows 403; tip_id cliente recusado; Connect JSON (não redirect hostil) |

ATROFIA (só redescobriu núcleo fechado): **NÃO**.

---

## P0 / P1 abertos

### RTI4-P1-UNLIST-LIVE-CAPTURE — P1

**Título:** Captura Stripe TEST num produto **fora da montra** (`list_on_marketplace=false`), amarrando `live_id` de um directo **já ended**.

**Actor:** buyer JWT + Edge `create-payment-intent` + cartão TEST 4242.

**Pré:**
- produto `8cc95520-3bff-4093-92b9-c556fe99dba7` unlist, `is_sold=false`, qty=2
- live `dc7a0dd9-6bb1-43ee-9899-d4b5bf93960d` `status=ended` `is_active=false` do **mesmo** seller
- Hub `hub_products_public` → `[]` (anon)

**Request:**
1. `POST /rest/v1/orders` JWT buyer: `product_id` unlist + `live_id=<ended>` → `201` hold `edbabf9f-…`
2. Sem `live_id`: hold bloqueado `order_hold_product_not_listed`
3. `POST create-payment-intent` → Session `cs_test_a1g5rjxfzkHH912tV3dQehcK9CiPsKUa57m8aB3qtrAnx1UKsh2YawNXdN` **14,30 €** (contrato 9,50 + portes + protecção; body `amount=1` ignorado)
4. Pagar 4242 na Checkout Stripe TEST

**Antes:** order `reserva_pendente`, `amount_paid_cents=null`, Hub vazio, wallet seller 66,34.

**Depois (CAPTURA):**
- order `pago`, `amount_paid_cents=1430`, PI `pi_3UADUhH7FWYUN3jh0HuS8iga`, `stock_units_applied=1`
- product qty 2→1, continua `list_on_marketplace=false`, Hub `[]`
- wallet **sem** crédito (release ainda não)

**Impacto:** montra vazia ≠ inventário morto. Qualquer SKU unlist do seller é vendável se o comprador conhecer o UUID e existir **algum** directo ended desse seller. Classe repetida no 2.º SKU (`ba339a49-…` → Session `cs_test_a1o3owIY…`, sem 2.ª captura).

**Repro:** hold JWT `live_id` ended + checkout + 4242.

**Distinção:** SESSION criada **e** CAPTURA permanente (PI succeeded). Após refund TEST (passo 3) o PI foi reembolsado na totalidade — o buraco de **autoridade de catálogo** permanece.

Live de **outro** seller: `order_live_seller_mismatch` (HOLD). `is_sold` + live ended: `order_hold_product_sold` (HOLD).

---

### RTI4-P1-RAFFLE-STRIP-FREEZE — P1

**Título:** `live_raffle_id` forjado (UUID inexistente) **bypassa unlist no hold**; a coluna é depois **anulada**; o hold **fica**. Stock preso sem live real e sem Session.

**Actor:** buyer JWT.

**Pré:** produto qty=1 unlist `88a02e2c-…`

**Request:** `POST orders` com `live_raffle_id=00000000-0000-4000-8000-000000000099`

**Antes / depois:**
- INSERT `201` hold `bf809940-…` `reserva_pendente`
- row LIVE: `live_raffle_id=null`, `live_id=null`
- seller `list_on_marketplace=true`
- `batata_product_checkout_available` → `{ok:false, held:1, stock:1, available:0}`

**Impacto:** DoS de capacidade. Edge recusa checkout (`product is not listed`) porque o flag já não existe — mas o hold **não** é revertido. `reservation_expires_at=null`.

**Repro:** JWT hold unlist + raffle UUID lixo → observar colunas null + available=0 após re-list.

Mesmo mecanismo no SKU da captura: hold fantasma `8450a8c0-…` ocupou 1 unidade residual após o pago (stock 1, held 1, available 0).

---

### RTI4-P2-HUB-SOLD — P2 (não P1)

View `hub_products_public` filtra só `list_on_marketplace`, **não** `is_sold`. Anon viu `6d96f361-…` `is_sold=true` price 9,50. Hold JWT em is_sold: `order_hold_product_sold`. Vitrine suja, sem venda.

---

## Invariantes A–L

| ID | Resultado | Notas |
|----|-----------|--------|
| A | HOLD | Checkout cobrou 14,30 € servidor, não o `amount` do body |
| B | HOLD | qty autoritativa; underpay/qty 99 recusado (`Invalid checkout user` / stock) |
| C | HOLD | release∥refund: wallet 66,34→66,34; refund Stripe 1430=captura |
| D | HOLD núcleo | race 6× qty=1 → 1 hold. **FALHA segunda onda:** freeze raffle ≠ duas vendas |
| E | HOLD | JWT não criou saldo; release `true` sem Δ quando refund a correr |
| F | NÃO COMPROVADO | off-platform não exercitado nesta onda |
| G | HOLD | refund `re_3UADUhH7FWYUN3jh0D4z7hhW` amount 1430 = captura |
| H | HOLD | foreign live_id bloqueado; fresh refund 403; fresh review 403 |
| I | HOLD | sem Transfer duplicada da order; Connect `tr_1UADXMH7…` é payout 1,00 € do **próprio** seller (probe órbita, não mint) |
| J | — | n/a |
| K | HOLD | contrato selado 14,30 vs catálogo 9,50 |
| L | **FALHA** | reserva/checkout sem listagem; raffle fake = autoridade de hold |

---

## O que fechou (segunda onda, não núcleo)

- Hold `is_sold` sem live → `order_hold_product_sold`
- Hold unlist **sem** live_* → `order_hold_product_not_listed`
- Bag após unlist (hold prévio, **sem** live_id) → Edge `product is not listed`
- Anon tabela `products` → 401
- Hub unlist → `[]`
- Discovery unpublished → `[]`
- Buyer INSERT `pago` → persistido como `reserva_pendente`
- Buyer `concluido` desde `pago` carrier → 403 `order_concluido_requires_shipped`
- Buyer `enviado` → HTTP 200 **silent**, status permanece (não raise)
- Fresh PATCH order alheia → 200 `[]`
- Dual GET settle → idempotente, stock_units=1
- Race qty=1 → 1 hold
- Crons auto_feedback / egress / expire → 401/403
- Favorites/follows user_id alheio → 403
- `tip_id` cliente → 400
- Admin resolve anon → 401
- Reviews sem order / order alheia → bloqueado
- Bundle self-accept → `bundle_invalid_buyer`

Probe Connect `amount=100` debitou **1,00 €** da wallet seller (66,34→65,34) com Transfer TEST — efeito colateral do teste de origem, **não** finding de mint.

---

## Contabilidade do fluxo pago

```
captura Stripe     +1430 cêntimos  (pi_3UADUhH7FWYUN3jh0HuS8iga)
refund Stripe      -1430           (re_3UADUhH7FWYUN3jh0D4z7hhW)
Δ wallet seller    0               (release marcado + refund; sem crédito líquido)
```

SESSION ≠ CAPTURA ≠ net permanente: houve captura; net carteira **0**; o P1 é **autoridade de catálogo / hold**, não mint.

---

## VEREDICTO

**B FAIL_P1** — duas classes P1 na segunda onda (unlist+live ended com captura; raffle-strip freeze). Sem P0 económico. Poços 1–4 exercitados. ATROFIA=NÃO.
