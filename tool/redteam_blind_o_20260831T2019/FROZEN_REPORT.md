AUDITOR: REDTEAM_BLIND_O_DISPUTA_ENVIO_v1
FROZEN_AT: 2026-08-31T19:40:00Z
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [O1, O2, O3, O4, O5, O6, O7, O8]
VEREDICTO: FAIL_P1

Prefixo: `RTO-20260831T2019`
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`pm_card_visa`) · sem produção · sem Fase 4.
Atacante = JWT / anon. `service_role` só fixture (`setup_paid_order`) e observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------

Depois de pago, o envio / a disputa / a devolução / o reembolso no meio do caos ainda dão dinheiro, stock ou um estado que a UI esconde?

**Resposta:** o núcleo RLS da disputa (só `concluido`/`entregue`, 1× por encomenda, % só do vendedor) e o selo de portes pós-pago **agem**. O JWT **não** minta reembolso sem oferta do vendedor.

Fica **P1** porque: (1) o vendedor **aborta** um `pedido_devolucao` com `PATCH enviado`; (2) `devolvida` **relista stock** e carimba flags de reembolso **sem** pagar o comprador — o Stripe só fecha se alguém chamar `refund-order` depois.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Pass 1 = catálogo RPC + disputa em `pago`/`enviado` (403) + selo `shipping_method` + `enviado` sem captura (não cola).  
Não se usou como vitória: dual Session, bag unlist, seguro plain, list `chat_media`, handle unpublished, DELETE review→5★, TTL resurrect, CORS, mux, mint pós-payout, seller `PATCH` disputa `resolvida` clássico, `pago`→`concluido` sem enviado, OCR 1442.

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| O1 | Disputa `pago`/`enviado`/B2/seller/anon = 403 RLS. `concluido` = 201. Reopen após `resolvida` = 409. Reply B2 = 403. Escalate: `status=escalada_fleaber` mas `current_turn` fica `vendedor` (P3). |
| O2 | **P1** seller `enviado` depois de `pedido_devolucao` cola. Release com disputa aberta + `enviado` = `false`. |
| O3 | **P1** `devolvida` qty 1→2, Δwallet 0, `stripe_refund_id` null, flags refund/release carimbados, 0 txns. `refund-order` *depois* ainda pode anular o PI (não é automático). |
| O4 | Self-deal 100% INSERT/PATCH: percent stripped, RPC `dispute_refund_offer_required`. Oferta seller 100%: wallet +5,90 €, PI sem refund, `refund-order` 403 `pedido_devolucao` (**P2** carris). |
| O5 | `concluido` a partir de `enviado` OK (caminho mão/carrier). Race `concluido`∥disputa: disputa 403 (vê `enviado`). Buyer pode `pedido_devolucao`→`concluido` e libertar se fechar a disputa. |
| O6 | Portes congelados (`order_shipping_frozen_after_payment`). `enviado` sem captura não cola. **P2** `proof_url` URL arbitrária. Colunas tracking inexistentes. |
| O7 | `return_label_url` evil = 403. **P2** wrap `https://fleaber.app/https://evil.example/x` aceite. `return_label_created_at` JWT cola; RPC refund não minta. |
| O8 | Race parcial∥`devolvida`: RPC `false`, sem crédito duplo. Stock mesmo assim relistado (O3). |

--------------------------------------------------
CONTABILIDADE
--------------------------------------------------

- Captura típica: **5,90 €** (`amount_paid_cents=590`) · crédito venda seller **5,00 €**.
- Wallets início da ronda O: buyer **40,45 €** · seller **0,00 €**.
- Fim pass 3: buyer **46,35 €** (+5,90 oferta 100% O4) · seller **10,00 €** (2× release 5,00 em encomendas `concluido` sem disputa aberta).
- Confirmação de receção: buyer JWT `PATCH concluido` após `enviado` — **não partida**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTO-O2-seller-abort-return · P1 · O2

**Actor:** seller JWT.

**Passos:**
1. Stripe TEST → `enviado` → `concluido`. Order `394d2e9c-bb93-46d9-82bb-ca76f4847fec`.
2. Buyer `POST order_disputes` + `PATCH pedido_devolucao` (status confirmado).
3. Seller `PATCH status=enviado`.

**Esperado:** devolução em curso imutável para o vendedor (ou recusa explícita com disputa intacta).

**Obtido:** status **`enviado`**. `completed_at` antigo mantém-se. Release JWT `false` (disputa ainda aberta). Buyer **não** pode voltar a `pedido_devolucao` a partir de `enviado` (FSM só a partir de `concluido`/`entregue`) — tem de reconfirmar receção.

**Prova:** `pass3.json` → `p3.o2.reenviado`. PI `pi_3UAax2H7FWYUN3jh16vS17hs`.

**Severidade P1:** o vendedor desfaz o pedido de devolução com um PATCH que a UI de envio já conhece; o comprador fica num estado que a disputa já não descreve.

---

### RTO-O3-devolvida-stock-sem-reembolso · P1 · O3

**Actor:** seller JWT `PATCH devolvida` (buyer só marcou a logística de volta, sem prova de envio).

**Passos:**
1. Stripe TEST 5,90 € → `concluido` + disputa + `pedido_devolucao` → `em_devolucao` → `devolucao_entregue`.
2. Seller `PATCH status=devolvida`. Order `c38658b5-e6c8-4a4b-ba03-0a146a7b3d02`.
3. Oráculo: qty produto **1 → 2**, `is_sold=false`, `list_on_marketplace=true`, `stock_units_applied=null`.
4. Δ buyer **0**, Δ seller **0**, `wallet_transactions` vazio, `stripe_refund_id` **null**. Flags `wallet_refund_processed_at` + `wallet_release_processed_at` preenchidos.
5. `refund-order` *chamado depois pelo auditor*: 200 com `re_3UAax7H7FWYUN3jh0fcSSuuQ` — o PI **pode** ser anulado, mas **não** foi no trigger.

**Esperado:** dinheiro (Stripe ou wallet) = captura **antes** (ou no mesmo passo atómico) de relistar stock.

**Obtido:** stock à venda de novo com o artigo ainda no comprador e o PI capturado, até alguém se lembrar do `refund-order`.

**Prova:** `pass3.json` → `p3.o3.devolvida_stripe`. Réplica pass 2: orders `00a531cd-…` e `fe1b050a-…` (qty 2, 0 txns).

**Severidade P1:** oversell + comprador por pagar. Não é P0 de mint extra (Δwallet 0). O `refund-order` posterior mostra que o carril Stripe existe — só não está amarrado à `devolvida`.

---

### RTO-O4-wallet-mint-sem-stripe · P2 · O4

**Actor:** buyer JWT após **oferta legítima** do vendedor (`seller_refund_percent=100`).

**Passos:**
1. Order `10576d71-f0a7-4270-9bb1-b7a784b3a880`, PI `pi_3UAauPH7FWYUN3jh1IsQmiZB`.
2. Disputa + `pedido_devolucao` + seller PATCH 100% `partial_refund`.
3. `rpc batata_process_partial_refund_dispute` → `true`, txn `reembolso` **+5,90 €**.
4. `refund-order` seller → 403 `order_refund_blocked_status` / `pedido_devolucao`.
5. Observação pass 3: `stripe_refund_id` continua null; stock **não** restaurado (`quantity=1`, `stock_units_applied=1`).

**Esperado:** fechar o PI na mesma transacção, ou recusar o mint até haver refund Stripe.

**Obtido:** carteira paga, captura Stripe aberta, Edge de refund bloqueada pelo estado da disputa.

**Severidade P2:** o vendedor **consentiu** o 100%. Não há loot extra. Carris carteira vs Stripe divergem; o comprador fica com item + saldo Fleaber enquanto o PI não fecha.

---

### RTO-O6-proof-url-unvalidated · P2 · O6

**Actor:** seller JWT (pass 1) e buyer JWT (pass 2).

**Passos:** `PATCH orders.proof_url=https://evil.example/…` após captura → 200. Persiste (`8e4b7057-…`, `00185e2c-…`).

**Esperado:** storage Fleaber ou imutável pós-pago.

**Obtido:** URL arbitrária (tracking/prova forjada na UI).

---

### RTO-O7-label-url-wrap · P2 · O7

**Actor:** buyer JWT.

**Passos:** `https://evil.example/label.pdf` → 403 `dispute_return_label_url_denied`.  
`https://fleaber.app/https://evil.example/x` → 200, gravado em `8e93bd4a-…`.

**Esperado:** prefixo Fleaber ≠ open-redirect wrap.

**Obtido:** allowlist `like 'https://fleaber.app/%'` aceita o wrap.

---

### Notas (não finding / P3)

- RPC `batata_order_allows_seller_stripe_refund`: JWT 403 (só service) — Edge usa service, OK.
- `batata_refund_buyer_wallet_for_order` / `release` JWT: `false` sem efeito indevido quando a disputa está aberta ou o PI não tem refund.
- Escalate: `escalada_fleaber` + `current_turn` revertido para `vendedor` (trigger anti-admin).
- `buyer_decision=accepted_partial_refund` no INSERT não chega a mintar (percent stripped).

--------------------------------------------------
PROVAS
--------------------------------------------------

`tool/redteam_blind_o_20260831T2019/pass1.json`  
`tool/redteam_blind_o_20260831T2019/pass2.json`  
`tool/redteam_blind_o_20260831T2019/pass3.json`

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
