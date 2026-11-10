# FLEABER — Auditoria cega independente (Red Team)

**Ambiente:** Supabase STAGING `fxdknzrqjenzqcvnwqqq` · Stripe **TEST** apenas  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO  
**FROZEN_AT:** `2026-08-29T14:40:00Z`

**Auditor:** Red Team independente (Application Security)  
**Método:** código actual + schema LIVE + ataques com anon / JWT buyer / JWT seller / JWT fresco. `service_role` só para fixtures, observação, evidência e cleanup.

**Veredicto:** `D — PASS_CEGO_SATURADO`

---

## 1. Sumário executivo

Não foi comprovado nenhum P0 nem P1 no estado LIVE actual.

Ataques de autoridade financeira (preço, quantidade, Stripe IDs, mint de carteira, payout cruzado, refund cruzado, JWT `alg=none`, settle E2E) falharam com JWT de atacante.

Stock=1 admite duas *Checkout Sessions* JWT em paralelo; settle **sem pagamento** não marca `pago`. No ciclo Stripe TEST (PaymentIntent confirmido + settle, via harness de staging, não JWT) uma unidade produziu **uma** venda `pago` e a segunda captura foi **reembolsada** (`oversell_refunded`).

Foi identificado um **P2** de bloqueio de capacidade no saco do directo: INSERT de reserva `pending` com `requested_qty=99` reduz `available_qty` a 0 sem consumir `accepted`. O comprador não consegue auto-aceitar; o vendedor não consegue aceitar qty=99 (`qty_exceeds_stock`). Após `expired`, o stock visível voltou a 5.

---

## 2. Findings

### RT-E-P2-01 — Reserva live `pending` com qty enorme bloqueia `available_qty`

| Campo | Valor |
|---|---|
| **ID** | RT-E-P2-01 |
| **Severidade** | P2 |
| **Título** | Buyer insere reserva live pending qty=99 e zera available_qty |
| **Actor** | JWT buyer (e JWT fresco em paralelo) |
| **Pré-condições** | Directo activo; `live_item` com stock 5; política INSERT em `live_reservation_requests` |
| **Reprodução** | `POST /rest/v1/live_reservation_requests` com `requested_qty=99`, `status=accepted` (persistido como `pending`). Observar `rpc batata_live_item_stock`. |
| **Impacto** | Griefing do saco do directo: `available_qty=0`, `pending_bag_qty=200`. Não produz venda de 99 unidades. PATCH buyer→accepted = vazio. PATCH seller→accepted = `qty_exceeds_stock`. Convert RPC = 403. |
| **Estado** | OPEN |
| **Evidência** | `tool/redteam_indep_e_20260829/pass2_raw.json` (race `two_reservations_qty99`); `pass3_raw.json` (accept bloqueado; expire restaurou available=5) |

Não elevado a P1: não há captura económica nem reserva `accepted` acima do stock.

---

## 3. Superfícies testadas

AUTH / PROFILES · ORDERS · ORDER FSM · PRODUCTS · CATALOG · PRICE / CONTRACT · QUANTITY AUTHORITY · CHECKOUT · STRIPE SESSION · SETTLE · WEBHOOK · RETURN PATH · BAG / CART · WALLET · LEDGER · PAYOUT · STOCK · REFUNDS · PARTIAL REFUNDS · DISPUTES · LIVE · LIVE ITEMS · LIVE RESERVATIONS · WAITLIST / QUEUE · OFFERS / PROPOSALS · BUNDLES / DISCOUNTS · RAFFLES (RPC) · TIPS (Edge) · CHAT · REVIEWS · STORAGE · MUX · LIVEKIT · PS/OCR · RPCs · SECURITY DEFINER · GRANTs (via EXECUTE) · RLS · TRIGGERS (via efeito) · EDGE FUNCTIONS

OpenAPI LIVE (service): **69** tabelas/views, **168** RPCs. 60 RPCs “quentes” sondadas.

---

## 4. Invariantes financeiros

| ID | Invariante | Resultado LIVE |
|---|---|---|
| A | Stripe cobra o contrato servidor | **Sustido.** Cliente `amount=50` + `price_total=0.5` num item 20 € → Session `server_amount_cents=2165` (20 € + protecção). |
| B | Buyer não define preço/qty autoritativos | **Sustido no checkout.** INSERT qty=99 → `order_quantity_exceeds_stock`. PATCH `contract_unit_cents=1` + `status=pago` → persistido `reserva_pendente`, `contract_unit_cents=2000`, `price_total=21.65`. |
| C | release/refund/payout ≤ fundos legítimos | **Não refutado.** Refund JWT buyer = 403. Payout buyer noutro user_id = bloqueado. Dual payout mesma key → 1 Transfer. |
| D | Uma unidade ≠ duas vendas válidas | **Sustido no settle TEST.** Winner `pago` stock=0; loser `cancelado` + refund 590 cêntimos. |
| E | JWT não cria saldo/ledger/PI/payout | **Sustido.** INSERT wallet 403; PATCH balance `[]`; credit/debit/payout RPCs 403. |
| F | Pagamento off-platform não minta saldo | **Sustido.** Seller PATCH MB WAY → `pago`; wallet seller **6.41 → 6.41**. |
| G | Refund ≤ captura | **Não refutado** (refund buyer 403; oversell refund = captura do PI perdedor). |
| H | Parties coerentes | INSERT order noutro `buyer_id` = 403 RLS. |
| I | 1 intenção payout ≤ 1 Transfer | Dual requests mesma/diferente key colapsaram por par a 1 `transferId`. |
| J | 2 intenções distintas podem 2 Transfers | Dois pares sequenciais produziram `tr_…ZU7` e `tr_…J9RE` (2 € debitados no total). |
| K | Catálogo posterior não altera contrato | Após `products.price=1`, checkout continuou **2165**. |
| L | Offer/bundle/reservation só com autoridade | Bundle INSERT buyer 403. Prize shipping sem rifa 400. |

---

## 5. Máquinas de estado (ordens)

Estados observados/atacados: `reserva_pendente`, `aguarda_confirmacao`, `pago`, `cancelado`, `premio_rifa` (via flag checkout).

| Transição | Actor | Resultado |
|---|---|---|
| INSERT `status=pago` | buyer JWT | Persistido **`reserva_pendente`** (trigger) |
| PATCH `pago` + PI fake | buyer JWT | Status permanece `reserva_pendente`; PI não gravado |
| PATCH `pago` MB WAY | seller JWT | **`pago`** (fluxo off-platform); **sem** mint de wallet |
| GET settle Session **não paga** | anon | HTTP 200 texto «ainda não confirmado»; order **não** passa a pago |

---

## 6. Races

| Race | Resultado |
|---|---|
| 2 orders stock=1 | **10/10** ambos INSERT `reserva_pendente` |
| 2 Checkout Sessions stock=1 | **2× HTTP 200**, 905 cêntimos cada |
| GET settle das Sessions **não pagas** | orders continuam `reserva_pendente` |
| 2 PI TEST + settle stock=1 (harness) | 1 `pago` + 1 `oversell_refunded` (refund succeeded 590) |
| 2 refunds JWT | 403 / 422 |
| 2 payouts keys distintas | mesmo `transferId` (colapso) |
| 2 payouts mesma key | 1 Transfer |
| 2 reviews mesma order | 201 depois **409 `review_duplicate`** |
| 2 reservas live qty=99 | 2× 201 `pending`; available_qty 0 até expire |

---

## 7. Stripe TEST

| Camada | Resultado |
|---|---|
| SESSION CRIADA | Sim — JWT buyer/fresh, 905 cêntimos, stock=1, duas Sessions |
| CAPTURA via Checkout hosted | **Não completada** — URL Stripe devolveu «This link is incomplete» no browser de auditoria (hash de Checkout) |
| GET return path sem pagamento | Não marca `pago` |
| CAPTURA REAL TEST (PaymentIntent `pm_card_visa` + settle, secret de staging **não JWT**) | 2 PI `succeeded`; 1 venda; 1 refund oversell |
| CAPTURA LÍQUIDA PERMANENTE | **1** unidade vendida; wallet seller inalterada (6.41) no instante do settle |

---

## 8. RPC / SECURITY DEFINER / RLS (síntese)

- `batata_wallet_payout_debit` / `finish` / `ensure_wallet` / `credit_wallet_once` / `finalize_stripe_order_refund`: **EXECUTE negado** (403) a anon/buyer.
- `batata_release_seller_wallet_for_order` e `batata_refund_buyer_wallet_for_order`: JWT buyer HTTP 200 corpo `false` (sem efeito em UUID inexistente).
- `batata_admin_list_profiles` / `batata_admin_resolve_dispute`: «Acesso negado» / «Apenas administradores».
- `staging_restore_stock_before_nuke`: 403.
- RLS: wallets alheias `[]`; chats alheios `[]`; stream keys em `lives` 401/403; webhook sem assinatura 400; `fase2_e2e_settle` com JWT buyer 401.
- JWT `alg=none`: 401 `Wrong or unsupported encoding algorithm`.

---

## 9. Matriz (extracto crítico)

Ver JSON completo. Amostra:

| SUPERFÍCIE | ATAQUE | IDENTIDADE | RESULTADO | IMPACTO | SEVERIDADE | EVIDÊNCIA |
|---|---|---|---|---|---|---|
| CHECKOUT | amount=50 item=20€ | buyer | 2165 cêntimos | cliente ignorado | — | pass3_raw |
| CHECKOUT | prize_shipping | buyer | 400 not raffle prize | — | — | pass3_raw |
| ORDERS | INSERT pago | buyer | demote reserva_pendente | — | — | pass2_raw |
| ORDERS | INSERT qty=99 | buyer | 400 exceeds_stock | — | — | pass2_raw |
| ORDERS | buyer_id alheio | buyer | 403 RLS | — | — | pass2_raw |
| WALLETS | INSERT 99999 | fresh | 403 | — | — | frozen_raw |
| PAYOUT | user_id seller | buyer | 400 cannot create another | — | — | frozen_raw |
| WEBHOOK | sem signature | anon | 400 missing_signature | — | — | frozen_raw |
| MUX | create live | buyer | 403 só vendedor | — | — | frozen_raw |
| LIVE RESERVATIONS | qty=99 pending | buyer+fresh | available_qty=0 | griefing saco | P2 | pass2/pass3 |
| STOCK settle TEST | 2 PI stock=1 | harness | 1 pago + 1 refund | sem double-sale | — | pass3c_capture |
| REVIEWS | sem order | fresh | 400 review_order_required | — | — | pass2_raw |
| REVIEWS | duplicar | buyer | 409 review_duplicate | — | — | pass2_raw |

---

## 10. Lacunas

- Checkout hosted Stripe TEST não foi pago no browser (link incompleto). Dual-session JWT **não** tem captura hosted comprovada; o caminho de settle TEST (PI) foi medido à parte.
- Assinaturas de alguns RPCs (404 PGRST202) — retried com hints; os financeiros continuaram 403 ou `false`.
- PS pairing: código 000000 inválido; OCR sem device token válido.
- Rifa: sem fluxo completo winner×order (RPCs draw/create prize 404 sem params; não se fabricaram winners).
- Partial refund dispute: assinatura RPC não casou.
- Review 5★ inserida em order lab já `concluido` `ff715140-…` (primeiro INSERT 201; segundo 409). Efeito colateral de laboratório.
- Directo `4e0d4898-…` já estava `live` (não iniciado por esta auditoria). Reservas de probe expiradas; `available_qty` restaurou a **5**.

---

## 11. Saturação

- Superfícies críticas atacadas: SIM  
- Invariantes financeiros testados: SIM  
- Composição executada: SIM (order×catalog×checkout, stock×sessions×settle, reservation×stock, review×order, payout×retry, webhook, bag IDs)  
- Races executadas: SIM (incl. 10× stock=1 INSERT)  
- Último passe completo (pass 3 + 3b/3c) **não** encontrou nova classe P0/P1  
- **SATURAÇÃO = SIM**

---

## 12. Checklist final

1. P0 aberto encontrado: **NÃO**  
2. Quantos P0? **0**  
3. P1 aberto encontrado: **NÃO**  
4. Quantos P1? **0**  
5. Buyer manipula preço autoritativo: **NÃO**  
6. Buyer manipula qty autoritativa: **NÃO** (INSERT 99 rejeitado; checkout usa contrato)  
7. Seller falsifica pagamento plataforma: **NÃO** (MB WAY `pago` sem mint de wallet)  
8. JWT cria saldo/fundos: **NÃO**  
9. Refund excede captura: **NÃO** (não comprovado caminho que exceda; oversell = captura do PI)  
10. Release+refund cria dinheiro líquido: **NÃO**  
11. Payout duplica Transfer indevidamente: **NÃO** (colapso idempotente)  
12. Stock=1 duas vendas válidas: **NÃO** (settle TEST: 1 pago + 1 refund)  
13. Stock=1 duas capturas líquidas permanentes: **NÃO**  
14. Bypass de capacidade/reserva: **NÃO** para venda aceite; **P2** lock pending qty  
15. Cross-user financeiro: **NÃO**  
16. Cross-user dados sensíveis: **NÃO** comprovado (PII seller `[]`; fotos de catálogo 200 = esperado público)  
17. Buyer assume seller/admin: **NÃO** (`user_type=admin` não persiste; mux 403)  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO** (sem order 400; dup 409)  
20. RPC SECURITY DEFINER perigoso: **NÃO** comprovado com JWT  
21. RLS crítico quebrado: **NÃO**  
22. Edge confia autoridade do cliente: **NÃO** (amount/prize/user_id ignorados ou bloqueados)  
23. Conclusão crítica NÃO COMPROVADA: **SIM** — captura hosted JWT das duas Sessions (mitigada por settle TEST e GET unpaid)  
24. Regressão funcional relevante: **NÃO** (auditoria não alterou produto)  
25. Último passe encontrou nova classe P0/P1: **NÃO**  
26. Saturação atingida: **SIM**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

---

## 13. Veredicto

**D — PASS_CEGO_SATURADO**

Zero P0, zero P1, invariantes críticos atacados, composição e races executadas, último passe sem nova classe P0/P1, saturação = SIM.

P2 OPEN: RT-E-P2-01 (pending live qty).

---

## 14. Artefactos

| Ficheiro | Conteúdo |
|---|---|
| `tool/redteam_indep_e_20260829/FROZEN_REPORT.md` | este relatório |
| `tool/redteam_indep_e_20260829/frozen.json` | machine-readable |
| `tool/redteam_indep_e_20260829_probe.dart` | pass 1 |
| `tool/redteam_indep_e_20260829_pass2.dart` | pass 2 |
| `tool/redteam_indep_e_20260829_pass3.dart` | pass 3 |
| `tool/redteam_indep_e_20260829/frozen_raw.json` | pass 1 bruto |
| `tool/redteam_indep_e_20260829/pass2_raw.json` | pass 2 bruto |
| `tool/redteam_indep_e_20260829/pass3_raw.json` | pass 3 bruto |
| `tool/redteam_indep_e_20260829/pass3c_capture.json` | settle unpaid + oversell TEST |
| `tool/redteam_indep_e_20260829/openapi_rpcs.json` | inventário LIVE |
