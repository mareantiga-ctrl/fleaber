# RED TEAM CEGO F — POLÍTICAS FINAS / RLS ∩ FSM
AUDITOR: REDTEAM_BLIND_F_POLITICAS_FINAS_v1  
FROZEN_AT: 2026-08-31T13:05+01:00  
Projecto: staging `fxdknzrqjenzqcvnwqqq`  
Stripe: TEST · prefixo fixtures `RTF-20260831T1250-`  
production_touched: false  
fase4: false  
corrections_applied: false  

Probes: `tool/redteam_blind_f_20260831T1250/` (`pass1`…`pass4`, `cleanup`, `out/*.json`)

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_F_POLITICAS_FINAS_v1
FROZEN_AT: 2026-08-31T13:05+01:00
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
MAPA DE ATAQUE (políticas finas) — 1 página
--------------------------------------------------

| Zona | LIVE (anon / JWT) | Cruzamento | Compra / leak? |
|------|-------------------|------------|----------------|
| `hub_live_items_public` ∩ `hub_lives_public` | anon vê items `paused` + `is_active=false` de live **ended** com loja publicada | F2 | título/preço (199,50 € «paused-secret», 55 € live-only). FOMO devolve `available_qty`. Sem checkout |
| `hub_live_items_discovery_public` | igual ao Hub items | F2 | alinhado (não mais apertado) |
| `hub_lives_discovery` ended unpublished | seller2 `hub_published=false` → `[]` | F2 | HOLD |
| live **draft** no Hub | FOMO `live_not_public`; items Hub `[]` | F2 | HOLD no Hub; OCR noutro poço |
| `products` RLS | buyer2 unlist/sold `[]`; listed OK; seller own OK | F1 | ghost `cancelado` → `order_wallet_release_flag_immutable` (não 201) |
| Shadow `live_checkout_shadow` | reserva `pending` em item paused de live **ended** → GET unlist (88,80 €) | F1 ∩ F3 | **lê** unlist; hold `order_hold_product_not_listed` |
| Hold unlist + `live_id` ended/draft | 400 `order_hold_product_not_listed` | F4/E6 1× | HOLD caixa |
| INSERT `pago`+PI fake | reescrito `reserva_pendente`; PI/`amount_paid` stripped | F3 | HOLD |
| PATCH `wallet_release_processed_at` | 403 `order_wallet_release_flag_immutable` | F3 | HOLD |
| Bundle self-accept | schema `catalog_subtotal` ausente; retry sem coluna → não `accepted` | E4 1× | HOLD |
| `catalog_subtotal` unlist/sold | JWT `0.00` | F8 | HOLD oracle preço |
| Pairing seller em live **ended** | RPC cria código; Edge claim **token**; OCR `live_ended`; heartbeat `ok` | F5 ∩ F4 | token vivo; ingest bloqueado |
| Pairing seller em live **draft** | código + claim token; OCR **created** pending `facebook_manual`; seller accept `reserved_partial`; convert `ok` **sem** order | F5 ∩ F8 | aceitar sim; comprar não; qty produto inalterada |
| Claim após `expires_at` passado | `invalid_or_expired_code` | F5 | HOLD |
| Bag 2 sellers | Edge 400 `must share one seller` | F6 | HOLD |
| Helper chat-only | escalate permissions **não**; pairing ended `not_allowed`; raffle `not_allowed` | F7 | HOLD |
| RPC release wallet JWT | `false` (unpaid + cross-user) | F4/F7 | HOLD |
| Admin / expire offers JWT | «Acesso negado» / 403 function | F7 | HOLD |
| `create-mux-live` comprador | 403 «Apenas contas de vendedor» (buyer2 `user_type=comprador`) | F4 | HOLD (pass1 200 foi fixture sem `user_type`) |
| `complete-mux-live` cross | 403 | F4 | HOLD |
| Wallets / storage / orders alheios | buyer2 `[]` | F2 | HOLD |
| `lives` JWT buyer2 | 403 tabela | F2 | HOLD stream key |
| `live_items` JWT buyer2 | lê item paused de live ended pública + `product_id` unlist; draft item `[]`; anon 401 | F2 | UUID produto + preço (Hub já mostra título/preço) |
| `reviews_gerais` | JWT vê `buyer_id` alheio | F2 | UUID residual |
| Tip ended / refund fake | metadata / encomenda não encontrada | F4 1× | HOLD |

Actores: seller `980f4fa1-…` · buyer `bfcbeeee-…` · buyer2 `f516eea6-…` · seller2 `d0cd43ce-…` (signup lab).

--------------------------------------------------
FINDINGS P0 / P1
--------------------------------------------------

Nenhum.

Candidato **RTF1250-F8-OCR-DRAFT** (pairing → Edge claim → OCR `created` → seller `accept` em live `draft`): **despromovido de P1**.  
Estado final (svc): reserva `d5198f20-…` aceite depois rejeitada no cleanup; `orders?live_item_id=draft` → `[]`; produto unlist qty **2** inalterado; wallets seller 234,60 / buyer 22,75 (sem Δ desta ronda); hold JWT `order_hold_product_not_listed`; **sem** Session Stripe.  
SESSION ≠ captura. Aceitar reserva OCR ≠ compra.

--------------------------------------------------
P2 (hardening, sem P0/P1 demonstrado)
--------------------------------------------------

**RTF1250-F2-HUB-PAUSED-ITEM** — F2  
`hub_live_items_public` e `hub_live_items_discovery_public` (anon) devolvem live_items `status=paused` / `is_active=false` desde que a live esteja em `hub_lives_public` (ended + seller `hub_published`). FOMO `batata_hub_live_fomo_snapshot` inclui `available_qty` desses items.  
Prova: item `38c59bba-…` título `paused-secret` preço 199,5; item live-only `090868bc-…` preço 55. Draft live **não** entra no Hub (`live_not_public`).

**RTF1250-F1-SHADOW-PAUSED** — F1 ∩ F3  
Buyer JWT INSERT `live_reservation_requests` pending em item paused de live **ended** (201). A policy `products_select_live_checkout_shadow` (OR reserva pending/accepted/converted, **sem** exigir live activa) revela o produto unlist (`f3f94bbf-…` 88,80 €). Promote hold → `order_hold_product_not_listed`.

**RTF1250-F5-PAIR-ENDED-CLAIM** — F5 ∩ F4  
Seller cria pairing em live ended (código 6 dígitos, TTL 120s). Edge `ps-pairing-claim` **anon** emite `device_token`. OCR `live_ended`. Heartbeat com o mesmo token → `ok:true` (token não revogado ao terminar a live). Claim com `expires_at` no passado → `invalid_or_expired_code`.

**RTF1250-F8-OCR-DRAFT** — F5 ∩ F8 ∩ F3  
Seller pairing em live **draft** + claim + OCR `action=created` (`ingest_status=needs_review`, `source=facebook_manual`, `buyer_id=null`). Seller RPC `accept` → `item_status=reserved_partial`, `reserved_qty=1`. Convert `ok:true` **sem** row em `orders`. Trigger/Edge de caixa não honram o rascunho. Heartbeat/claim = superfície PS à volta de um directo que a UI/Hub não mostram.

**RTF1250-F2-LIVE-ITEMS-JWT** — F2  
JWT buyer2 SELECT `live_items` do item paused de live ended pública (título, preço, `product_id` unlist). Anon 401 na tabela base. Draft item de live não pública → `[]`.

**RTF1250-F2-REVIEWS-BUYER-ID** — F2  
JWT lê `reviews_gerais.buyer_id` de outros (ex. `4b343994-…`). Hub `hub_reviews_public` só `author_display`. Sem IBAN/telefone.

--------------------------------------------------
LACUNAS HONESTAS
--------------------------------------------------

- Captura Stripe TEST **não** feita: nenhum poço chegou a Session de unlist/draft; bag 2 sellers bloqueada; INSERT pago não persiste captura. Não há Δwallet desta ronda a fechar.
- `create-mux-live` no pass1 devolveu stream ao buyer2 **antes** de `user_type=comprador` (perfil lab sem tipo). Pass3: 403. Não é leak de chave alheia; Mux live `72115a99-…` foi `complete` + `ended`.
- Pass2 abortou no `GET` storage com body; pass3 `POST` list `chat-media` / `fleaber-private` → `[]`.
- RPC raffle draw: nome incorrecto no pass1; `batata_live_raffle_assert_seller` → `not_allowed` (HOLD).
- OpenAPI / inventário RPC completo: não refeito (foco intersecções).

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------

Pass 1 **não** gasto em dual Session, offer amount mutável, carrier concluido, disputa seller close, OCR kick, tip sem live, email enum, admin resolve.  
E6 unlist hold: **1 repro** → `order_hold_product_not_listed` (com e sem `live_id` ended/draft).  
E4 bundle self-accept: **1 repro** → coluna/`accepted` não persistiu.  
Tip ended: **1 repro** → metadata.  
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
Existe view vs base (paused items / UUID reviews / product_id): SIM (P2)
Existe policy OR que revela unlist: SIM (P2, via reserva ended, sem compra)
Existe trigger silent falso-OK de compra: NÃO (convert OCR ok sem order; hold bloqueia)
Existe Edge vs BD P0/P1: NÃO (claim token sim / caixa não)
Existe TTL offer→preço stale: NÃO (INSERT offer expirada 403)
Existe pairing token após expire: NÃO (claim 400)
Existe pairing+OCR no que a UI esconde (draft): SIM (P2, sem compra)
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
