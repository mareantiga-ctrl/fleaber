# Fleaber — Auditoria cega independente G (Red Team)

**FROZEN_AT:** `2026-08-29T16:55:52Z`  
**Projecto staging:** `fxdknzrqjenzqcvnwqqq`  
**Stripe:** TEST (sessões criadas; captura completa da race stock=1 **não** concluída)  
**Produção tocada:** NÃO  
**Fase 4 iniciada:** NÃO  
**Correcções implementadas:** NÃO  
**service_role:** só fixtures, observação e cleanup — nenhum finding de autoridade JWT depende de service_role  

**VEREDICTO:** `C — INCONCLUSIVO`

Zero P0 e zero P1 comprovados com impacto. Invariantes financeiros principais foram atacados em live e não quebraram. A race obrigatória **stock=1 → duas Checkout Sessions → duas capturas líquidas permanentes** não foi levada até captura Stripe TEST (URL de checkout rejeitada pelo Stripe como «link incomplete»). Essa lacuna impede fechar o invariante D/stock com prova de captura.

---

## 1. Âmbito e método

Auditoria adversarial ao estado LIVE de staging. Identidades: anon, buyer lab, seller lab, contas descartáveis, chamadas directas PostgREST / RPC / Edge (sem Flutter).

Três passes:

| Passo | Ficheiro bruto | Foco |
|---|---|---|
| 1 — cobertura | `pass1_raw.json` (369 probes) | RLS, money cols, RPCs, Edges, wallet, reviews, storage |
| 2 — invariantes | `pass2_raw.json` (39 probes) | contrato vs preço cliente, catálogo pós-selo, qty, ofertas, MB WAY FSM, 12× orders + 2 Sessions |
| 3 — composição / races | `pass3_raw.json` + `pass3b_full_urls.json` + `pass3c_raw.json` | MB WAY×stock×wallet×review, payout idempotência, dual session 5,90 €, chat, rifa |

Probes em `tool/redteam_blind_g_20260829/probes/`.

---

## 2. Findings

### P0

Nenhum.

O único HTTP 200 `true` em `batata_release_seller_wallet_for_order` após MB WAY `concluido` **não creditou saldo** (before=after `6.41` €). O `true` corresponde ao ramo fail-closed (`amount_paid_cents` nulo → base 0 → marca flag, sem mint).

### P1

Nenhum comprovado.

### P2

| ID | Título | Actor | Impacto |
|---|---|---|---|
| G-P2-01 | `notifications_view` legível por anon | anon | Feed de favoritos alheios: UUID, nome, foto, título de produto |
| G-P2-02 | Review após MB WAY confirmado pelo seller, sem captura plataforma | buyer+seller | Review inserida; `purchase_verified=false`. Risco reputacional de conluio, mitigado pela flag |
| G-P2-03 | Duas Checkout Sessions Stripe para `stock=1` | buyer | Duas sessões TEST a **590 cêntimos** cada. Captura permanente dupla **NÃO COMPROVADA** |
| G-P2-04 | `live_raffle_winners` SELECT autenticado (incl. `draw_proof`) | buyer JWT | Lista de vencedores + prova de sorteio visível; INSERT bloqueado |

### P3

- `favorites` / `follows` / `live_item_show_events` / views Hub públicas: dados de catálogo/social, não financeiros.
- Listing de `chat_media/product_photos/{sellerId}` pelo buyer: fotos de marketplace (bucket público).
- `send-sms-bulkgate` responde 200 com envelope de erro GoTrue (sem envio).
- URL Stripe devolvida pela Edge tem fragmento `#fidnandhYH…YHgl` **idêntico** entre sessões distintas; o Checkout recusa («This link is incomplete»). Limitou o TEST de captura; não demonstra underpay.

---

## 3. Invariantes financeiros (tentativa de refutação)

| | Invariante | Resultado live |
|---|---|---|
| A | Stripe cobra o contrato servidor | CPI em order com `price_total=0.50` selou **2500** cêntimos e cobrou **2690** (25 € + protecção). Underpay cliente **falhou**. |
| B | Buyer não define preço/qty autoritativos | INSERT `contract_unit_cents=1` / `qty=99` → selo catálogo `2500` / `qty=1`. Qty 99 com stock 2 → `order_quantity_exceeds_stock`. |
| C | Release/refund/payout ≤ fundos plataforma | Release MB WAY sem captura: saldo inalterado. Partial refund sem oferta de disputa: `dispute_refund_offer_required`. |
| D | Uma unidade ≠ duas vendas válidas | 12 orders pendentes + 2 Sessions no mesmo stock=1. **Venda/captura dupla permanente NÃO COMPROVADA.** |
| E | JWT não cria saldo/PI/session authority | PATCH `wallets.balance` 200 com body `[]`, saldo inalterado. INSERT ledger 403. `payout_debit` / `apply_tip_once` / `credit_wallet_once` / `finalize_stripe_order_refund` → 403 EXECUTE. |
| F | Pagamento off-platform ≠ saldo Fleaber | Seller marca MB WAY `pago` (stock 1→0). Release wallet **não** aumenta balance. |
| G | Refund ≤ captura | Refund JWT em order sem PI: 422. Partial 100% sem disputa: erro. |
| H | Parties coerentes | Ghost sale seller INSERT buyer alheio `pago`: `order_buyer_attribution_denied`. CPI com `buyer_id` trocado: `Invalid checkout user`. |
| I | Uma intenção de payout ≤ uma Transfer | Mesma `idempotency_key`: mesmo `transferId`, `idempotent: true`. |
| J | Duas intenções distintas → duas Transfers | Segunda key: segundo `tr_…` (1 cêntimo cada, carteira do seller). Comportamento esperado. |
| K | Catálogo posterior não altera contrato | Seller 25 € → 1 € após order selada; CPI continuou **2690**. |
| L | Offer/bundle só com autoridade | Buyer INSERT offer `accepted` → persistiu **pending**. PATCH accept: `offer_accept_not_authorized`. |

---

## 4. Máquinas de estado (orders)

Estados observados / atacados: `reserva_pendente`, `reservado`, `pago`, `concluido`, tentativa `premio_rifa` via checkout.

| Transição | Quem | Resultado |
|---|---|---|
| INSERT `status=pago` + `amount_paid_cents` (JWT) | buyer | Persistiu `reserva_pendente`, `amount_paid_cents=null` |
| PATCH `reserva_pendente` → `pago` (seguro Fleaber) | buyer | Revertido, fica `reserva_pendente` |
| PATCH `reserva_pendente` → `pago` (MB WAY) | buyer **sem** seller | Revertido |
| PATCH → `reservado` depois `pago` (MB WAY) | **seller** | **Permitido** (oráculo off-platform). `amount_paid_cents` continua null. Stock aplicado. |
| PATCH `pago` MB WAY → `concluido` | buyer | Permitido |
| `prize_shipping=true` em order marketplace | buyer | `order is not a raffle prize` |

O caminho MB WAY **não** é bypass de captura Stripe: é confirmação honorífica do seller, sem mint de wallet.

---

## 5. RPCs SECURITY DEFINER (JWT)

| Função | EXECUTE JWT | Efeito hostil |
|---|---|---|
| `batata_wallet_payout_debit` / `_finish` | 403 | — |
| `batata_wallet_apply_tip_once` | 403 | — |
| `batata_credit_wallet_once` / `debit` | 403 | — |
| `batata_finalize_stripe_order_refund` | 403 | — |
| `batata_create_raffle_prize_order` | 403 | — |
| `batata_release_seller_wallet_for_order` | 200 `true`/`false` | Extra buyer / unpaid → `false` ou true sem crédito |
| `batata_refund_buyer_wallet_for_order` | 200 `false` | sem `devolvida` |
| `batata_process_partial_refund_dispute` | 400 | `order_not_paid` / `dispute_refund_offer_required` |
| `batata_find_user_id_by_email` | 200 | Lab **comprador** → `null`. Seller → UUID (convites staff). Extra user nasceu `vendedor` via INSERT de perfil (não é bypass buyer). |
| `batata_seller_direct_payment_details` | 200 `[]` | sem IBAN para buyer sem relação off-platform válida |
| `batata_send_live_tip_from_wallet` | 403 `not_allowed` | — |
| `batata_is_admin` | 200 `false` | — |

---

## 6. Edge Functions

| Função | Ataque | Resultado |
|---|---|---|
| `create-payment-intent` | amount=50, parties trocadas | 400 `Invalid checkout user` / metadata |
| `create-payment-intent` | order selada 25 €, amount cliente 50 | Session **2690** |
| `create-payment-intent` GET settle session fake | buyer | Stripe `No such checkout.session` |
| `create-payment-intent` GET settle session real **não paga** | buyer | texto «ainda não confirmado»; order continua `reserva_pendente` |
| `refund-order` | buyer | 403 `Sem permissão` |
| `create-connect-account` | buyer `user_id`=seller | 400 cannot create another user |
| `create-mux-live` | buyer | 403 só vendedor |
| `complete-mux-live` | buyer em live seller | 403 |
| `stripe-webhook` | anon sem assinatura | 400 `missing_signature` |
| `ingest-ocr-reservation` | buyer | 401 `missing_device_token` |
| `ps-pairing-claim` | anon `000000` | 400 `invalid_or_expired_code` |
| `delete-test-account` | buyer lab | 403 allowlist |

---

## 7. Races

| Race | n | Estado final |
|---|---|---|
| INSERT orders `stock=1` | 12 | 12 rows `reserva_pendente` (não são vendas) |
| CPI paralelo 2 orders `stock=1` | 2 | **2** `cs_test_…` amount_total=590 |
| Settle GET unpaid | 1 | não marca `pago` |
| Refund paralelo order sem PI | 2 | ambos 422 |
| Payout same key | 2 | 1 Transfer, idempotent |
| Payout keys distintas | 2 | 2 Transfers de 1 ¢ (intencional) |

**Captura Stripe TEST das duas sessões da race:** não concluída. O `checkoutUrl` da Edge é recusado pelo Stripe Checkout («link incomplete»); o fragmento `#fidnandhYH…` é o mesmo em sessões diferentes. Sem `STRIPE_SECRET_KEY` no env local para pagar via API.

---

## 8. Stripe TEST (distinção)

| Nível | Estado |
|---|---|
| SESSION CRIADA | SIM — múltiplas `cs_test_…`, `server_amount_cents` alinhado ao contrato |
| CAPTURA REAL TEST | NÃO nesta auditoria (URL de checkout inválida no browser) |
| CAPTURA LÍQUIDA PERMANENTE dupla | NÃO COMPROVADO |

---

## 9. Superfícies cobertas

AUTH/PROFILES, ORDERS/FSM, PRODUCTS/CATALOG, PRICE/CONTRACT, QTY, CHECKOUT, STRIPE SESSION, SETTLE, RETURN PATH, BAG, WALLET, LEDGER, PAYOUT, STOCK, REFUNDS, PARTIAL REFUNDS, DISPUTES, LIVE/ITEMS/RESERVATIONS/WAITLIST, OFFERS, BUNDLES (INSERT schema miss / pending), RAFFLES, TIPS, CHAT, REVIEWS, STORAGE, MUX, LIVEKIT, PS/OCR, RPCs, SECURITY DEFINER, RLS, TRIGGERS, EDGE.

Chat: extra JWT não lê threads lab; INSERT com `sender_id` alheio **reescreve** para `auth.uid()`.

---

## 10. Lacunas (impedem PASS saturado)

1. Race stock=1 **sem** duas capturas TEST concluídas.  
2. Sem chave Stripe no harness local.  
3. URL Checkout da Edge aparentemente truncada / hash partilhado — bloqueou pagamento no browser.  
4. OpenAPI JWT devolveu 0 paths (anon 401); inventário de RPCs por tentativa + OpenAPI service_role (237 paths).  
5. Não se pagou bag checkout até captura.

---

## 11. Saturação

**SATURAÇÃO = NÃO**

Último passe completo (3/3c) **não** encontrou nova **classe** P0/P1.  
Critério de saturação falha porque a race financeira stock=1→captura não foi fechada com prova de estado final Stripe+BD.

---

## 12. Checklist final

1. P0 aberto encontrado: **NÃO**  
2. Quantos P0? **0**  
3. P1 aberto encontrado: **NÃO**  
4. Quantos P1? **0**  
5. Buyer manipula preço autoritativo: **NÃO**  
6. Buyer manipula qty autoritativa: **NÃO**  
7. Seller falsifica pagamento **plataforma** (captura/saldo): **NÃO** (MB WAY `pago` é off-platform, sem mint)  
8. JWT cria saldo/fundos: **NÃO**  
9. Refund excede captura: **NÃO** (não observado)  
10. Release+refund cria dinheiro líquido: **NÃO**  
11. Payout duplica Transfer da **mesma** intenção: **NÃO**  
12. Stock=1 → duas vendas válidas: **NÃO COMPROVADO**  
13. Stock=1 → duas capturas líquidas permanentes: **NÃO COMPROVADO**  
14. Bypass capacidade/reserva: **NÃO** (buyer não self-accept; qty 99 recusada)  
15. Cross-user financeiro: **NÃO**  
16. Cross-user dados sensíveis: **NÃO** (P2 social `notifications_view`; IBAN/stream_key/chat alheio bloqueados)  
17. Buyer assume seller/admin: **NÃO** (`user_type` imutável no UPDATE)  
18. Seller assume buyer/admin: **NÃO**  
19. Reviews forjadas/duplicadas: **NÃO** (duplicate 409; author_role seller no INSERT do buyer não elevou; off-platform marcada `purchase_verified=false`)  
20. RPC DEFINER perigoso: **NÃO** (EXECUTE privilegiado recusado; release JWT não minta)  
21. RLS crítico quebrado: **NÃO**  
22. Edge confia autoridade do cliente: **NÃO** (amount/parties/qty ignorados ou rejeitados)  
23. Conclusão crítica NÃO COMPROVADA: **SIM** (12/13)  
24. Regressão funcional relevante: **NÃO** (fora de âmbito de produto; leftover live de probe Mux foi `ended`)  
25. Último passe nova classe P0/P1: **NÃO**  
26. Saturação atingida: **NÃO**  
27. Produção tocada: **NÃO**  
28. Fase 4 iniciada: **NÃO**

---

## 13. Tabela de findings

| ID | Sev | Título | Actor | Pré-condições | Reprodução | Impacto | Estado |
|---|---|---|---|---|---|---|---|
| G-P2-01 | P2 | notifications_view anon | anon | nenhuma | `GET /rest/v1/notifications_view` com anon key | PII social (UUID, nome, foto) | ABERTO |
| G-P2-02 | P2 | Review MB WAY sem captura | buyer+seller | order MB WAY `pago` pelo seller | INSERT reviews; `purchase_verified=false` | Reputação sem fundos plataforma | ABERTO (flag mitiga) |
| G-P2-03 | P2 | Dual Session stock=1 | buyer | produto qty=1, 2 orders | 2× `create-payment-intent` → 2 `cs_test` @ 590 | Risco de oversell **se** ambas capturarem; captura não provada | ABERTO / NÃO COMPROVADO captura |
| G-P2-04 | P2 | Winners rifa + draw_proof | buyer JWT | raffle existente | `GET live_raffle_winners` | Visibilidade de prova de sorteio | ABERTO (INSERT 403) |

---

## 14. Evidência (IDs, sem segredos)

- Contrato barato: order `5adae88d-…` `contract_unit_cents=2500`, CPI `server_amount_cents=2690`.  
- Catálogo drop: CPI pós 25→1 € ainda 2690.  
- MB WAY: order `90b06d7c-…` `pago`/`concluido`, product qty 0, wallet 6.41→6.41, review `e8287d77-…` `purchase_verified=false`.  
- Race: product `cf05e4c4-…`, orders `67c0e047-…` / `4c1ec758-…`, sessions `cs_test_a1Q8itcX…` / `cs_test_a1AFH3dK…` amount 590.  
- Payout: `tr_1U9pSbH7FWYUN3jhk4oUwoEE` (retry mesma key) vs `tr_1U9pSfH7FWYUN3jh8CnPKBCy` (key nova).  
- Chat spoof: mensagem `id=796` `sender_id` = buyer, não seller.

JSON: `pass1_raw.json`, `pass2_raw.json`, `pass3_raw.json`, `pass3b_full_urls.json`, `frozen.json`.
