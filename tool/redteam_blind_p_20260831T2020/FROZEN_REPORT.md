# FROZEN_REPORT — REDTEAM_BLIND_P_COMPOSICAO_CAIXA_v1

```
AUDITOR: REDTEAM_BLIND_P_COMPOSICAO_CAIXA_v1
FROZEN_AT: 2026-08-31T19:34:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [P1, P2, P3, P4, P5, P6, P7, P8, P9, P10]
composicoes_distintas: 9
VEREDICTO: PASS_CEGO_SATURADO
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · actors: anon, buyer JWT `bfcbeeee-…`, seller JWT `980f4fa1-…`, 2.º buyer `d9284ec6-…`, 2.º seller `98c98de2-…`.  
`service_role` só fixture / observação. Prefixo `RTP-20260831T2020`.  
Provas: `probe.json`, `pass2.json`, `pass3.json`. Repro: `dart run tool/redteam_blind_p_20260831T2020/probe.dart` (+ `pass2.dart`, `pass3.dart`).

**Missão.** Dois ou três furos que sozinhos HOLD — encadeados, abrem a caixa (Δwallet, stock permanente, Stripe net)?

**Resposta.** Não neste poço. Nove cadeias distintas até quote Stripe, captura TEST, refund, release ou restock: o segundo elo recusa ou fecha a contabilidade. Último ciclo sem classe nova P0/P1.

Não é ATROFIA_ABORT (não se parou em dual Session / bag unlist / seguro plain / chat_media / handle unpublished / review 5★ / TTL resurrect / CORS / mux draft).

--------------------------------------------------
## Findings P0/P1
--------------------------------------------------

Nenhum. Cadeias exercitadas abaixo (INFO / HOLD).

--------------------------------------------------
## Composições (esperado vs obtido)
--------------------------------------------------

### P3+P9 · Catálogo / body depois do hold → Session

| Cadeia | Esperado (caixa) | Obtido |
|--------|------------------|--------|
| Hold 8,50 € → seller `price=1,00` → checkout **com** `product_id`/`seller_id` alheios + `prize_shipping` | underpay / Session no preço novo | **400** `product does not match order` |
| Hold 8,50 € → `price=1,00` → checkout **coerente** | Stripe ~170¢ | **958¢** (`cs_test_a1CbOWm…`) — contrato selado |
| Hold carrier → buyer PATCH `entrega em mão` → checkout | Stripe sem 350¢ portes | **1325¢** (8,50+3,50+protecção) |
| Hold → unlist+`is_sold` + `live_id` forjado | Session mesmo assim | **400** `product is marked sold` |
| Hold → só `list_on_marketplace=false` | Session | **400** `product is not listed` |
| Hold qty=1 → PATCH qty=5 + `price_total` | Stripe 5× | PATCH **403** `order_money_fields_immutable`; checkout **958¢** |

### P2 · Dois caminhos, uma unidade

Stock=1: 2.º INSERT **400** `order_hold_exceeds_stock`. Paralelo: um hold nulo + um Session (um vencedor). Sem duas Sessions no mesmo SKU=1.

### P6 · Dois carris

Hold `MB WAY` → seller PATCH `pago` (200, status `pago`, sem PI) → checkout Stripe: **400** `order status 'pago' cannot start payment`.

### P1 · Mentira → caixa

- JSON `seguro_fleaber_paid` na order MB WAY «pago» sem captura: **400** `chat_system_card_order_not_paid` (não se encadeou).  
- `refund-order` nessa linha: **200** `skipped: not_seguro_fleaber` — sem Stripe net.  
- Buyer PATCH `pago` + `amount_paid_cents=888888`: **403** `order_money_fields_immutable`.  
- Após captura: PATCH `devolvida` (buyer e seller): status permanece `pago` quando o ciclo não chegou a `concluido`; Δwallet **0**. Sem mint.

### P4 · Identidade cruzada

| Ataque | Obtido |
|--------|--------|
| Buyer2 checkout order do buyer1 | **400** `order does not belong to buyer` |
| Buyer2 / seller2 `refund-order` | **403** Sem permissão |
| GET settle `session_id` A + `order_id` B (Session não paga) | **402** pagamento não confirmado |
| POST `fase2_e2e_settle` com JWT | **401** `service_role required` |
| Buyer2 PATCH `concluido` order alheia | **200 []** (0 linhas) |

### P5+P10 · Dois verbos pós-caixa

**Pago (não enviado):** `Future.wait` `refund-order` (seller) ∥ `release` (buyer) ∥ `refund_buyer_wallet`.  
- Refund: cancela `ec49661c-…`, PI `pi_3UAaurH7FWYUN3jh08l7XFfc`, `re_3UAaurH7FWYUN3jh0TEkGNtb`, **590¢**.  
- Release RPC: `false`. Δwallet **0**.  
- `wallet_release_processed_at` **e** `wallet_refund_processed_at` gravados no cancelado (selo anti-mint, não crédito).

**Concluido mão:** buyer `batata_release_seller_wallet_for_order` → `true`, seller **+5,00 €** (5,90 − comissão) na order `c88d2171-…`. 2.ª chamada `false`. `refund-order` **403** `order_refund_blocked_status`. Sem crédito duplo.

INSERT `order_disputes` em cancelado: **403** RLS.

### P7 · Saco

`setup_paid_bag` PI `pi_3UAav7H7FWYUN3jh1BFulKZE` **1115¢** · A `52ee5937-…` 335¢ · B `1b4cafb7-…` 780¢.  
Refund A: **335¢** `re_3UAav7H7FWYUN3jh1V1zmpLn` metadata `fleaber_order_id=A`. B continua **`pago` 780¢**. Soma refunds **335 ≤ 1115**. Restock no SKU A (qty inicial 3) + hold buyer2 = esperado, não oversell.

### P8 · Sombra → caixa

- `create-live-tip-checkout` seller2 + live UUID lixo: **400** (`Invalid tip amount` / object).  
- INSERT `product_offers` 1 €: **403** RLS.

### P9 · Body × RLS / mint directo

- `batata_credit_wallet_once` JWT **403** / anon **401** permission denied.  
- INSERT `wallet_transactions` **403** RLS. PATCH `wallets.balance` **200 []**.

### P10 · Contabilidade desta ronda

Buyer lab inalterado pelos nossos ataques (**46,35 €** no freeze — saldo já vinha de rondas partilhadas).  
Seller: **+5,00 €** só da libertação legítima `c88d2171-…`. O segundo crédito 5,00 € visível no livro (`ecc6161e-…`, 19:30:46Z) é **outra order E2E** (lab partilhado), não double-mint da nossa cadeia.

--------------------------------------------------
## Resposta final
--------------------------------------------------

```
P0 encontrados: 0
P1 encontrados: 0
P2 encontrados: 0

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe cadeia 2–3 elos → caixa P0/P1: NÃO
SESSION underpay (amount Stripe ≠ contrato): NÃO
Dois carris na mesma order: NÃO
Race dois verbos P0/P1: NÃO

Dois buyers + dois sellers: SIM
Fluxo Stripe TEST pago: SIM
Último ciclo nova classe P0/P1: NÃO
ATROFIA: NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: PASS_CEGO_SATURADO
```

**PASS_CEGO_SATURADO:** ≥4 lentes (10), ≥3 composições (9), Stripe TEST pago + contabilidade, ATROFIA=NÃO, último ciclo sem P0/P1 novo.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
