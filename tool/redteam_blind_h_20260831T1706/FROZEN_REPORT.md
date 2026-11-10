# FROZEN_REPORT — RED TEAM CEGO H (IDENTIDADE / STAFF / MULTI-CONTA)

```
AUDITOR: REDTEAM_BLIND_H_IDENTIDADE_v1
VEREDICTO: PASS_CEGO_SATURADO
FROZEN_AT: 2026-08-31T16:25:00Z
staging: fxdknzrqjenzqcvnwqqq
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [H1, H2, H3, H4, H5, H6, H7]
prefixo_fixtures: RTH-20260831T1706-
```

**Não corrigido. Produção não tocada. Fase 4 não iniciada.**  
`service_role` só fixture / evidência / cleanup.

Provas: `tool/redteam_blind_h_20260831T1706/pass{1,2,3,4,5}.json`.

---

## Veredicto

Não foi possível actuar como outra pessoa (nem como staff com permissão a mais) e daí tirar dinheiro, stock, autoridade da loja alheia ou dados de encomenda/chat.

O poço H **aguenta**: helper chat-only não escala bits; token de pairing morre no kick; 2.ª conta não lê/escreve order/chat/review/disputa alheios; Edge recusa `buyer_id`/`seller_id` do body quando o JWT não bate; refund Stripe fica no `uid == seller_id` mesmo com `can_issue_refunds`.

Dois candidatos do pass1 foram **despromovidos** (falso positivo de fixture: contas lab nascem `user_type=vendedor`).

---

## Actores

| Papel | UID |
|-------|-----|
| buyer B1 | `bfcbeeee-7dc1-4cd1-b2a7-d3a0a6cf7c96` |
| seller S1 | `980f4fa1-0004-42f9-abca-69f1a9c29588` |
| buyer2 | `0664800a-1f59-4118-9827-35939c369e0e` |
| seller2 | `c472c97a-5daa-4774-be62-055710ca1e5c` |
| helper chat-only | `86ef631c-efc8-484b-8414-4028e95ecd2c` |
| helper reservas | `82d46f8f-b9fd-4bb3-8ee5-330bccc16c1e` |

---

## Contabilidade (Stripe TEST)

| Momento | Wallet B1 | Wallet S1 |
|---------|-----------|-----------|
| Início pass4 | 40.45 € | 0.00 € |
| Após pass4 | 40.45 € | 0.00 € |

PI TEST: `pi_3UAXxAH7FWYUN3jh0BChXfRc` 590¢ `succeeded` · order `0b580a2e-212f-4d2c-b4ef-97ae5c817f34` `pago`.  
Δ wallet desta ronda: **0** (captura sem libertação; nenhum refund JWT passou).

---

## Mapa de ataque (identidade)

| Zona | LIVE observado |
|------|----------------|
| H1 helper escalate | PATCH permissions no accept **stripped**. `batata_staff_has_permission` chat=true, refund/raffle/res=false. INSERT/PATCH products loja 403 / `[]`. Orders `[]`. Wallet `[]`. Perfil loja `[]`. Invite helper `not_allowed`. `live_raffles` GRANT denied. |
| H2 device após kick | Pairing helper → claim token → heartbeat OK. Kick → heartbeat `invalid_token`, OCR `invalid_token`. Token do **seller** continua OK. Pairing JWT após kick `not_allowed`. Token S1 na live S2: `live_not_owned` / OCR `not_allowed`. |
| H3 buyer2 hijack | PATCH/SELECT order B1 `[]`. Review `review_order_not_yours`. Disputa RLS 403. Chat forge B1–S1 403. `user_a` frozen. `chat_messages` INSERT 403, SELECT `[]`. Seller INSERT order `buyer_id=B2` → `order_buyer_attribution_denied`. |
| H4 JWT / switch | Kick: perm chat passa a `false`; reactivar-se `[]`. JWT `user_type` **congelado** (before=after). Logout parcial não re-provado (G7). |
| H5 staff loja alheia | `complete-mux-live` / LiveKit 403. INSERT `lives` `permission denied`. `live_items` RLS 403. Auto-convite S2 403. Helper `comprador` (svc) → Mux **403**. |
| H6 Edge body IDs | `create-payment-intent` JWT≠`buyer_id` → `Invalid checkout user.` Order alheia → `order does not belong to buyer.` `refund-order` B1/B2/helper/S2 → `Sem permissão.` Connect `user_id` spoof 400. e2e settle JWT não abre o caminho service_role. |
| H7 composição → caixa | Helper (+ bit refund) 403 no Edge. Hold forjado 403. Helper chat-only accept da própria reserva `not_allowed`. GET settle B2 sem sessão 400. |

---

## Findings P0 / P1

Nenhum com cadeia JWT/anon + efeito permanente (dinheiro, stock, autoridade da loja, dados de encomenda).

### Falsos positivos retirados

**RTH-H4-001 / RTH-H5-001 (pass1)** — «helper elevou `user_type`» e «helper comprador criou Mux».

- **O que aconteceu:** `create-mux-live` HTTP 200 com `vendedor_id` = helper; perfil observado `user_type=vendedor`.
- **Porque não é P0/P1:** o trigger `batata_profiles_guard_user_type` congela o tipo no UPDATE JWT. Pass2: buyer2 before=after=`vendedor` (default de registo lab, não elevação). Com `user_type=comprador` posto por **service_role**, o mesmo helper recebe Mux **403** «Apenas contas de vendedor». A live criada é a **loja do helper**, não a de S1 (`complete-mux-live` na live de S1 = 403).
- Lives Mux desta ronda (`9d0f249f-…`, `1d81f075-…`, `e03bd487-…`): `status=ended`, `is_active=false`.

---

## HOLD (identidade fechada nesta ronda)

| # | Ataque | Resultado |
|---|--------|-----------|
| H1 | Helper alarga permissions no accept | bits hostis stripped; chat-only persiste |
| H1 | Helper INSERT produto `seller_id=S1` | 403 RLS products |
| H1 | Helper PATCH preço SKU da loja | 200 `[]` (0 rows) |
| H1 | Helper SELECT orders / wallet S1 | `[]` |
| H1 | Helper PATCH nome da loja | 200 `[]` |
| H1 | Helper convida colaborador | 403 `not_allowed` |
| H1 | Helper INSERT `live_raffles` | 403 `permission denied for table live_raffles` |
| H2 | Token S1 heartbeat live S2 | `live_not_owned` |
| H2 | Token helper após kick | `invalid_token` (heartbeat + OCR) |
| H2 | Pairing JWT após kick | `not_allowed` |
| H2 | Helper kicked lê `seller_device_tokens` | `[]` |
| H3 | B2 PATCH/GET order B1 | `[]` |
| H3 | B2 review / disputa / chat B1–S1 | 403 |
| H3 | B2 `chat_messages` | INSERT 403 · SELECT `[]` |
| H3 | Seller forja hold `buyer_id=B2` | `order_buyer_attribution_denied` |
| H4 | Helper re-activa convite após kick | `[]`; perm `false` |
| H5 | Helper complete/LiveKit live S1 | 403 |
| H5 | Helper INSERT lives `seller_id=S1` | `permission denied for table lives` |
| H5 | Helper auto-insert em S2 | 403 RLS |
| H5 | Helper `comprador` cria Mux | 403 authz |
| H6 | Checkout JWT B2 + `buyer_id` B1 | `Invalid checkout user.` |
| H6 | Checkout order B1 JWT B2 | `order does not belong to buyer.` |
| H6 | refund-order não-seller | 403 `Sem permissão.` |
| H7 | Helper com `can_issue_refunds` refund Stripe | 403 (Edge `uid==seller`) |
| H7 | Helper chat-only accept reserva própria | `not_allowed` |

**Não re-provado (anti-objectivo):** dual Session, bag unlist, tip seller mismatch, invite enum, cancel hold, review release, Hub paused, pairing ended, offer morto.

---

## Lentes — cobertura

| Lente | Exercitada | Captura / estado |
|-------|------------|------------------|
| H1 | SIM | 2 helpers (chat-only + reservas); escalate + REST loja + rifa |
| H2 | SIM | pairing activo (não ended) → kick → token morto; cruzamento S1→S2 |
| H3 | SIM | order/chat/review/dispute + forge seller |
| H4 | SIM | kick + user_type before/after; Mux pós-kick = loja própria |
| H5 | SIM | Mux/LiveKit/lives/rifa/refund loja alheia |
| H6 | SIM | PI / refund / connect / complete / e2e JWT |
| H7 | SIM | `setup_paid_order` 590¢ + refund staff/B2/S2 + hold forjado + conluio reserva |

---

## Notas (não finding)

- Contas criadas via Auth admin neste staging ficam `user_type=vendedor` até um PATCH **service_role**; JWT não muda o tipo. Quem for comprador de verdade não passa no Mux.
- `refund-order` **não honra** `can_issue_refunds` (só `uid==seller`). Fail-closed para o atacante; staff com o bit também não reembolsa pela Edge.
- `lives` / `live_raffles`: GRANT negado a `authenticated` (nem RLS chega).
- Cleanup: helpers revoked; SKUs RTH apagados; lives RTH `ended`.

---

## Saturação H / atrofia

Último ciclo (pass5) não acrescentou classe nova. O poço identidade/staff/multi-conta está **saturado** neste freeze: 7 lentes, 0 P0/P1 reproduzido.

**ATROFIA_ABORT:** não. Zero findings nas classes fechadas (dual Session / bag unlist / tip mismatch / invite enum / cancel hold / review release / Hub paused / pairing ended / offer morto).

Não declarar PASS global da app (outros poços G/D ainda abertos noutros freezes).
