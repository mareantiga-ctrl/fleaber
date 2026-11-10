# FROZEN_REPORT — REDTEAM_BLIND_CD_MARKETPLACE_POS_BXCC_v1

## CONTAGEM
P0 aberto: NÃO → quantos: 0
P1 aberto: NÃO → quantos: 0
P2 aberto: SIM → quantos: 1
P3 aberto: NÃO → quantos: 0
TOTAL P0–P3 abertos: 1
1. P0? NÃO  2. Quantos P0: 0
3. P1? NÃO  4. Quantos P1: 0
5. P2? SIM  6. Quantos P2: 1
7. P3? NÃO  8. Quantos P3: 0

```
AUDITOR: REDTEAM_BLIND_CD_MARKETPLACE_POS_BXCC_v1
FROZEN_AT: 2026-09-06T12:42:00+01:00
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [CD1, CD2, CD3, CD4, CD5, CD6, CD7, CD8]
pocos_tentados: [CD-A, CD-B, CD-C, CD-D, CD-E]
VEREDICTO: FAIL_P2
```

Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST (`setup_paid_order` PI `succeeded` 590¢ + `setup_paid_bag` 1115¢) · sem produção · sem Fase 4 · **sem patches**.  
Prefixo: `RTCD-20260906T1225-` · pasta: `tool/redteam_blind_cd_20260906T1225/`.  
Atacantes: `anon` · buyer JWT · seller JWT · 2.º buyer · seller2. `service_role` só fixture/observação.

---

## P2-1 — slot `claiming:` órfão bloqueia checkout (DoS)

**O que isto é:** o checkout do marketplace tranca a encomenda com um marcador `claiming:…` enquanto cria a sessão Stripe. Se esse marcador ficar para trás, o comprador deixa de conseguir pagar aquela encomenda.

**Quem / onde:** comprador (JWT) no checkout; o marcador órfão foi simulado como crash a meio do claim (observação), não como actor `service_role`.

**O que fizemos:** gravámos `stripe_checkout_session_id=claiming:deadbeefcafebabe` (e depois `claiming:orphanedtoken12`) na order; o comprador fez POST `create-payment-intent`; esperámos 5 s e repetimos.

**Esperado vs resultado**
- Ecrã/API comprador: esperado reclaim ou expirar o slot → visto `400 Checkout blocked: order claim contention.` nas duas tentativas
- Base de dados: esperado `cs_…` ou null → visto o `claiming:` intacto
- Stripe: nenhuma Session nova
- Outros sítios: não aplicável

**Conclusão:** **P2** — a encomenda fica impagável sem TTL/reclaim. Não desvia dinheiro nem stock. Timeout de cliente (250 ms) **não** criou 2 Sessions (1 `cs_` gravada nas duas linhas).  
**Prova:** `pass1_findings.json` FINDING P2-1; `pass2_findings.json` BLOCKED P2-1-CONFIRM.

---

## Anti-atrofia

Exactos já fechados (não contar; todos bloqueados nesta corrida):
- bag∥single mesma order → **1** `cs_` (A1)
- 5-line ×3 paralelo → **1** `cs_` (A2)
- underpay `amount`/currency ZWJ/bidi/fullwidth/NBSP → servidor ignora / rejeita non-EUR; Session ~1325¢ para SKU 12€ (B1)
- UI≠Stripe: quote servidor 1640¢ estável após PATCH hostil (A5; buyer PATCH qty 403)

Variante nova com prova LIVE: **P2-1** (crash/claim sem TTL). Não é o dual-Session bag∥single. Anti-atrofia OK.

---

## Poços (estado final)

### CD-A — lock / Sessions
| # | Ataque | Resultado |
|---|--------|-----------|
| A.1 | bag∥single residual | BLOCKED ≤1 `cs_` |
| A.2 | 5 linhas ×3 paralelo | BLOCKED 1 `cs_` |
| A.3 | timeout 250 ms ∥ retry | BLOCKED 1 `cs_` nas 2 orders |
| A.3b | `claiming:` órfão | **P2-1** contention permanente |
| A.4 | bag 5-line ∥ 3-line (2 SKUs partilhados, ≠ triângulo AB∥AC) | Edge devolveu 2 `cs_` distintas (`4108` vs `3341` ¢); ledger ficou com **1** `cs_` em A–E; linha F sem sid; GET settle nas duas → `402` unpaid (objectos Stripe existem). HTML Stripe é SPA — não distingue open/expired. Browser «This link is incomplete» no hash. **Dual pagável não comprovado** — não conta P0/P1 |
| A.5 | PATCH qty/price com Session open | BLOCKED amount_total 1640→1640; buyer PATCH qty 403 |
| A.6 | list Stripe `sk_test_` local | SKIP (secret não no env local). Settle GET prova que as `cs_` ainda existem unpaid |

### CD-B — preço / currency / encoding
- Currency ZWJ / bidi / fullwidth → `only EUR is supported`
- Amount NBSP / fullwidth / ZWJ / bidi → Session não baixa do contrato
- Bundle `total_eur=1` → insert falhou `bundle_products_required`; bag 3 SKUs Session 2837¢ (não 100¢)
- Offer `８.００` → `invalid input syntax for type numeric`; offer 8€ aceite → Session 905¢ (8€ + protecção, não underpay)
- `batata_ensure_checkout_product` buyer → `live_item_not_found`; anon → `42501`

### CD-C — stock / oversell / unlist
- 2.º hold em qty=1 → `order_hold_exceeds_stock` (insert)
- Race 2 buyers após 2 holds + PATCH qty=1 → **ambos** `quantity 1 exceeds available stock 0` (CD6)
- checkout ∥ unlist → checkout 400 `not listed` (unlist ganhou)
- `is_sold=true` → 400 `marked sold`
- live ended + mesmo SKU marketplace → checkout OK (live_item insert falhou NOT NULL; sem oversell live activo)
- `bag_update_qty` 9999 → `request_not_found`; anon `42501`
- bag 2 sellers → 400 `must share one seller`

### CD-D — FSM / MB WAY / pós-pago
- Seller `pago` MB WAY sem prova → `order_mbway_pago_requires_proof`
- Buyer `concluido` cedo → `order_concluido_denied`
- Cancel JWT pós-pago → `order_cancel_denied_post_pay`
- `refund-order` JWT buyer → `403 Sem permissão`
- 2× refund seller → 2.º idempotente; stock 2→3 (não duplicou)
- GET settle Session unpaid → `402`; order continua `reserva_pendente`

### CD-E — composição até caixa
- `setup_paid_order`: status=`pago`, PI `pi_3UCeKVH7FWYUN3jh0jIjF7Ze` succeeded, `amount_paid_cents=590`, `stock_units_applied=1`, product qty 2→1
- Δwallet buyer/seller: **0** (hold em escrow, não release) — ausência de Δwallet sem release é coerente
- `setup_paid_bag`: PI 1115¢, quote items 1000 + protecção 115
- Wallets pré/pós probes: buyer 61.10 / seller 70.33 inalteradas nas corridas unpaid
- Controlo single-item legítimo: 200 + `cs_` + 1325¢

---

## Lentes (≥6/8)

| Lente | Evidência |
|-------|-----------|
| CD1 | encoding amount/currency; contract seal 1640¢; single legítimo 1325¢ |
| CD2 | claim 5-line; bag∥single; `claiming:` P2-1; overlap 5∥3 |
| CD3 | offer unicode rejeitada; freeze 8€→905¢; bundle insert fail-closed |
| CD4 | MB WAY sem prova; concluido cedo; cancel pós-pago |
| CD5 | last-unit; unlist; sold; cross-seller bag |
| CD6 | Future.wait 5-line×3; overlap 5∥3; 2 buyers last-unit; unlist∥checkout |
| CD7 | buyer2 last-unit; anon ensure/qty; buyer refund 403 |
| CD8 | setup_paid_order 590¢ pago+stock; wallets; settle 402 |

---

## Tácticas mínimas

1. Checkout Stripe TEST pago (4242 / `pm_card_visa`) marketplace: **sim** (`setup_paid_order` + `setup_paid_bag`)
2. ≥2 races distintas: **sim** (5-line×3; overlap 5∥3; last-unit 2 buyers; unlist∥checkout; timeout∥retry)
3. Encoding/currency no amount: **sim** (ZWJ, bidi, fullwidth, NBSP)
4. Contabilidade por order pago: stock · PI · status=`pago` · wallets (sem Δ até release)
5. Compra single-item / envio vendedor: **não partida** (CTRL-SINGLE 200)

---

## Checklist invariantes (exercício cego, sem ler FROZEN BX–CC)

- Preço: body hostil ignorado; só EUR; contrato selado
- Claim: 1 Session por saco 5-line e bag∥single; **falha** TTL de `claiming:`
- Stock: holds e `batata_product_checkout_available` impedem 2ª Session na última unidade
- FSM pago/cancel/concluido/refund: fail-closed nos JWT
- Caixa: captura TEST alinha PI, `amount_paid_cents`, stock; wallets sem release
- Checklist 28 (marketplace/checkout): poços A–E tentados; dual pagável overlap **não** fechado com captura 4242 nas 2 URLs (sem `sk_test_` local + hash Stripe incompleto no browser)

---

## Não feito / limites

- Sem `STRIPE_SECRET_KEY` `sk_test_` no env local → sem retrieve/expire/list/confirm `pm_card_visa` nas Checkout Sessions
- Dual Session overlap 5∥3: 2 objectos Stripe (settle 402) + 1 sid no ledger; captura dupla **não** comprovada
- live_item mesmo SKU activo: fixture live ended sem colunas obrigatórias; não oversell live+marketplace em directo
- **NÃO CORRIGIR** (missão)

---

## Artefactos

- `tool/redteam_blind_cd_20260906T1225/_rtcd.dart`
- `tool/redteam_blind_cd_20260906T1225/pass1.dart` + `pass1_findings.json`
- `tool/redteam_blind_cd_20260906T1225/pass2.dart` + `pass2_findings.json`
- `tool/redteam_blind_cd_20260906T1225/pass3_overlap_urls.json`
- `tool/redteam_blind_cd_20260906T1225/pass3b_orphan_settle.json`
