# RED TEAM CEGO E — ÓRBITA
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1  
FROZEN_AT: 2026-08-30T22:09+01:00  
Projecto: staging `fxdknzrqjenzqcvnwqqq`  
Stripe: TEST · prefixo fixtures `RTE-20260830T1930-`  
production_touched: false  
fase4: false  
corrections_applied: false  

Probes: `tool/redteam_blind_e_orbita_20260830T1930/` (`pass1`…`pass7`, `out/*.json`)

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1
FROZEN_AT: 2026-08-30T22:09+01:00
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
MAPA DE ATAQUE (órbita) — 1 página
--------------------------------------------------

| Zona | LIVE (anon / JWT) | Efeito económico? |
|------|-------------------|-------------------|
| Hub views `hub_*` | anon SELECT OK; discovery unpublished = `[]`; `batata_resolve_handle` 404 em ghost | não |
| FOMO `batata_hub_live_fomo_snapshot` | anon: `available_qty` exacto | intel stock (P3) |
| Tabela `lives` | anon `select=id,status,title,mux_playback_id` 200; `mux_stream_key` 401 | playback público, não key |
| Crons | `batata_generate_auto_feedback` / `expire_product_offers` 401/403 JWT+anon; `livekit-egress-cleanup` 401 | wallet RPC executa mas `false` se ≠ `concluido` |
| Notificações | INSERT/SELECT alheio bloqueado; `notifications_view` anon 401; tokens `[]` | não |
| Bundle | buyer INSERT `total_eur=0.50` pending; seller-only accept; Edge cobra **preço produto** (2165¢) não 0.50 | Session listed, não desconto hostil |
| Connect | `user_id` cruzado recusado; IBAN oracle vazio p/ buyer2 | GET `web_return_origin=https://attacker.fleaber.pt/` → 303 `/wallet` (allowlist `*.fleaber.pt`) |
| Soft-delete / unlist | **P1:** `list_on_marketplace=false` + `live_id` de directo **ended** do mesmo seller → hold 201 + Session TEST 958¢ | hold qty=1; captura **não** feita |
| Unlist após hold (sem live_id) | Edge `Checkout blocked: product is not listed.` | fechado neste caminho |
| `is_sold=true` | hold `order_hold_product_sold` | fechado |
| Return URL pagamento | Session com origin `attacker.fleaber.pt` (mesma allowlist) | Session≠capture |
| Social | anon follow/reserve 401; dual-hold qty=1 → 2º `order_hold_exceeds_stock` | não oversell |
| SMS | 200 `Hook failed: Missing required headers` | não envio |

Actores: seller `980f4fa1-…` · buyer `bfcbeeee-…` · buyer2 `74ade8e0-…` (criado admin, só setup).

--------------------------------------------------
FINDING P1 — E6 mortos que vendem (live_id stamp)
--------------------------------------------------

**ID:** E1930-E6-UNLIST-LIVE-STAMP  
**Lente:** E6 → E10 (órbita→caixa até Session)  
**Severidade:** P1  

**O que é:** um artigo **já retirado da loja** (`list_on_marketplace=false`) ainda pode ser reservado e aberto em Checkout Stripe TEST se o comprador carimbar na encomenda o `live_id` de um directo **antigo (ended)** do mesmo vendedor.

**Pré:** produto `3c58b97d-a083-47c3-9a0f-df8397b58d61` qty=1, `is_sold=false`, `list_on_marketplace=false`. Live ended `a95a3bcb-2f92-4c2b-a4f3-6e3a945c275c` (mesmo seller).

**Repro (JWT buyer):**
1. `POST orders` sem `live_id` → **400** `order_hold_product_not_listed`
2. `POST orders` `status=aguarda_pagamento` + `live_id=<ended>` → **201** order `c5d6b577-19b9-491e-b286-ea12cebf3c15`
3. `batata_product_held_qty` → **1**
4. `POST create-payment-intent` `{order_id, buyer_id, shipping_method:hand}` → **200**  
   `cs_test_a1nYpPdgtR7ck4vleohKA2u0tkouG8D69FwRdQ4tBTZBkQUSje5Qm2gt53`  
   `server_amount_cents=958` (8,50 € + protecção)
5. GET settle sem pagar → texto «Pagamento ainda não confirmado»; `amount_paid_cents=null`; `is_sold=false`

**Porquê P1, não P0:** Session TEST existe e o stock está **held**. Captura Stripe / Δwallet / `is_sold=true` **não** foram obtidos (SESSION ≠ capture). Um cartão TEST fecha a venda dum artigo que a loja já escondeu.

**Contraste (controlo):** hold listed → PATCH unlist → checkout **sem** live_id → `Checkout blocked: product is not listed.`  
`is_sold=true` → `order_hold_product_sold`.

Causa provável: trigger de hold trata `live_id` como «contexto live» mesmo em directo **ended** e sem `live_item_id`; Edge `hasLive` salta o gate `list_on_marketplace`.

--------------------------------------------------
OUTROS (não P0/P1 sozinhos)
--------------------------------------------------

**P2 E4** — buyer INSERT bundle `total_eur=0.50` `status` forçado a `pending`; `PATCH accepted` buyer → `bundle_accept_seller_only`. Seller accept grava `total_eur=0.50`, mas Edge cobra **2165¢** (preço 20 € + taxas), não 0,50. Desconto hostil **não** chega ao Stripe. Checkout de conjunto **pending** ao preço de lista = P2 de fluxo, não mint.

**P3 E7** — GET `create-connect-account?web_return_origin=https://attacker.fleaber.pt/` → **303** `Location: https://attacker.fleaber.pt/wallet`. `endsWith(".fleaber.pt")`. Sem prova de DNS/takeover; evil.com / `fleaber.pt.evil.com` / userinfo rejeitados.

**P3 E1** — FOMO `available_qty`; Hub mostra `is_sold=true` na vitrine (não checkoutável); anon lê `lives` públicas (playback, não stream key).

**INFO** — crons JWT negados; notif/tokens/IBAN/Connect uid cruzado/follow anon fechados; dual hold qty=1 bloqueado no 2º buyer.

Anti-objectivo (dual Session, offer amount, pago→concluido, disputa PATCH, OCR pairing): **não** usados como finding.

--------------------------------------------------
TÁCTICAS
--------------------------------------------------
1. Anon Hub: SIM (`hub_*`, resolve_handle, FOMO)  
2. Cron/job: SIM (RPC JWT + edge egress) — efeito económico indevido **não** reproduzido  
3. Pagar TEST: Session aberta; captura **não** (browser abortado; settle unpaid não liquida)  
4. Contabilidade: hold=1, paid=null, sold=false  
5. Race hold buyer∥buyer2 qty=1: 201 + 400  
6. Dois buyers + anon na superfície Hub: SIM  
7. Soft-delete/unlist + checkout: SIM (P1 stamp)  
8. Burst favorites: 1/8 (unique), sem DoS  

Último ciclo (E1 lives cols, E4 accept+amount, E7 origin, E8 anon, E2 cron): **sem nova classe P0/P1**.

--------------------------------------------------
RESPOSTA FINAL
--------------------------------------------------
```
P0 encontrados: 0
P1 encontrados: 1
P2 encontrados: 1
P3 encontrados: 3

Existe criação líquida de dinheiro: NÃO COMPROVADO
Existe oversell válido: NÃO
Existe leak Hub/anon: NÃO
Existe cron explorável: NÃO
Existe cross-user: NÃO
Existe cadeia órbita→caixa P0/P1: SIM (unlist+live_id → Session TEST 958¢; captura não)

Anon Hub exercitado: SIM
Cron/job exercitado: SIM
Último ciclo nova classe P0/P1: NÃO
ATROFIA (só redescobriu classes fechadas): NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P1
```
