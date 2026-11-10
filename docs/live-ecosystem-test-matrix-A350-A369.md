# Matriz expandida — A350 a A369

**Área:** Marketplace TYPE A · cross-pool bridge · PDP ↔ live ↔ gravado (Z82/Z52)  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A350–A369 em `live-ecosystem-test-matrix.md`.

**Nota:** A340–A349 já em `live-ecosystem-test-matrix-A280-A349.md` — A350–A369 é ponte marketplace↔live sem duplicar A340–A349.

**Dependências transversais:** A029 (TYPE A prep L12), A138 (toggle marketplace), A226 (checkout live TYPE A), A225 (shadow live_only), A042/A349 (Z52 merge), A347 (upsert marketplace live item), A340–A349 (pool Z82, blocked/cross_reserved, poll, dedup).

---

## A350 — PDP desde carrossel TYPE A

| Campo | Valor |
|-------|-------|
| **ID** | A350 |
| **Nome** | Navegação carrossel → PDP com contexto live |
| **Pré-condições** | Live `status=live`; item TYPE A (`item_kind=marketplace_product`, `product_id` ligado); comprador autenticado |
| **Passos** | 1. Entrar player 2. No card TYPE A, abrir PDP (tap info/título ou acção equivalente) 3. Inspeccionar params e UI |
| **Resultado esperado** | `ProductDetailsPageWidget` abre com `originLiveId`, `originLiveItemId`, `originSellerId`, `originIsLive=true`; produto marketplace correcto; **sem** forçar checkout live inline se acção for «ver detalhes» |
| **Componentes afectados** | `fleaber_live_player_widget.dart` (`_openCheckoutForProduct` / navegação PDP), `product_details_page_widget.dart` (`routeExtraForProduct`), `nav.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Manual |
| **Dados necessários** | `live_id`, TYPE A `live_item_id`, `product_id`, buyer JWT |
| **Validar BD** | `live_items.product_id` match `products.id`; `list_on_marketplace=true` |
| **Validar UI** | PDP mostra título/foto marketplace; chip/banner origem live se aplicável; botão voltar ao player |
| **Risco de regressão** | Alto — entry bridge carrossel↔marketplace |
| **Dependências** | A029; A347; A171 (originLiveId PDP) |

---

## A351 — Marketplace feed após toggle ON

| Campo | Valor |
|-------|-------|
| **ID** | A351 |
| **Nome** | Home feed lista produto após `list_on_marketplace=true` |
| **Pré-condições** | Produto marketplace seller; item TYPE A no catálogo live; toggle OFF inicial |
| **Passos** | 1. Seller activa «Listar no marketplace» (prep ou mid-live) 2. Aguardar refresh feed 3. Abrir Home → tab Marketplace |
| **Resultado esperado** | Card aparece no feed (`products.list_on_marketplace=true`); thumbnail/título/preço marketplace; link PDP funcional |
| **Componentes afectados** | `home_page_widget.dart` (query `list_on_marketplace`), `live_catalog_stock_service.dart`, `batata_upsert_marketplace_live_item` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | `product_id`, seller, live activa opcional |
| **Validar BD** | `products.list_on_marketplace=true`; `live_items.list_on_marketplace=true` |
| **Validar UI** | Card visível Home; ausente quando toggle OFF (ver A364) |
| **Risco de regressão** | Alto — revenue path TYPE A |
| **Dependências** | A138; A029; A347 |

---

## A352 — Stock sync live → PDP marketplace (Z82)

| Campo | Valor |
|-------|-------|
| **ID** | A352 |
| **Nome** | Venda live decrementa qty visível no PDP |
| **Pré-condições** | RR1 qty ≥3; TYPE A listado marketplace; live activa; PDP aberto ou refreshável |
| **Passos** | 1. Registar qty inicial PDP (`products.quantity` + pool RPC) 2. Vender 1 un. na live (aceite+pagamento) 3. Reabrir/atualizar PDP |
| **Resultado esperado** | PDP qty/stock copy reflecte pool Z82 (`available_qty` −1); **não** oversell marketplace; alinhado A340 sem re-testar dedup |
| **Componentes afectados** | `live_items_inventory_batata.sql` (Z82), `product_details_page_widget.dart` (`_fetchLiveStockSnapshot`, `_displayQuantity`), `batata_live_item_stock` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | logical_item_id partilhado; order live `pago` |
| **Validar BD** | `batata_live_item_stock(live_item_id).available_qty` = qty PDP −1; `products.quantity` coerente |
| **Validar UI** | Label stock PDP; CTA comprar desactivado se 0 |
| **Risco de regressão** | Crítico — oversell cross-canal |
| **Dependências** | A340; A343; A339; A348 |

---

## A353 — Preço live ≠ preço marketplace (UI)

| Campo | Valor |
|-------|-------|
| **ID** | A353 |
| **Nome** | Superfícies mostram preço correcto por canal |
| **Pré-condições** | TYPE A; `live_items.price=15€`; `products.price=20€`; ambos >0 |
| **Passos** | 1. Ver card carrossel live 2. Abrir PDP marketplace 3. Comparar breakdowns |
| **Resultado esperado** | Carrossel/checkout **live** mostra 15€ (`resolveFreshUnitPrice`); PDP mostra 20€ (`products.price`); **sem** misturar valores na mesma superfície |
| **Componentes afectados** | `live_item_price_gate.dart`, `fleaber_live_player_widget.dart`, `product_details_page_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Bot |
| **Dados necessários** | TYPE A item preços divergentes |
| **Validar BD** | `live_items.price` ≠ `products.price` persistidos |
| **Validar UI** | 15€ player; 20€ PDP hero + checkout sheet |
| **Risco de regressão** | Alto — disputas preço / KPI errado |
| **Dependências** | A226 (live cobra live); A360 (PDP cobra marketplace); A134 |

---

## A354 — Cross-pool 3-way live + gravado + marketplace

| Campo | Valor |
|-------|-------|
| **ID** | A354 |
| **Nome** | Pool RR1 com vendas live, gravado e reserva marketplace |
| **Pré-condições** | `quantity=10` mesmo `logical_item_id`; live A activa; gravado B `ended`; listing marketplace ON |
| **Passos** | 1. Vender 1 un. live A (pago) 2. Vender 1 un. gravado B (`product_id` order) 3. Reserva marketplace pending (order `reserva_pendente`) 4. Ver carrossel, PDP, catálogo seller |
| **Resultado esperado** | `available_qty=7` (10−2 vendidos−1 reserva bloqueante); KPI Total·Disp·Reservas coerentes nas 3 superfícies; origem irrelevante para pool |
| **Componentes afectados** | Z82 `batata_live_items_same_stock_pool`, `live_catalog_stock_service.dart`, `product_details_page_widget.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | 2 lives + 1 product; 3 transacções distintas |
| **Validar BD** | RPC stock: sold=2, blocked/reserved=1, available=7 |
| **Validar UI** | Carrossel «7 disp»; PDP qty 7; seller catálogo barra = Disp |
| **Risco de regressão** | Crítico — puzzle stock 3 vias |
| **Dependências** | A340; A341; A342; A346; A352 |

---

## A355 — `logical_item_id` link PDP ↔ live

| Campo | Valor |
|-------|-------|
| **ID** | A355 |
| **Nome** | PDP e live items partilham linhagem via `logical_item_id` |
| **Pré-condições** | ≥2 `live_items` mesmo `logical_item_id`; 1 TYPE A com `product_id`; comprador abre PDP |
| **Passos** | 1. Query linhagem 2. Venda/reserva noutro `live_item_id` mesma linhagem 3. Refresh PDP com `originLiveItemId` |
| **Resultado esperado** | Stock PDP (com contexto live) reflecte pool da linhagem, não só row local; ref history coerente |
| **Componentes afectados** | `live_logical_item_id_batata.sql`, `live_catalog_stock_service.dart` (`p_logical_item_id`), `ref_history_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | `logical_item_id` uuid partilhado |
| **Validar BD** | `select logical_item_id from live_items where id in (...)` igual; RPC usa pool |
| **Validar UI** | Qty PDP muda após acção noutro live da linhagem |
| **Risco de regressão** | Alto — stock isolado por row |
| **Dependências** | A004–A009 (linhagem L-series); A352 |

---

## A356 — Ref history: vendas marketplace no prep

| Campo | Valor |
|-------|-------|
| **ID** | A356 |
| **Nome** | Prep mostra histórico vendas marketplace da ref |
| **Pré-condições** | Produto com orders marketplace `pago` anteriores; seller abre prep ou gestão referências |
| **Passos** | 1. Adicionar/seleccionar produto TYPE A no prep 2. Abrir sheet ref history / detalhe linhagem 3. Ver entradas |
| **Resultado esperado** | Lista inclui vendas marketplace (origem «Marketplace»); qty/preço/data; **sem** duplicar converted live+order |
| **Componentes afectados** | `ref_history_service.dart`, `ref_history_detail_sheet.dart`, `preparar_directo_page_widget.dart`, `gestao_referencias_page_widget.dart`, `batata_ref_history_detail` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | ≥1 order marketplace `pago`; `ref_code` ou `logical_item_id` |
| **Validar BD** | RPC `batata_ref_history_detail` retorna rows marketplace |
| **Validar UI** | Sheet history com badge origem; seller informado antes go-live |
| **Risco de regressão** | Médio — seller re-lista ref esgotada |
| **Dependências** | A029; A344 (dedup); A346 |

---

## A357 — Opt-in marketplace mid-live

| Campo | Valor |
|-------|-------|
| **ID** | A357 |
| **Nome** | Toggle «Listar no marketplace» durante directo activo |
| **Pré-condições** | Live `status=live`; item TYPE A no catálogo; `list_on_marketplace=false` inicial |
| **Passos** | 1. Seller abre catálogo studio 2. Activa toggle marketplace mid-live 3. Comprador refresca Home + carrossel |
| **Resultado esperado** | `list_on_marketplace=true` imediato; item permanece no carrossel; feed marketplace actualiza (A351); checkout live continua TYPE A |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `live_catalog_stock_service.dart`, `batata_upsert_marketplace_live_item` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa; product_id |
| **Validar BD** | `live_items.list_on_marketplace=true`; `products.list_on_marketplace=true` |
| **Validar UI** | Toggle ON studio; card Home ≤30s; carrossel inalterado |
| **Risco de regressão** | Alto — Z52 apaga listing mid-sync |
| **Dependências** | A138; A347; A349; A042 |

---

## A358 — Quick edit foto TYPE A sync PDP

| Campo | Valor |
|-------|-------|
| **ID** | A358 |
| **Nome** | Foto quick edit live propaga carrossel + PDP |
| **Pré-condições** | TYPE A listado; live activa; nova foto seleccionada no quick edit catálogo |
| **Passos** | 1. Seller quick edit → alterar foto 2. Guardar 3. Ver carrossel comprador 4. Abrir PDP marketplace |
| **Resultado esperado** | `live_items.image_url` actualizado; carrossel mostra nova foto; PDP hero usa foto marketplace (`products.image`) **ou** sync policy documentada — **sem** foto quebrada/placeholder permanente |
| **Componentes afectados** | `live_vendor_studio_panel.dart` (quick edit), `live_catalog_sync.dart`, `product_details_page_widget.dart`, `BatataCachedImage` |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | TYPE A item; ficheiro imagem teste |
| **Validar BD** | `live_items.image_url` updated_at recente |
| **Validar UI** | Carrossel + PDP reflectem foto correcta pós-cache |
| **Risco de regressão** | Médio — drift visual cross-canal |
| **Dependências** | A044 (N/A descrição); A349; A138 |

---

## A359 — `live_only` shadow nunca no marketplace

| Campo | Valor |
|-------|-------|
| **ID** | A359 |
| **Nome** | Shadow `live_only` ausente do feed marketplace |
| **Pré-condições** | Item `item_kind=live_only` com shadow `checkout_product_id`; **sem** TYPE A; seller tenta listar |
| **Passos** | 1. Confirmar toggle marketplace indisponível ou OFF 2. Query feed Home 3. Busca directa por `product_id` shadow |
| **Resultado esperado** | Shadow **não** aparece Home/perfil marketplace; `list_on_marketplace=false`; checkout live usa shadow (A225); listing marketplace real intacto |
| **Componentes afectados** | `live_catalog_stock_service.dart`, `home_page_widget.dart`, shadow rows SQL, `create-payment-intent` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_only item + shadow product |
| **Validar BD** | shadow `products.list_on_marketplace=false`; `available_for_live=false` ou policy shadow |
| **Validar UI** | Ausência feed; carrossel live OK |
| **Risco de regressão** | Alto — shadow polui marketplace (Z52) |
| **Dependências** | A225; A003 (live_only); A042 |

---

## A360 — Checkout PDP usa preço marketplace

| Campo | Valor |
|-------|-------|
| **ID** | A360 |
| **Nome** | Compra orgânica PDP — preço `products.price`, não live |
| **Pré-condições** | TYPE A preços divergentes (live 15€, marketplace 20€); comprador abre PDP **sem** saco live / sem `originPayQty` bag |
| **Passos** | 1. Home → PDP 2. Comprar now / checkout sheet 3. Ver total Stripe metadata |
| **Resultado esperado** | `itemPrice = products.price` (20€); order `price_total` baseado marketplace; **≠** `resolveFreshUnitPrice` live; contraste explícito com A226 |
| **Componentes afectados** | `product_details_page_widget.dart` (`_showCheckoutSheet`, `_openStripeCheckoutInBrowser`), edge checkout marketplace |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | product preço marketplace ≠ live |
| **Validar BD** | `orders.price_total` / line items = 20€ × qty (+ taxas) |
| **Validar UI** | Sheet breakdown 20€; **sem** override live |
| **Risco de regressão** | Crítico — cobrança canal errado |
| **Dependências** | A353; A226 (contraste); A202 |

---

## A361 — Badge «Em directo» no PDP

| Campo | Valor |
|-------|-------|
| **ID** | A361 |
| **Nome** | PDP indica sessão live activa ligada ao artigo |
| **Pré-condições** | TYPE A listado; live `status=live`; PDP aberto com `originLiveId` + `originIsLive=true` |
| **Passos** | 1. Abrir PDP desde carrossel live 2. Ver hero/meta 3. Terminar live 4. Reabrir PDP |
| **Resultado esperado** | Com live activa: badge/chip «Em directo» ou equivalente + link voltar player; após `ended`: badge GRAVADO ou ausência «Em directo»; listing marketplace mantém-se |
| **Componentes afectados** | `product_details_page_widget.dart` (`_listingStatusLabel`, origin params), `fleaber_live_player_widget.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Manual |
| **Dados necessários** | live activa → ended transition |
| **Validar BD** | `lives.status` live → ended |
| **Validar UI** | Badge estado correcto; CTA «Ver directo» quando aplicável |
| **Risco de regressão** | Médio — confusão live vs gravado |
| **Dependências** | A350; A171; A365 |

---

## A362 — `blocked_qty` no PDP (cross-pool)

| Campo | Valor |
|-------|-------|
| **ID** | A362 |
| **Nome** | Reserva aceite noutro live reduz qty PDP |
| **Pré-condições** | Live A com reserva **aceite**; Live B TYPE A mesmo pool; PDP com `originLiveItemId` live B |
| **Passos** | 1. Aceitar reserva live A 2. Abrir PDP (contexto live B ou orgânico com fetch pool) 3. Comparar qty |
| **Resultado esperado** | `_maxCheckoutQuantity` / stock copy usa `available_qty` RPC incluindo `blocked_qty` remoto; **≠** `products.quantity` bruto se pool menor |
| **Componentes afectados** | `product_details_page_widget.dart`, Z82 RPC, `LiveCatalogStockSnapshot` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | 2 lives; 1 aceite live A |
| **Validar BD** | RPC `blocked_qty` > 0; `available_qty` decrementado |
| **Validar UI** | PDP max qty = available pool; label coerente |
| **Risco de regressão** | Alto — A3 puzzle overbook |
| **Dependências** | A341; A352; A354 |

---

## A363 — `cross_reserved_qty` copy PDP

| Campo | Valor |
|-------|-------|
| **ID** | A363 |
| **Nome** | Reservas noutras lives visíveis no stock PDP |
| **Pré-condições** | Reserva pending/accepted live A; PDP live B mesmo pool (`originLiveItemId`) |
| **Passos** | 1. Criar reserva live A 2. Abrir PDP live B 3. Ler copy Reservas/Disp |
| **Resultado esperado** | `displayReservedQty` inclui cross; copy «X reservadas» ou barra coerente; comprador não vê stock «livre» inflacionado |
| **Componentes afectados** | `LiveCatalogStockSnapshot`, `product_details_page_widget.dart`, player carousel (contraste) |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | 2 lives; 1 reserva cross |
| **Validar BD** | RPC `cross_reserved_qty` > 0 |
| **Validar UI** | Texto reservas PDP ≈ carrossel live B |
| **Risco de regressão** | Alto — A342 extendido a PDP |
| **Dependências** | A342; A362; A354 |

---

## A364 — Deslist mid-live (feed off, catálogo on)

| Campo | Valor |
|-------|-------|
| **ID** | A364 |
| **Nome** | Toggle OFF remove marketplace feed; item permanece no carrossel |
| **Pré-condições** | TYPE A `list_on_marketplace=true`; live activa; card visível Home |
| **Passos** | 1. Seller desactiva toggle marketplace mid-live 2. Refresh Home 3. Ver carrossel live |
| **Resultado esperado** | Feed marketplace **sem** card; carrossel live **com** item; `live_items` row intacta; checkout live TYPE A ainda possível |
| **Componentes afectados** | `live_catalog_stock_service.dart`, `home_page_widget.dart`, `live_vendor_studio_panel.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | listing activo pré-toggle |
| **Validar BD** | `products.list_on_marketplace=false`; `live_items.list_on_marketplace=false`; row live não apagada |
| **Validar UI** | Ausência Home; presença carrossel |
| **Risco de regressão** | Alto — deslist apaga catálogo live (Z52) |
| **Dependências** | A138; A351; A349; A042 |

---

## A365 — Listing persiste após live ended

| Campo | Valor |
|-------|-------|
| **ID** | A365 |
| **Nome** | Marketplace listing sobrevive fim do directo |
| **Pré-condições** | TYPE A `list_on_marketplace=true`; live activa com item |
| **Passos** | 1. Seller termina live (`status=ended`) 2. Ver Home feed 3. Abrir PDP directo |
| **Resultado esperado** | Card marketplace permanece; PDP comprável; carrossel replay/gravado separado; pool Z82 continua (A340) |
| **Componentes afectados** | `live_publish_cleanup.dart`, `live_catalog_sync.dart`, `home_page_widget.dart`, Z82 |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | live ended; listing ON |
| **Validar BD** | `products.list_on_marketplace=true` pós-ended; `live_items` ended live rows preserved |
| **Validar UI** | Feed + PDP OK; player gravado badge GRAVADO |
| **Risco de regressão** | Alto — cleanup apaga listing |
| **Dependências** | A349; A042; A303 (gravado); A361 |

---

## A366 — KPI agregado pool seller

| Campo | Valor |
|-------|-------|
| **ID** | A366 |
| **Nome** | Total · Disp · Reservas alinhados catálogo ↔ marketplace |
| **Pré-condições** | Cross-pool activo (live + reserva remota + venda marketplace); seller studio aberto |
| **Passos** | 1. Executar mix vendas/reservas (A354) 2. Ler KPI barra catálogo 3. Comparar RPC + PDP |
| **Resultado esperado** | «Total · Disp · Reservas» seller = RPC Z82; barra fundo carrossel comprador = Disp; **sem** puzzle 2/1 documentado A341 |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `LiveCatalogStockSnapshot`, `live_catalog_stock_service.dart` poll |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual |
| **Dados necessários** | pool partilhado; 2+ eventos stock |
| **Validar BD** | RPC snapshot JSON igual em seller/buyer ±2s (A348) |
| **Validar UI** | KPI strings idênticas seller catálogo vs buyer card |
| **Risco de regressão** | Alto — KPI errado → overbook |
| **Dependências** | A341; A342; A348; A354 |

---

## A367 — Venda marketplace → carrossel live B

| Campo | Valor |
|-------|-------|
| **ID** | A367 |
| **Nome** | Order marketplace decrementa stock carrossel live |
| **Pré-condições** | TYPE A pool partilhado; live B activa; comprador compra via PDP orgânico (A360) |
| **Passos** | 1. Completar order marketplace `pago` 2. Observar carrossel live B (poll 2s) 3. Ver catálogo seller |
| **Resultado esperado** | `available_qty` −qty order; carrossel actualiza; Z82 branch `product_id` conta (A343); feed qty coerente |
| **Componentes afectados** | Z82 SQL, `fleaber_live_player_widget.dart`, `live_catalog_stock_service.dart`, `product_details_page_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | order marketplace pago |
| **Validar BD** | sold increment; available decrement |
| **Validar UI** | Carrossel Disp actualizado ≤4s |
| **Risco de regressão** | Crítico — live oversell pós-venda marketplace |
| **Dependências** | A343; A352; A348; A360 |

---

## A368 — Prep inherit TYPE A sem duplicar product

| Campo | Valor |
|-------|-------|
| **ID** | A368 |
| **Nome** | Novo directo inherit marketplace item — 1 product row |
| **Pré-condições** | Live ended com TYPE A listado; seller prep novo directo → inherit catálogo |
| **Passos** | 1. Prep Continuar inherit 2. Go-live 3. Query `products` + `live_items` |
| **Resultado esperado** | Mesmo `product_id`; **sem** duplicate `products` row; `list_on_marketplace` preservado; bridge intacto |
| **Componentes afectados** | `live_catalog_sync.dart`, `batata_upsert_marketplace_live_item`, `preparar_directo_page_widget.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended live + inherit draft |
| **Validar BD** | `count(*) products where id=$pid` = 1; `live_items.product_id` stable |
| **Validar UI** | Toggle marketplace ON pós-inherit |
| **Risco de regressão** | Médio — duplicate listing SEO |
| **Dependências** | A042; A349; A029; A347 |

---

## A369 — Regressão Z52+Z82 pós re-sync prep

| Campo | Valor |
|-------|-------|
| **ID** | A369 |
| **Nome** | Re-sync prep não quebra bridge marketplace↔live↔pool |
| **Pré-condições** | TYPE A activo mid-season; vendas live+marketplace; `list_on_marketplace=true` |
| **Passos** | 1. Prep re-sync / merge catálogo 2. Verificar flags marketplace 3. RPC stock 4. Feed + carrossel + PDP |
| **Resultado esperado** | Z52: `list_on_marketplace` + `product_id` intactos; Z82: pool qty correcto pós-merge; **sem** reset sold/blocked |
| **Componentes afectados** | `live_catalog_sync.dart`, `batata_update_live_item`, Z82, `live_items_inventory_batata.sql` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | live_item marketplace com histórico vendas |
| **Validar BD** | flags unchanged; `batata_live_item_stock` = pré-sync ± eventos reais |
| **Validar UI** | Feed + carrossel + PDP coerentes |
| **Risco de regressão** | Crítico — regressão documentada Z52 apagou listings |
| **Dependências** | A042; A349; A340; A347; A357 |

---

## Apêndice A — Resumo A350–A369

| Bloco | IDs | Foco |
|-------|-----|------|
| Navegação bridge | A350, A355, A361 | Carrossel→PDP, `logical_item_id`, badges live |
| Marketplace feed | A351, A357, A364, A365 | Toggle ON/OFF, mid-live, persistência ended |
| Stock Z82 sync | A352, A354, A362, A363, A367 | Live→PDP, 3-way pool, blocked/cross PDP, marketplace→live |
| Preço por canal | A353, A360 | Live vs marketplace UI; checkout PDP vs live (A226) |
| Integridade TYPE A | A358, A359, A368, A369 | Foto sync, shadow guard, inherit, re-sync Z52+Z82 |
| Seller intel | A356, A366 | Ref history prep; KPI agregado pool |

**Total fichas:** 20 (A350–A369).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| PDP desde live vs checkout inline | A350, A226, A360 |
| Preço live ≠ marketplace | A353, A360, A226 |
| Pool Z82 cross-canal | A352, A354, A367, A340 (base) |
| blocked / cross_reserved UI | A362, A363, A341, A342 |
| Z52 merge / listing survival | A364, A365, A369, A042, A349 |
| Shadow live_only isolation | A359, A225 |
| Ref history / prep intel | A356, A355 |
| KPI seller = buyer | A366, A348 |

### Mapa dependências externas (faixa A350–A369)

| ID externo | Relação |
|------------|---------|
| **A029** | TYPE A prep L12 — base toggle sem sheet linhagem |
| **A138** | Toggle `list_on_marketplace` — A351, A357, A364 |
| **A226** | Checkout live TYPE A preço live — contraste A360 |
| **A225** | Shadow live_only — A359 guard |
| **A042 / A349** | Z52 merge sync — A369, A365, A364 |
| **A347** | Upsert marketplace live item — A350, A351, A357 |
| **A340–A349** | Pool Z82, blocked, cross_reserved, poll, dedup — base sem duplicar |

---

## Apêndice B — P0 desta faixa (15)

| ID | Nome curto |
|----|------------|
| A350 | Carrossel → PDP TYPE A |
| A351 | Feed pós toggle ON |
| A352 | Stock live → PDP Z82 |
| A353 | Preço UI por canal |
| A354 | Pool 3-way |
| A357 | Opt-in mid-live |
| A359 | Shadow nunca feed |
| A360 | Checkout PDP preço marketplace |
| A362 | blocked_qty PDP |
| A363 | cross_reserved PDP |
| A364 | Deslist mid-live |
| A365 | Listing pós-ended |
| A366 | KPI pool agregado |
| A367 | Venda marketplace → live |
| A369 | Regressão Z52+Z82 |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A369 | Z52+Z82 merge — regressão apagou listings | Integration |
| 2 | A352 | Stock live→PDP — oversell cross-canal | Integration |
| 3 | A360 | Preço canal errado — disputas Stripe | Integration |
| 4 | A367 | Marketplace→live reverse sync | Integration |
| 5 | A359 | Shadow no feed — poluição catálogo | Integration |
| 6 | A354 | Pool 3-way — cenário real produção | Integration |
| 7 | A362 | blocked_qty PDP — overbook silencioso | Integration |
| 8 | A363 | cross_reserved PDP — stock inflacionado | Bot + Integration |
| 9 | A368 | Duplicate product row — SEO/dados | Integration |
| 10 | A355 | logical_item_id pool — stock isolado | Integration |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Integration** | A351, A352, A354, A355, A356, A359, A360, A362, A365, A367, A368, A369 |
| **Manual** | A353, A357, A358, A364, A366 |
| **Maestro** | A350, A361 |
| **Bot** | A353 (parcial), A363 (parcial) |
| **Híbrido** | A350 (Maestro + Manual), A352 (Integration + Manual), A354 (Integration + Manual), A360 (Integration + Manual), A361 (Maestro + Manual), A362 (Integration + Manual), A365 (Integration + Manual), A367 (Integration + Manual), A356 (Integration + Manual) |

---

## Apêndice E — Riscos críticos (levantamento)

1. **Preço canal errado (A353/A360 vs A226):** PDP orgânico deve cobrar `products.price`; live checkout cobra `resolveFreshUnitPrice` — inversão quebra confiança e KPI.
2. **Oversell cross-canal (A352/A367/A354):** venda live ou marketplace não reflectida no outro canal → checkout duplo (Z82 gap).
3. **Z52 merge apaga listing (A369/A364/A365):** re-sync prep ou deslist mid-live remove row marketplace ou `list_on_marketplace` — regressão documentada.
4. **Shadow no feed (A359/A225):** `live_only` shadow listado no Home polui catálogo e duplica refs.
5. **blocked/cross PDP (A362/A363):** PDP usa `products.quantity` bruto ignorando pool → max checkout > available (extensão A341/A342).
6. **KPI puzzle (A366):** seller Total/Disp ≠ buyer carrossel → overbook operacional.
7. **Mid-live toggle race (A357):** toggle ON durante sync merge pode perder flag ou duplicar upsert.
8. **Ended cleanup (A365):** `live_publish_cleanup` ou ended handler deslista marketplace involuntariamente.
9. **logical_item_id orphan (A355):** items sem linhagem partilhada isolam stock — pool falso «disponível».
10. **Ref history gap (A356):** seller re-introduz ref esgotada no prep por histórico marketplace incompleto.

---

*Fim A350–A369. Ponte marketplace↔live; não duplica A340–A349.*
