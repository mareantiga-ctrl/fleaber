AUDITOR: REDTEAM_BLIND_L_CRON_AUTO_v1
FROZEN_AT: 2026-08-31T17:14:00Z
production_touched: false
fase4: false
corrections_applied: false
VEREDICTO: FAIL_P1

Prefixo: `RTL-20260831T1802`
Staging: `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`pm_card_visa` / `sk_test_`) · sem produção · sem Fase 4.
Atacante = JWT / anon. `service_role` só fixture, oráculo de job (`p_now`) e observação.

--------------------------------------------------
MISSÃO
--------------------------------------------------

Jobs e estados automáticos ainda dão dinheiro, stock, feedback forjado ou libertação indevida?

**Resposta:** o JWT **não** dispara os crons (auto-feedback, expire offers, egress cleanup). O relógio de 48h com `now()` é respeitado. Duplo cron é idempotente. Race humana ∥ cron **não** duplica crédito. Refund após `concluido` recusa. Review humana 5★ **liberta** a carteira (caminho vivo).

Fica **P1** porque o comprador **apaga** reviews (incluindo as automáticas do cron) e o job de 48h **volta a forjar 5★**. O TTL de hold de reserva **não tem job** e o JWT **reescreve** `reservation_expires_at`.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Pass 1 = catálogo + EXECUTE de jobs (`auto_feedback`, `expire_product_offers`, `livekit-egress-cleanup`, schemas cron/vault).  
Não se repetiu: dual Session, bag unlist, plain→JSON, mint pós-payout, cancel hold, Hub paused, pairing ended, offer morto como tema de Pass 1, helper escalate.

L4 testou o **relógio** (cron expire + PATCH TTL), não o «accept de SKU morto».

--------------------------------------------------
LENTES
--------------------------------------------------

| Lente | Resultado |
|-------|-----------|
| L1 | JWT/anon 403/401 em `batata_generate_auto_feedback`, `batata_expire_product_offers`, `batata_invoke_livekit_egress_cleanup`. Edge cleanup 401. cron/vault REST 404. |
| L2 | `now()` em order com segundos: 0 reviews. `pago` + `completed_at` antigo: ignorado. 2.º cron: Δwallet 0, reviews estáveis. JWT `p_now` 403. |
| L3 | Humana 5★ → 201 + `wallet_release` + **+5,00 €**. Humana 1★ → 201, **sem** release. |
| L4 | Offer: cron marca `expired`; seller accept fica `expired`; resurrect `pending` recusado. Hold: **sem job**; JWT estende TTL. |
| L5 | `Future.wait` review∥cron → humana 409 `review_duplicate`, cron 1× venda +5,00 €. refund-order∥cron → refund 403 `order_refund_blocked_status`, cron liberta 1×. |
| L6 | `completed_at` JWT 200 mas valor **revertido**. Flags release/auto_feedback 403. `is_automatic=true` JWT → persistido **false**. **DELETE reviews permitido** (P1). |
| L7 | Cada order Stripe 5,90 € → crédito venda **5,00 €** (1 txn `venda`). Race sem duplo crédito. |

--------------------------------------------------
CONTABILIDADE (amostra)
--------------------------------------------------

- Seller wallet início da ronda L: **0,00 €**.
- Após 1.º cron global de fixture (`p_now`+2d service, oráculo): **70,00 €** (inclui libertação de encomendas `concluido` já elegíveis no staging — efeito de relógio service, **não** JWT).
- Order `29bff199-…`: 1 txn `venda` 5,00 €; 2.º cron Δ=0.
- Humana 5★ `ce48570d-…`: Δ seller **+5,00 €** sem cron.
- Race `5b789612-…`: 1 txn `venda` 5,00 €.

Confirmação de receção em mão: buyer JWT `PATCH status=concluido` após `enviado` — **não partida**.

--------------------------------------------------
FINDINGS
--------------------------------------------------

### RTL-L6-delete-then-cron-5star · P1 · L6

**Actor:** buyer JWT `DELETE reviews` + cron `batata_generate_auto_feedback`.

**Passos:**
1. Stripe TEST → `enviado` → `concluido` (mão). Order `00db216a-3da5-4702-997c-e404db64029b`.
2. `POST reviews` stars=1 → 201. `wallet_release_processed_at` null, Δ seller 0.
3. `DELETE reviews?id=eq.d3d47c45-…` JWT → 200.
4. Fixture: `completed_at` −49h (service). `rpc batata_generate_auto_feedback p_now` futuro (service = job).

**Esperado:** a 1★ fica, ou o cron não inventa 5★ depois de o comprador ter avaliado (mesmo que apague o cartão).

**Obtido:** duas reviews automáticas 5★ (`is_automatic=true`, comprador+vendedor), comentário «Avaliação automática…». Cron HTTP 200, inseriu 3 (esta order + órbita).

**Prova:** `pass3.json` → `p3.l6.delete`, `p3.l6.cron_after_delete`. Review ids `572ddb99-…` / `7ab88476-…`.

**Severidade P1:** reputação forjada (1★ → 5★) via job de 48h; não é P0 de dinheiro extra (o release às 48h também ocorreria sem review).

---

### RTL-L6-delete-auto-feedback · P1 · L6

**Actor:** buyer JWT `DELETE` sobre review `is_automatic=true`.

**Passos:**
1. Cron já tinha gerado 5★ automática no order `d3c7f45a-…` (review `8e8c2d40-1941-4e6a-a73f-d656f4783af7`).
2. `DELETE reviews?id=eq.8e8c2d40-…` com JWT comprador (`buyer_id` = auth.uid()).

**Esperado:** reviews do job imutáveis (sem DELETE, ou policy `is_automatic`).

**Obtido:** 200; `GET` posterior lista vazia.

**Prova:** `pass4.json` → `p4.l6.del_auto`. Policy viva: `reviews_delete_own` (`buyer_id = auth.uid()`).

**Composição L6→L6:** apagar 1★ → cron 5★ → apagar 5★ automática → perfil sem rasto e `auto_feedback_processed_at` já preenchido (o job **não** volta a correr).

---

### RTL-L4-hold-ttl-resurrect · P1 · L4

**Actor:** buyer JWT `PATCH orders.reservation_expires_at`.

**Passos:**
1. `POST orders` JWT `reserva_pendente`, `reservation_expires_at` = now−2h. Order `691f7e5f-630e-4a4d-a9c0-d602cc21da27`.
2. `PATCH reservation_expires_at` = now+7d.

**Esperado:** TTL de hold só o vendedor / o job; após caducar, imutável.

**Obtido:** 200; valor `2026-09-07T17:13:07.481303+00:00` (era `2026-08-31T15:13:04.018228+00:00`).

**Prova:** `pass4.json` → `p4.l4.hold.resurrect`. A app usa este campo no aceite de reserva (`+5d` em `batata_reservation_actions.dart`).

**Nota:** não há job que leia este TTL (finding seguinte). O relógio é **só** o que o JWT quiser mostrar / que um cron futuro possa vir a confiar.

---

### RTL-L4-hold-no-cron · P2 · L4

**Actor:** observação (service tenta RPCs de expire hold — **não existem**).

**Passos:**
1. Hold `reserva_pendente` com `reservation_expires_at` no passado (`691f7e5f-…`).
2. JWT `batata_expire_product_offers` → 403 (não é expire de hold).
3. Service: `batata_expire_pending_orders`, `batata_release_expired_reservations`, `batata_claim_expired_reservations`, `batata_expire_reservations`, `batata_expire_holds` → todos **404** PGRST202.

**Esperado:** job marca cancelado/expirado e deixa de contar no hold de stock.

**Obtido:** status continua `reserva_pendente`. Produto `19faa1e7-…` quantity=2, `stock_units_applied` null. TTL −2h ignorado.

**Prova:** `pass4.json` → `p4.l4.hold.after`.

**P2:** stock/capacidade de hold pode ficar presa para sempre; não é desvio de dinheiro nesta prova.

--------------------------------------------------
FECHADO NESTA RONDA (não finding)
--------------------------------------------------

- L1: JWT não executa crons; `p_now` futuro recusado; GET rpc 403; edge `livekit-egress-cleanup` 401 (JWT, secret vazio, secret `x`).
- L2: auto-feedback com `now()` não dispara cedo; order `pago` excluído; 2.º cron idempotente.
- L3: review humana 5★ **não** está morta — liberta 5,00 € na hora.
- L4 offer: após cron, `status=expired` resiste a accept e a resurrect `pending` (HTTP 200 silencioso no status). JWT **consegue** PATCH `expires_at` num offer já `expired` (relógio, status fica expired) — sem escalate a finding separado.
- L5: sem double-credit; refund pós-`concluido` bloqueado.
- L6: flags money/auto_feedback imutáveis; `completed_at` revertido; `is_automatic` forçado a false no INSERT JWT.
- L7: 1 crédito `venda` por order; commission implícita (5,90 pago → 5,00 na carteira).

--------------------------------------------------
FIXTURE / ÓRBITA
--------------------------------------------------

- `sec-fase2-e2e-oversell` `setup_paid_order` (Stripe TEST). Vendedor `enviado`, comprador `concluido`.
- Um `rpc auto_feedback` com `p_now`+2d (service, oráculo) devolveu **45** inserts — processou encomendas `concluido` já velhas no staging. Não é vector JWT.
- Hold de teste ainda `reserva_pendente`: `691f7e5f-630e-4a4d-a9c0-d602cc21da27` (cleanup manual se necessário).

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
