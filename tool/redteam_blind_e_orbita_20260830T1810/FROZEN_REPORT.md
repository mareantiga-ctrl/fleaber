# RED TEAM CEGO E — ÓRBITA
## AUDITOR: REDTEAM_BLIND_E_ORBITA_v1

```
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1
FROZEN_AT: 2026-08-30T17:25:00Z
production_touched: false
fase4: false
corrections_applied: false
project: fxdknzrqjenzqcvnwqqq (staging)
stripe: TEST (cs_test_ / pi_3UACMR…)
prefix: RTE-20260830T1810
```

**Não corrigi. Não toquei produção. Não re-auditei o freeze 1442.**

Probes: `tool/redteam_blind_e_orbita_20260830T1810/`  
Evidência bruta: `out/pass1.json`, `out/pass2.json`, `out/pass3.json`, `out/pay_dead.json`, `out/pay_dead_after.json`

--------------------------------------------------
MAPA DE ATAQUE (órbita) — 1 página
--------------------------------------------------

| Zona | Superfície LIVE | Actor | Resultado curto |
|------|-----------------|-------|-----------------|
| Hub views | `hub_*` + discovery | anon | Whitelist OK; **discovery enumera hub_published=false** (P3) |
| Handle | `batata_resolve_handle` | anon | 200 published / 404 missing; sem PII extra |
| FOMO | `batata_hub_live_fomo_snapshot` | anon | qty exacta (produto, não PII) |
| Base tables | profiles/products/lives | anon | 401; wallets/orders 200 `[]` |
| Crons | auto_feedback, expire_offers | JWT | **403/401** |
| Jobs | `batata_release_seller_wallet_for_order` | buyer | EXECUTE sim; **false** se ≠ concluido |
| Egress | livekit-egress-cleanup | buyer JWT | 401 |
| Notif | user_notifications | buyer | own-only; INSERT alheio 403 |
| Bundle | product_bundles PATCH status | buyer | **self-accept** (P2); Stripe **não** honra total 0,50 € |
| Discounts | seller_bundle_discounts | buyer | write cruzado 403; SELECT global (residual) |
| Connect | GET web_return_origin | anon | `*.fleaber.pt` 303; **sem wildcard DNS** |
| Connect | user_id swap | buyer | 400 |
| Webhook | account.updated sem sig | anon | missing_signature |
| Mortos | is_sold + unlist + qty>0 | buyer | **Session + captura TEST** (P1) |
| RLS produtos | GET unlisted | buyer2 | **lê SKU morto** (P2, vector) |
| Return | session_id fake | anon | 400 genérico |
| Social | follows / favorites | buyer | forge 403; unique favorites OK |
| Block | tabelas | — | **não existem** |
| Invite | find_user_id_by_email | buyer | null (não-seller) |

Lentes E1–E10 exercitadas. Anti-objectivo (dual Session, offer amount, carrier pago→concluido, disputa PATCH, OCR pairing) **não** foi o poço.

--------------------------------------------------
FINDINGS (estado final)
--------------------------------------------------

### E6-DEAD-CAPTURE — P1 — ABERTO
**Título:** Artigo `is_sold=true` + `list_on_marketplace=false` com `quantity>0` ainda reserva, emite Checkout Session e **captura** Stripe TEST.

**Actor:** buyer JWT (`bfcbeeee-…`)

**Pré:** produto fixture `35dd8125-872f-4440-8ed7-25da64f5d84d` criado já morto (`is_sold=true`, unlist, qty=2, preço 6,00 €). Hub público **não** o lista (pass1: unlist → `hub_products_public` 200 `[]`).

**Repro:**
1. JWT buyer `POST /orders` `reserva_pendente` qty=1 → 201.
2. `POST create-payment-intent` → `checkoutUrl` + `amount_total=695`.
3. Pagar Stripe TEST 4242 (sandbox) → PI `pi_3UACMRH7FWYUN3jh1h3Q1QhI`.

**Estado final (BD):**
- order `3b63916a-c241-4ecd-9283-9bb07d01a800` **status=pago**, `price_total=6.95`, `stripe_refund_id=null`
- product qty **2→1**, `list_on_marketplace` continua false, `is_sold` passou a **false** (unidade restante “viva” mas ainda unlisted)
- captura Stripe: SIM (Session + PI). Wallet seller observada 37,96 € (Δ não baselineado; crédito carteira pode esperar `concluido`)

**Impacto:** o vendedor tira o artigo da vitrine / marca vendido **sem zerar stock** → o comprador (e qualquer JWT que leia o UUID) ainda **compra de verdade**. Cadeia órbita (unlist/Hub vazio) → caixa (pago).

**Não é oversell:** qty=0 bloqueia (`order_hold_exceeds_stock`); 2.º buyer em qty=1 sold também bloqueia. O buraco é **is_sold/unlist ignorados** no hold + quote.

---

### E6-AUTH-READ-UNLISTED — P2 — ABERTO
**Título:** Qualquer autenticado lê produtos unlisted+sold (não é dono, nunca interagiu).

**Actor:** buyer2 JWT fresco `15457ed6-…` (pass2)

**Repro:** `GET /products?id=eq.<morto>` → 200 com title, price, qty, is_sold, list_on_marketplace=false.

**Impacto:** vector de descoberta para E6 (não precisa de UUID por outro canal). RLS documentada (`list_on_marketplace OR own`) **não** explica este SELECT — há policy extra LIVE (ex. shadow live) ou SELECT autenticado largo.

---

### E4-BUNDLE-SELF-ACCEPT — P2 — ABERTO
**Título:** Buyer faz PATCH `product_bundles.status=accepted` (e persiste `total_eur=0.50` / `discount_pct=50`) sem o vendedor.

**Actor:** buyer

**Repro:** INSERT bundle (guard força `pending`) → PATCH `accepted` → 200. Depois 2× `POST orders` `reservado` com `bundle_id`.

**Estado Stripe:** bag checkout `server_amount_cents=2333` (**23,33 €**, não 0,50 €). Edge recompute a partir de contratos/tiers — **não há desconto hostil na captura**.

**Impacto:** falso “aceite” do conjunto (UX/chat/seller pode expedir). Hold de stock = o mesmo que reserva marketplace normal. **Não** mint. **Não** IBAN novo (método «Compra em conjunto aceite» fora da allowlist off-platform).

---

### E1-DISCOVERY-UNPUB — P3 — ACEITE DE PRODUTO / residual
Anon `GET hub_profiles_discovery_public?hub_published=eq.false` devolve UUID, handle, full_name, location. **Desenho** da descoberta live sem vitrine. Sem email/IBAN/phone.

### E5-SUBDOMAIN-ALLOWLIST — P3 — residual
`GET create-connect-account?web_return_origin=https://evil.fleaber.pt` → **303** `https://evil.fleaber.pt/wallet`.  
DNS: `evil.fleaber.pt` e `this-sub-does-not-exist-rte.fleaber.pt` = **NXDOMAIN** (sem wildcard). `evil.com` / userinfo **não** redireccionam. Explorável só com subdomínio Fleaber controlado (takeover futuro). `http://localhost/wallet` 303 = web local.

--------------------------------------------------
FALSOS POSITIVOS / FECHADOS NESTE CEGO
--------------------------------------------------

| Claim inicial | Fecho |
|---------------|--------|
| Cron auto_feedback JWT | 401/403 |
| expire_product_offers JWT | 401/403 |
| release_wallet JWT = mint cedo | 200 `false` em reserva; só `concluido` + buyer (fluxo recepção, não cron mentiroso P0) |
| tick raffle buyer | `raffle_not_found` — não provado fechar rifa alheia |
| egress cleanup JWT | 401 |
| INSERT notif UID alheio | 403 |
| buyer write seller_bundle_discounts | 403 |
| Connect user_id swap | 400 |
| webhook Connect sem assinatura | missing_signature |
| session_id alheio unpaid | 400 genérico |
| follow as other UID | 403 |
| favorites DoS dup | unique (1/12) |
| qty=0 sold hold | 23514 |
| 2 buyers qty=1 sold | 2.º 23514 |
| total_eur=0.50 no Stripe | Edge 23,33 € |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------

1. Anon Hub: **SIM** (todas as views + resolve_handle + fomo)  
2. Cron/job hostil: **SIM** (auto_feedback/expire negados; release_wallet exercitado → false; egress 401)  
3. Pagar TEST: **SIM** (E6, 6,95 €, PI acima)  
4. Contabilidade: order pago + qty 2→1 + PI; Δwallet **não** atribuído (sem snapshot prévio; hold wallet até concluido é esperado)  
5. Race verbos: PATCH bundle ∥ POST orders; dual-buyer POST orders  
6. Dois buyers + anon Hub: **SIM**  
7. Soft-delete/unlist + checkout: **SIM** (P1)  
8. Burst: favorites 12× (único)

--------------------------------------------------
SCOREBOARD
--------------------------------------------------

```
P0 encontrados: 0
P1 encontrados: 1
P2 encontrados: 2
P3 encontrados: 2

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO  (qty=0 e 2.º hold qty=1 bloqueiam; P1 é venda de morto com qty>0)
Existe leak Hub/anon: NÃO  (PII financeira não; discovery unpublished = P3 produto)
Existe cron explorável: NÃO
Existe cross-user: SIM  (P2: JWT estranho lê produtos unlisted)
Existe cadeia órbita→caixa P0/P1: SIM  (unlist/Hub vazio → Session → pago)

Anon Hub exercitado: SIM
Cron/job exercitado: SIM
Último ciclo nova classe P0/P1: NÃO  (pass3 só refinou E6; qty0/dual-buyer fecharam oversell)
ATROFIA (só redescobriu classes fechadas): NÃO
SATURAÇÃO: NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P1
```

**ATROFIA_ABORT:** não (≥50% não são classes anti-objectivo; o P1 é E6 mortos/unlist).

--------------------------------------------------
FIXTURE A LIMPAR (staging)
--------------------------------------------------

- order **pago** evidência: `3b63916a-c241-4ecd-9283-9bb07d01a800` (não cancelar se quiserem reter prova)
- product: `35dd8125-872f-4440-8ed7-25da64f5d84d` (qty=1, unlist)
- users buyer2 criados `RTE-E` / `rte-e-b2-*@staging.fleaber.bot` (pass1/2/3 boots)
- outros orders fixture → `cancelado` no pass2/3
