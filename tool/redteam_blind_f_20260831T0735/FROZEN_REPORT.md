# RED TEAM CEGO F — POLÍTICAS FINAS / RLS ∩ FSM
AUDITOR: REDTEAM_BLIND_F_POLITICAS_FINAS_v1  
FROZEN_AT: 2026-08-31T07:51+01:00  
Projecto: staging `fxdknzrqjenzqcvnwqqq`  
Stripe: TEST · prefixo fixtures `RTF-20260831T0735-`  
production_touched: false  
fase4: false  
corrections_applied: false  

Probes: `tool/redteam_blind_f_20260831T0735/` (`pass1`…`pass4`, `cleanup`, `out/*.json`)

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_F_POLITICAS_FINAS_v1
FROZEN_AT: 2026-08-31T07:51+01:00
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
MAPA DE ATAQUE (políticas finas) — 1 página
--------------------------------------------------

| Zona | LIVE (anon / JWT) | Cruzamento | Compra / leak? |
|------|-------------------|------------|----------------|
| `products` RLS | anon 401; buyer2 listed OK, unlisted/sold `[]`; seller vê own unlist | F1 OR `exists(orders)` | Ghost `cancelado` → SELECT unlist (mesmo buyer). PATCH hold → `order_hold_product_not_listed` |
| Hub `hub_products_public` | sold `[]`; listed visível | F2 | alinhado com RLS JWT |
| `profiles` | buyer2 `[]` na linha do seller | F1 | own-row HOLD |
| `profiles_directory_public` | JWT lista N perfis (incl. handles null / labs) | F2 vs Hub `hub_published` | nomes, não IBAN |
| `lives` / `live_items` | JWT 403 na tabela `lives`; anon 401 `live_items` | F2 | item em live **draft** visível no Hub? não. Base buyer2 `[]` (EXISTS herda RLS de `lives`) |
| `reviews_gerais` vs `hub_reviews_public` | JWT vê `buyer_id` alheio; Hub só `author_display` | F2 | UUID, não PII bancária |
| `live_messages` vs Hub | JWT vê `user_id`; Hub omite | F2 | UUID |
| Hold trigger | status que não segura stock **não raise** | F3 | INSERT `cancelado` unlisted 201; promote hold 400 |
| Bundle write | INSERT hostil → `pending` + total catálogo; PATCH accept buyer 403 | F3/E4 | 1 repro: fechado |
| Edge vs BD | unlist+ended `live_id` hold 400; ghost Edge 400; INSERT `pago`+PI fake → `reserva_pendente` | F4 / E6 1× | E6 HOLD; money fields immutable |
| Offer TTL | seller PATCH `accepted` com `expires_at` passado | F5 | selo contrato **1250¢** (lista); `product_offer_id` null; Session TEST lista+proteção 13,77 €. SESSION ≠ captura |
| Pairing PS | seller cria código em live **ended**; claim JWT/anon **PGRST203** (overload 2 assinaturas) | F5 | claim **NÃO COMPROVADO**; tabela `ps_pairing_sessions` buyer/anon `[]`; seller vê own token |
| Bag 2 sellers | Edge 400 `must share one seller` (com e sem `seller_id` nas lines) | F6 | HOLD |
| Helper chat-only | accept **não** escala permissions; rifa 403; pairing `not_allowed`; payouts `false` | F7 | HOLD |
| Admin / cron JWT | `batata_admin_list_profiles` «Acesso negado»; `expire_product_offers` 403 | F7/F4 | HOLD |
| Wallets / chats / device tokens | buyer2 `[]` / 403 refund fake | F2/F4 | HOLD |

Actores: seller `980f4fa1-…` · buyer `bfcbeeee-…` · buyer2 `9eb5143a-…` · seller2 `263c825c-…` (signup admin, só setup).

--------------------------------------------------
FINDINGS P0 / P1
--------------------------------------------------

Nenhum.  

Candidato Pass 1 **RTF0735-F5-OFFER-CHECKOUT-5** (Session após offer expirada) — **despromovido**.  
Estado final (svc): order `f9741e1e-…` `contract_unit_cents=1250`, `product_offer_id=null`, `price_total=13.77`, `amount_paid_cents=null`, Session `cs_test_a1da7TQ4REXUInpYmyOzays9UopKxs6lkMIL7heI6RvnlnGR31xuEbOVQv`.  
O trigger de selo **anula** a offer expirada e cobra o catálogo. SESSION ≠ captura. Não há Δwallet.

--------------------------------------------------
P2 (hardening, sem P0/P1 demonstrado)
--------------------------------------------------

**RTF0735-F5-OFFER-TTL-4** — F5  
Seller JWT aceita `product_offers` com `expires_at` no passado (`18d08a85-…` amount 8,00 `accepted`). A UI/FSM da proposta mente; o caixa **não** honra os 8 €.

**RTF0735-F1-OR-VIA-ORDER-3** + **RTF0735-F3-GHOST-ORDER-2** — F1 ∩ F3  
INSERT `orders.status=cancelado` em produto `list_on_marketplace=false` → 201 (gate de hold saltado). A policy `products` `OR exists(orders)` passa a revelar título/preço/qty do unlist **ao mesmo buyer**. Promote para `aguarda_pagamento` → `order_hold_product_not_listed`. Edge no ghost → `order status 'cancelado' cannot start payment.`

**RTF0735-F2-REVIEWS-BUYER-ID-1** — F2  
JWT buyer2 SELECT `reviews_gerais.buyer_id` de outros (ex. `4b343994-…`). Hub `hub_reviews_public` só `author_display`.

**RTF0735-F2-DIRECTORY-ALL-101** — F2  
`profiles_directory_public?limit=8` devolve labs/unpublished (`hub_profiles_public` filtra `hub_published`). Colunas: nome/handle/location/user_type — sem phone/IBAN.

**RTF0735-F2-LIVE-MSG-USER-102** — F2  
JWT lê `live_messages.user_id` alheio; Hub omite.

--------------------------------------------------
LACUNAS HONESTAS
--------------------------------------------------

- `batata_ps_claim_pairing`: PostgREST **PGRST203** (duas assinaturas). Claim JWT/anon/svc **não exercitável** neste freeze. Create em live ended **sim** (código 6 dígitos, TTL 120s). Não se prova «token válido após expire».
- Captura Stripe TEST **não** feita: nenhum poço exigia net após o despromove do P1.
- OpenAPI anon 401; inventário RPC via service no pass 2.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Pass 1 **não** gasto em dual Session, offer amount mutável, carrier concluido, disputa seller close, OCR kick, tip sem live, email enum, admin resolve.  
E6 unlist+ended live_id: **1 repro** → `order_hold_product_not_listed`.  
E4 bundle self-accept: **1 repro** → INSERT reescrito `pending`/catálogo; PATCH `bundle_accept_seller_only`.  
≥50% findings ≠ essas classes. **ATROFIA=NÃO.**

--------------------------------------------------
RESPOSTA FINAL
--------------------------------------------------
```
P0 encontrados: 0
P1 encontrados: 0
P2 encontrados: 6

Existe criação líquida de dinheiro: NÃO
Existe oversell válido: NÃO
Existe leak Hub/anon PII: NÃO
Existe view vs base (UUID / directory): SIM (P2)
Existe policy OR que revela unlist: SIM (P2, mesmo UID, sem compra)
Existe trigger silent falso-OK de compra: NÃO (ghost não promove / Edge bloqueia)
Existe Edge vs BD P0/P1: NÃO
Existe TTL offer→preço stale: NÃO (accept sim / caixa não)
Existe multi-seller bag Session: NÃO
Existe helper perm escalate: NÃO
Existe cadeia F*→caixa P0/P1: NÃO

Lentes F1–F8: SIM
Anon Hub exercitado: SIM
Último ciclo nova classe P0/P1: NÃO
ATROFIA (só redescobriu classes fechadas): NÃO
SATURAÇÃO: SIM
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: PASS_CEGO_SATURADO
```
