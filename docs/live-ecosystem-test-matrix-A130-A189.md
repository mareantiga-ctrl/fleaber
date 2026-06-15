# Matriz expandida — A130 a A189

**Área:** Catálogo seller + comprador player  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A130–A189 em `live-ecosystem-test-matrix.md`.

**Nota:** A130–A144 cobrem catálogo seller (vitrine, stock, marketplace); A145–A159 entrada player + reservas base; A160–A189 player comprador alargado (chat, realtime, rifa, edge cases).

---

## A130 — Activar vitrine (is_active) no catálogo

| Campo | Valor |
|-------|-------|
| **ID** | A130 |
| **Nome** | Activar vitrine (is_active) no catálogo |
| **Pré-condições** | Live `status=live`; seller no studio tab Catálogo; ≥2 `live_items` no directo |
| **Passos** | 1. Abrir tab Catálogo 2. Tocar «Mostrar» / activar artigo B 3. (Opcional) comprador no player observa carrossel |
| **Resultado esperado** | Artigo B `is_active=true`; outros `is_active=false`; evento `live_item_show_events`; comprador vê highlight B no carrossel |
| **Componentes afectados** | `live_vendor_studio_panel.dart`, `live_item_show_events`, `live_catalog_sync.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | `live_id`, ≥2 items, seller JWT |
| **Validar BD** | `live_items.is_active` — só B true; row em `live_item_show_events` |
| **Validar UI** | Seller: chip «Em vitrine»; buyer: highlight carrossel segue B |
| **Risco de regressão** | Alto — vitrine errada quebra reservas/comprador |
| **Dependências** | A054 (go-live); A159 (highlight buyer) |

---

## A131 — Stock +/- e barra Total·Disp (A3)

| Campo | Valor |
|-------|-------|
| **ID** | A131 |
| **Nome** | Barra catálogo alinhada com `available_qty` RPC |
| **Pré-condições** | Item com `blocked_qty` noutro directo (cross-pool) ou reservas cross-live |
| **Passos** | 1. Abrir catálogo seller 2. Comparar label Total·Disp vs barra de fundo 3. +/- stock 4. Recomparar |
| **Resultado esperado** | **Disp** = `available_qty` RPC (não confundir com `quantity` bruto); Total mostra bruto quando diferem |
| **Componentes afectados** | `live_catalog_stock_service.dart`, studio catálogo barra |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | item com blocked_qty; 2 lives mesmo produto (Z82) |
| **Validar BD** | RPC stock: `available_qty`, `blocked_qty`, `cross_reserved_qty` |
| **Validar UI** | Catálogo «Total X · Disp Y»; barra fundo = Disp |
| **Risco de regressão** | Crítico — A3 FAIL histórico (13 vs 1) |
| **Dependências** | A340+ (cross-pool); A144 |

---

## A132 — Marcar vendido manual + repor qty (R32/#3)

| Campo | Valor |
|-------|-------|
| **ID** | A132 |
| **Nome** | Repor stock após sold — catálogo e carrossel sync |
| **Pré-condições** | Item `sold` ou `available_qty=0` após venda/aceite |
| **Passos** | 1. Menu artigo → +10 unidades (ou edit qty) 2. Ver catálogo seller 3. Ver carrossel comprador |
| **Resultado esperado** | Catálogo e carrossel **Qtd: 10**; badge sold removido; barra activa |
| **Componentes afectados** | `batata_update_live_item`, `batata_recompute`, `live_catalog_stock_service.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | item sold; seller no studio |
| **Validar BD** | `live_items.quantity`, `available_qty` após recompute |
| **Validar UI** | Qtd 10 em catálogo + carrossel; sem ESGOTADO |
| **Risco de regressão** | Alto — R32 FAIL (8 vs 10) |
| **Dependências** | A206 (venda); A133 (negativo sold badge) |

---

## A133 — ESGOTADO só após aceite (BATATA)

| Campo | Valor |
|-------|-------|
| **ID** | A133 |
| **Nome** | Badge ESGOTADO nunca só por pending |
| **Pré-condições** | Stock bruto 1; reserva `pending` sem aceite |
| **Passos** | 1. Comprador reserva qty 1 2. Ver badge carrossel/saco **sem** aceitar |
| **Resultado esperado** | **Sem** badge ESGOTADO; waitlist/reserva permitida; `reserved_full` só pós-aceite |
| **Componentes afectados** | stock rules, `isSoldOut`, carrossel buyer |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | stock 1; buyer JWT |
| **Validar BD** | `live_items` status ≠ `reserved_full` com só pending |
| **Validar UI** | Sem ESGOTADO; chip Espera OK se fila cheia |
| **Risco de regressão** | Crítico — regra BATATA core |
| **Dependências** | A148; A173; A192 |

---

## A134 — Quick edit preço no live (Z53)

| Campo | Valor |
|-------|-------|
| **ID** | A134 |
| **Nome** | Editar preço inline no catálogo live |
| **Pré-condições** | Live activa; item sem venda `converted`; seller tab Catálogo |
| **Passos** | 1. Abrir quick edit preço 2. Alterar valor 3. Guardar 4. Comprador vê carrossel |
| **Resultado esperado** | `live_items.price` actualizado; carrossel reflecte novo preço; checkout usa preço live (`resolveFreshUnitPrice`) |
| **Componentes afectados** | studio quick edit Z53, `batata_update_live_item`, carrossel poll |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | item price_pending ou price > 0 |
| **Validar BD** | `live_items.price` = novo valor |
| **Validar UI** | Preço actualizado seller + buyer <5s |
| **Risco de regressão** | Médio — P10 bloqueio pós-venda (A228) |
| **Dependências** | A130; A202/A227 (price gate) |

---

## A135 — Quick edit descrição (Z54)

| Campo | Valor |
|-------|-------|
| **ID** | A135 |
| **Nome** | Editar descrição inline no catálogo live |
| **Pré-condições** | Item activo ou inactivo no catálogo |
| **Passos** | 1. Quick edit descrição 2. Guardar 3. Comprador expande detalhe carrossel |
| **Resultado esperado** | Descrição persistida; visível no player sem reload app |
| **Componentes afectados** | studio quick edit Z54, `live_items.description` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live_item id |
| **Validar BD** | `live_items.description` actualizado |
| **Validar UI** | Texto novo no carrossel/detalhe |
| **Risco de regressão** | Baixo |
| **Dependências** | A130 |

---

## A136 — Quick edit fotos (Z55)

| Campo | Valor |
|-------|-------|
| **ID** | A136 |
| **Nome** | Alterar fotos do artigo durante live |
| **Pré-condições** | Item com ≥1 foto ou placeholder |
| **Passos** | 1. Quick edit fotos 2. Adicionar/remover imagem 3. Guardar 4. Ver carrossel/checkout |
| **Resultado esperado** | `image_url` / gallery actualizada; miniatura carrossel e checkout (A196) reflectem |
| **Componentes afectados** | studio quick edit Z55, storage upload, `BatataCachedImage` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | imagem teste |
| **Validar BD** | `live_items.image_url` ou gallery JSON |
| **Validar UI** | Thumbnail nova no carrossel |
| **Risco de regressão** | Médio — cache stale (A177) |
| **Dependências** | A130; A196 |

---

## A137 — Quick edit estado (Z56)

| Campo | Valor |
|-------|-------|
| **ID** | A137 |
| **Nome** | Editar estado/condição do artigo no live |
| **Pré-condições** | Item TYPE A ou live_only com campo estado |
| **Passos** | 1. Quick edit estado 2. Seleccionar novo valor 3. Guardar |
| **Resultado esperado** | Estado persistido; label visível no carrossel se exposto |
| **Componentes afectados** | studio quick edit Z56, `live_items` metadata |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | item com state field |
| **Validar BD** | state/condition column actualizada |
| **Validar UI** | Chip estado no carrossel |
| **Risco de regressão** | Baixo |
| **Dependências** | A130 |

---

## A138 — Marketplace toggle list_on_marketplace

| Campo | Valor |
|-------|-------|
| **ID** | A138 |
| **Nome** | Opt-in marketplace no catálogo live |
| **Pré-condições** | Item TYPE A ligado a `products`; seller no catálogo |
| **Passos** | 1. Activar toggle «Listar no marketplace» 2. Query product 3. (Opcional) checkout |
| **Resultado esperado** | `list_on_marketplace=true`; checkout via `product_id` marketplace; listing marketplace intacto |
| **Componentes afectados** | `live_catalog_stock_service.dart` (`p_list_on_marketplace`), studio toggle |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | TYPE A item + product_id |
| **Validar BD** | `live_items.list_on_marketplace=true`; product unchanged |
| **Validar UI** | Toggle ON; badge marketplace se aplicável |
| **Risco de regressão** | Alto — Z52 marketplace merge (A347) |
| **Dependências** | A029; A226; A347 |

---

## A139 — Cross-live stock poll 2s (Z57)

| Campo | Valor |
|-------|-------|
| **ID** | A139 |
| **Nome** | Poll stock cross-session cada ~2s |
| **Pré-condições** | Mesmo produto/pool em 2 lives ou live + marketplace reserva |
| **Passos** | 1. Reservar/vender noutra sessão 2. Observar catálogo seller live A 3. Esperar poll |
| **Resultado esperado** | Disp/barra actualiza em ~2s sem reload manual; `blocked_qty` reflectido |
| **Componentes afectados** | `live_catalog_stock_service.dart` poll timer Z57, cross-pool RPC |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 sessions mesmo logical_item_id |
| **Validar BD** | `available_qty` desce após acção remota |
| **Validar UI** | Total·Disp sync <3s |
| **Risco de regressão** | Alto — A3 puzzle 2 vs 1 |
| **Dependências** | A131; A340+ |

---

## A140 — P14.1 contador vendidos após pago

| Campo | Valor |
|-------|-------|
| **ID** | A140 |
| **Nome** | KPI vendidos incrementa pós-pagamento |
| **Pré-condições** | Live activa; item com preço; comprador paga (A206) |
| **Passos** | 1. Baseline contador vendidos catálogo 2. Completar pagamento 3. Ver catálogo seller |
| **Resultado esperado** | Contador **Vendidos** +1 (ou +qty); barra reflecte unidades vendidas |
| **Componentes afectados** | studio catálogo KPI, reconcile stock |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | converted order |
| **Validar BD** | sold count / `live_items` sold qty |
| **Validar UI** | Label Vendidos actualizado |
| **Risco de regressão** | Médio — desync KPI vs BD |
| **Dependências** | A206; A142 |

---

## A141 — P14.2 contador reservas pending

| Campo | Valor |
|-------|-------|
| **ID** | A141 |
| **Nome** | KPI reservas reflecte pending |
| **Pré-condições** | Live activa; sem aceite ainda |
| **Passos** | 1. Comprador reserva 2. Ver contador Reservas no catálogo seller |
| **Resultado esperado** | Reservas incrementa; inclui `blocked_qty` cross-live se regra v6 |
| **Componentes afectados** | studio catálogo KPI, reservation queue |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | pending reservation |
| **Validar BD** | count pending por item |
| **Validar UI** | Contador Reservas +1 |
| **Risco de regressão** | Médio |
| **Dependências** | A148; A172 |

---

## A142 — P14.3 barra após aceite parcial multi-unidade

| Campo | Valor |
|-------|-------|
| **ID** | A142 |
| **Nome** | Barra catálogo após aceite parcial qty multi |
| **Pré-condições** | Item qty ≥2; 2 reservas mesmo artigo (ou qty 2); aceitar **uma** unidade |
| **Passos** | 1. Setup 2× reserva 2. Seller aceita uma 3. Ver barra Vendidos/Reservas |
| **Resultado esperado** | Vendidos +1; Reservas desce; barra coerente com stock bruto |
| **Componentes afectados** | studio barra P14.3, accept RPC |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | multi-unit item; 2 buyers ou qty 2 |
| **Validar BD** | `available_qty`, pending count |
| **Validar UI** | Vendidos +1; Reservas -1 |
| **Risco de regressão** | Alto — regressão P14.3 histórica |
| **Dependências** | A081; A149; A155 |

---

## A143 — Optimistic vitrine rollback em erro

| Campo | Valor |
|-------|-------|
| **ID** | A143 |
| **Nome** | Rollback UI se RPC vitrine falha |
| **Pré-condições** | Live activa; simular erro RPC (offline ou mock) |
| **Passos** | 1. Tocar Mostrar artigo C 2. Forçar falha rede/RPC 3. Observar UI |
| **Resultado esperado** | UI reverte para vitrine anterior; snack erro; BD `is_active` inalterado |
| **Componentes afectados** | `live_vendor_studio_panel.dart` optimistic update |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | network intercept ou staging fault |
| **Validar BD** | `is_active` = estado pré-tentativa |
| **Validar UI** | Highlight não «salta» permanentemente |
| **Risco de regressão** | Médio — vitrine fantasma |
| **Dependências** | A130 |

---

## A144 — live_items.quantity sync pós stock adjust

| Campo | Valor |
|-------|-------|
| **ID** | A144 |
| **Nome** | `quantity` BD sync após +/- stock |
| **Pré-condições** | Item com qty conhecida |
| **Passos** | 1. +/- via catálogo 2. Query `live_items.quantity` 3. Comparar carrossel |
| **Resultado esperado** | `live_items.quantity` = valor editado; carrossel Qtd match; recompute OK |
| **Componentes afectados** | `batata_update_live_item`, `live_catalog_stock_service.dart`, patch v5 sync |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | item id, delta qty |
| **Validar BD** | `quantity`, `available_qty` pós RPC |
| **Validar UI** | Qtd label buyer = BD |
| **Risco de regressão** | Alto — R32 desync |
| **Dependências** | A131; A132 |

---

## A145 — Comprador entra live Home feed

| Campo | Valor |
|-------|-------|
| **ID** | A145 |
| **Nome** | Entrada player via card LIVE Home |
| **Pré-condições** | Live `status=live`, `is_active=true` no feed |
| **Passos** | 1. Home → grid lives 2. Tap card LIVE 3. Aguardar player |
| **Resultado esperado** | `FleaberLivePlayer` abre; HLS/Mux playback; saco visível; badge LIVE |
| **Componentes afectados** | `home_live_feed_grid.dart`, `fleaber_live_player_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | live_id activo, buyer JWT |
| **Validar BD** | `lives.status=live`, `is_active=true` |
| **Validar UI** | Player fullscreen; CTA saco/reservar |
| **Risco de regressão** | Crítico — entry point comprador |
| **Dependências** | A054; A183 |

---

## A146 — Entrar gravado do perfil

| Campo | Valor |
|-------|-------|
| **ID** | A146 |
| **Nome** | Player VOD via perfil vendedor |
| **Pré-condições** | Live `status=ended` com `playback_id` Mux |
| **Passos** | 1. Perfil seller → tab Diretos anteriores 2. Tap gravado |
| **Resultado esperado** | Player VOD; badge **GRAVADO**; chat off (A162); saco/commerce on |
| **Componentes afectados** | `profile_lives_tab.dart`, `_isVodReplay` guards |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended live + playback |
| **Validar BD** | `status=ended`; playback_id not null |
| **Validar UI** | Badge GRAVADO; sem input chat |
| **Risco de regressão** | Alto — A060 VOD downstream |
| **Dependências** | A060; A162; A310+ |

---

## A147 — Deep link `?ref=` rifa

| Campo | Valor |
|-------|-------|
| **ID** | A147 |
| **Nome** | Referral rifa via deep link |
| **Pré-condições** | Rifa activa na live; link com `?ref=` válido |
| **Passos** | 1. Abrir link (guest ou logged out) 2. Login/registo 3. Permanecer player ≥60s |
| **Resultado esperado** | `registerReferralVisit`; qualify 60s (A214); referrer +2 entradas |
| **Componentes afectados** | player raffle referral, deep links, `nav.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | referral token, 2 users |
| **Validar BD** | referral visit row; entries referrer |
| **Validar UI** | Player abre live correcta |
| **Risco de regressão** | Médio |
| **Dependências** | A145; A187; A214 |

---

## A148 — Reservar 1ª vez qty 1

| Campo | Valor |
|-------|-------|
| **ID** | A148 |
| **Nome** | Primeira reserva — pending + chat |
| **Pré-condições** | Stock disponível; preço definido ou price_pending; buyer no player |
| **Passos** | 1. Carrossel → Reservar qty 1 2. Ver snack 3. Ver chat |
| **Resultado esperado** | `live_reservation_requests` `status=pending`, `requested_qty=1`; chat `🛍️`; snack OK |
| **Componentes afectados** | `createRequest`, `live_reservation_queue_service.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro |
| **Dados necessários** | live_item, buyer JWT |
| **Validar BD** | pending row; `source=fleaber_live` |
| **Validar UI** | Snack sucesso; linha saco |
| **Risco de regressão** | Crítico — base toda fila |
| **Dependências** | A145; A191 |

---

## A149 — 2ª reserva mesmo artigo incrementa qty (R6)

| Campo | Valor |
|-------|-------|
| **ID** | A149 |
| **Nome** | Segunda reserva incrementa qty — não duplica row |
| **Pré-condições** | A148 completo — mesma conta, mesmo artigo |
| **Passos** | 1. Reservar de novo mesmo artigo 2. Abrir saco 3. Query BD |
| **Resultado esperado** | **Mesma** linha `requested_qty=2`; **não** 2 rows pending |
| **Componentes afectados** | reservation service increment, gate R6 |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | buyer, live_item_id |
| **Validar BD** | 1 row; `requested_qty=2` |
| **Validar UI** | Saco 1 linha qty 2 |
| **Risco de regressão** | Crítico — R6 FAIL histórico |
| **Dependências** | A148; A197 |

---

## A150 — Waitlist quando stock cheio

| Campo | Valor |
|-------|-------|
| **ID** | A150 |
| **Nome** | Fila de espera quando stock esgotado por aceite |
| **Pré-condições** | Stock 1; 1 reserva **aceite** (consome stock) |
| **Passos** | 1. Segundo comprador reserva 2. Abrir saco 3. Ver chips |
| **Resultado esperado** | Waitlist; chip **Espera #N**; **sem** ESGOTADO só por pending |
| **Componentes afectados** | bag ranking, `isWaitlistPosition` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | 2 buyers; stock 1; 1 aceite |
| **Validar BD** | 2 pending; `queue_position` distinto |
| **Validar UI** | Label Espera âmbar (A2) |
| **Risco de regressão** | Alto — A2/A192 |
| **Dependências** | A133; A081; A192 |

---

## A151 — Card verde aceite no player (R1)

| Campo | Valor |
|-------|-------|
| **ID** | A151 |
| **Nome** | Card verde comprador ao aceite — sem dialog duplicado |
| **Pré-condições** | Comprador no player live; reserva pending |
| **Passos** | 1. Seller aceita 2. Observar player comprador <5s |
| **Resultado esperado** | **Um** card verde acima chat; **sem** dialog overlay duplicado; foto artigo |
| **Componentes afectados** | `fleaber_live_player_widget.dart` realtime accept, patch v4 stream |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices ou Bot+Manual |
| **Validar BD** | reserva `accepted` |
| **Validar UI** | Card verde único; <5s |
| **Risco de regressão** | Crítico — R1 FAIL repetido |
| **Dependências** | A081; A148; A180 |

---

## A152 — Banner aceite no saco (R2)

| Campo | Valor |
|-------|-------|
| **ID** | A152 |
| **Nome** | Banner saco só em `status=accepted` |
| **Pré-condições** | Reserva accepted (não só pending) |
| **Passos** | 1. Aceitar reserva 2. Comprador abre saco |
| **Resultado esperado** | Banner + chip «Aceite · pronto a pagar»; **sem** banner em pending puro |
| **Componentes afectados** | `live_bag_sheet.dart`, patch v3 gate |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | accepted reservation |
| **Validar BD** | `status=accepted` |
| **Validar UI** | Banner + chip exactos |
| **Risco de regressão** | Alto — R6 banner prematuro |
| **Dependências** | A081; A191 |

---

## A153 — Botão Pagar visível (R3/A1)

| Campo | Valor |
|-------|-------|
| **ID** | A153 |
| **Nome** | CTA Pagar no saco e player quando payable |
| **Pré-condições** | Reserva `pending` ou `accepted`; preço > 0 se gate activo |
| **Passos** | 1. Ver saco 2. Ver card player 3. Confirmar CTA |
| **Resultado esperado** | **Pagar** visível em ambos quando `buyerCanPayBagReservation`; desactivado se price 0 |
| **Componentes afectados** | `buyerCanPayBagReservation`, player + bag CTAs |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | payable reservation |
| **Validar BD** | status pending/accepted; price > 0 |
| **Validar UI** | Botão Pagar teal visível |
| **Risco de regressão** | Crítico — A1 histórico (sumiu) |
| **Dependências** | A152; A202; A227 |

---

## A154 — Stepper qty saco persiste (R4)

| Campo | Valor |
|-------|-------|
| **ID** | A154 |
| **Nome** | Stepper +/- qty persiste ao reabrir saco |
| **Pré-condições** | 2 linhas ou qty 2 no mesmo artigo |
| **Passos** | 1. Abrir saco 2. +/- qty 3. Fechar e reabrir saco |
| **Resultado esperado** | Qty mantém valor editado; BD `requested_qty` sync |
| **Componentes afectados** | `live_bag_sheet.dart` stepper |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | multi-qty reservation |
| **Validar BD** | `requested_qty` após edit |
| **Validar UI** | Stepper valor persistente |
| **Risco de regressão** | Alto — R4/R31 |
| **Dependências** | A149; A203 |

---

## A155 — Chips posição #1#2#3 (A2)

| Campo | Valor |
|-------|-------|
| **ID** | A155 |
| **Nome** | Chips por unidade — cores verde/âmbar |
| **Pré-condições** | Multi-unidade mesmo artigo (qty≥2) ou multi-buyer |
| **Passos** | 1. Criar 2+ reservas/unidades 2. Abrir saco 3. Ver chips |
| **Resultado esperado** | Chips #1 #2 #3 por unidade; verde se unidade ≤ stock bruto; âmbar Espera |
| **Componentes afectados** | bag ranking v6, `isWaitlistUnit` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | multi-unit setup |
| **Validar BD** | `queue_position` por unidade |
| **Validar UI** | Cores correctas; todas posições visíveis |
| **Risco de regressão** | Crítico — A2 FAIL v5/v6 |
| **Dependências** | A149; A150; A192 |

---

## A156 — Viewer count ping

| Campo | Valor |
|-------|-------|
| **ID** | A156 |
| **Nome** | Contador espectadores incrementa ao entrar |
| **Pré-condições** | Live activa |
| **Passos** | 1. Entrar player 2. Observar contador 3. (Opcional) 2º viewer |
| **Resultado esperado** | Contador incrementa via `batata_live_viewer_ping`; seller vê tally |
| **Componentes afectados** | `live_room_service.dart`, viewer ping RPC |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id |
| **Validar BD** | viewer count / ping timestamp |
| **Validar UI** | Número espectadores >0 |
| **Risco de regressão** | Baixo |
| **Dependências** | A145 |

---

## A157 — Follow/unfollow seller no player

| Campo | Valor |
|-------|-------|
| **ID** | A157 |
| **Nome** | Seguir vendedor no player |
| **Pré-condições** | Buyer não segue seller; live activa |
| **Passos** | 1. Player → Seguir 2. Ver estado 3. (Opcional) unfollow |
| **Resultado esperado** | Follow gravado; rifa +1 entrada se rifa activa (regra produto) |
| **Componentes afectados** | player follow chip, `FleaberPrimaryButton.compact`, raffle hook |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | buyer, seller_id |
| **Validar BD** | follows row; optional raffle +1 |
| **Validar UI** | Chip «A seguir» |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A212 |

---

## A158 — Comprar já directo (Z6) sem aceite

| Campo | Valor |
|-------|-------|
| **ID** | A158 |
| **Nome** | Checkout directo sem passar aceite vendedor |
| **Pré-condições** | Preço definido > 0; stock disponível; feature «Comprar já» activa |
| **Passos** | 1. Carrossel → Comprar já 2. Ver checkout |
| **Resultado esperado** | Abre `LiveInStreamCheckout` / sheet; **sem** estado accepted prévio |
| **Componentes afectados** | `LiveInStreamCheckout`, carrossel CTA Z6 |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | item price > 0 |
| **Validar BD** | order/reserva conforme design Z6 |
| **Validar UI** | Checkout abre in-player |
| **Risco de regressão** | Médio — bypass fila |
| **Dependências** | A148 negativo; A205 |

---

## A159 — Carrossel highlight item activo

| Campo | Valor |
|-------|-------|
| **ID** | A159 |
| **Nome** | Highlight carrossel segue vitrine seller |
| **Pré-condições** | Seller mudou vitrine (A130) |
| **Passos** | 1. Seller activa artigo D 2. Buyer poll ~2s 3. Ver highlight |
| **Resultado esperado** | Highlight/scroll automático para item `is_active=true` |
| **Componentes afectados** | catalog poll buyer, `live_item_show_events` subscription |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 items; seller + buyer |
| **Validar BD** | `is_active` match |
| **Validar UI** | Card destacado = vitrine |
| **Risco de regressão** | Médio |
| **Dependências** | A130; A178 |

---

## A160 — Cancelar reserva comprador (#4)

| Campo | Valor |
|-------|-------|
| **ID** | A160 |
| **Nome** | Comprador remove reserva do saco (pré-pagamento) |
| **Pré-condições** | Reserva `pending` ou `accepted`; sem order `pago` |
| **Passos** | 1. Saco → Remover/Cancelar 2. Confirmar 3. Ver vendedor fila |
| **Resultado esperado** | `status=rejected`, notes `bag_removed`; stock libertado; vendedor **sem** Aceitar (A085) |
| **Componentes afectados** | `batata_live_bag_remove_request`, `live_bag_sheet.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Integration |
| **Dados necessários** | reservation id, buyer JWT |
| **Validar BD** | rejected + bag_removed |
| **Validar UI** | Secção cancelados; sem Pagar |
| **Risco de regressão** | Médio — doc live-ops #4 |
| **Dependências** | A148; A194; A230 |

---

## A161 — Chat público enviar (live)

| Campo | Valor |
|-------|-------|
| **ID** | A161 |
| **Nome** | Comprador envia mensagem chat público |
| **Pré-condições** | Live activa (`_liveIsActive`); buyer autenticado |
| **Passos** | 1. Player → input chat 2. Enviar mensagem 3. Ver painel |
| **Resultado esperado** | Msg aparece no chat público; `profiles.full_name` como nome |
| **Componentes afectados** | `live_room_service.dart`, chat panel buyer |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id, buyer JWT |
| **Validar BD** | `live_messages` row tipo chat |
| **Validar UI** | Bolha com texto enviado |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A162 (negativo) |

---

## A162 — Chat bloqueado em gravado

| Campo | Valor |
|-------|-------|
| **ID** | A162 |
| **Nome** | Input chat desactivado em VOD/replay |
| **Pré-condições** | Live `status=ended`; `_isVodReplay=true` |
| **Passos** | 1. Entrar gravado (A146) 2. Tentar escrever chat |
| **Resultado esperado** | Input disabled ou oculto; replay chat histórico visível |
| **Componentes afectados** | `_isVodReplay` guards, `fleaber_live_player_widget.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ended live + playback |
| **Validar BD** | — |
| **Validar UI** | Sem input activo; badge GRAVADO |
| **Risco de regressão** | Alto — spam em replay |
| **Dependências** | A146; A310+ |

---

## A163 — Private chat buyer→seller

| Campo | Valor |
|-------|-------|
| **ID** | A163 |
| **Nome** | Mensagem privada comprador para vendedor |
| **Pré-condições** | Live activa; feature DM activa |
| **Passos** | 1. Player → DM/privado 2. Enviar msg 3. Seller vê tab Chat privado |
| **Resultado esperado** | Thread privada; seller recebe; não mistura com chat público |
| **Componentes afectados** | private chat panel, studio Chat tab |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 users |
| **Validar BD** | private message row |
| **Validar UI** | Thread separada |
| **Risco de regressão** | Médio |
| **Dependências** | A145; A280+ |

---

## A164 — Share live copy link

| Campo | Valor |
|-------|-------|
| **ID** | A164 |
| **Nome** | Partilhar link da live (copy) |
| **Pré-condições** | Live activa ou gravado |
| **Passos** | 1. Player → Partilhar 2. Copiar link 3. Abrir noutro device/browser |
| **Resultado esperado** | Link válido abre player correcto; deep link params preservados |
| **Componentes afectados** | share sheet, deep links |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | live_id |
| **Validar BD** | — |
| **Validar UI** | Clipboard/snack «Link copiado» |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A147 |

---

## A165 — Spotlight item (se activo)

| Campo | Valor |
|-------|-------|
| **ID** | A165 |
| **Nome** | Overlay spotlight no artigo activo |
| **Pré-condições** | Feature spotlight activa; item em vitrine |
| **Passos** | 1. Seller activa spotlight (se UI) 2. Buyer vê overlay |
| **Resultado esperado** | Destaque visual extra no item activo; não quebra carrossel |
| **Componentes afectados** | spotlight overlay (se implementado) |
| **Prioridade** | P3 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa |
| **Validar BD** | — |
| **Validar UI** | Overlay visível |
| **Risco de regressão** | Baixo |
| **Dependências** | A130; A159 |

---

## A166 — Portes breakdown visível pré-checkout

| Campo | Valor |
|-------|-------|
| **ID** | A166 |
| **Nome** | Portes visíveis antes de abrir Stripe |
| **Pré-condições** | Reserva payable; buyer abre checkout sheet |
| **Passos** | 1. Pagar → sheet 2. Ver breakdown **antes** confirmar |
| **Resultado esperado** | Linhas transportadora 3,50 € / mão 0 € visíveis; total parcial |
| **Componentes afectados** | `live_bag_checkout_sheet.dart`, `live_in_stream_checkout.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | payable reservation |
| **Validar BD** | — (pré-order) |
| **Validar UI** | «Envio Transportadora (€3.50)» presente |
| **Risco de regressão** | Alto — R5 KPI; BATATA portes |
| **Dependências** | A153; A199 |

---

## A167 — Seguro Fleaber no total

| Campo | Valor |
|-------|-------|
| **ID** | A167 |
| **Nome** | Linha seguro no preview checkout comprador |
| **Pré-condições** | Checkout com seguro activo (pagamento na app) |
| **Passos** | 1. Abrir checkout 2. Ver linha seguro 3. Calcular 0,65 + 5% |
| **Resultado esperado** | Seguro visível no total preview; fórmula BATATA |
| **Componentes afectados** | `fee_calculator.dart`, checkout preview buyer |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Unit + Manual |
| **Dados necessários** | artigo 10€ + portes 3.5 |
| **Validar BD** | — (pré-pagamento) |
| **Validar UI** | Linha seguro + total |
| **Risco de regressão** | Médio |
| **Dependências** | A166; A201 |

---

## A168 — App resume Stripe context

| Campo | Valor |
|-------|-------|
| **ID** | A168 |
| **Nome** | Retomar app após Stripe — reconcile pending |
| **Pré-condições** | Checkout Stripe iniciado; app background |
| **Passos** | 1. Pagar → browser Stripe 2. Home app 3. Resume app |
| **Resultado esperado** | `tryResumeOnAppResumed` reconcilia; snack sucesso ou estado saco correcto |
| **Componentes afectados** | `fleaber_stripe_checkout_context.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | Stripe test session |
| **Validar BD** | order pago se success |
| **Validar UI** | Saco actualizado pós-resume |
| **Risco de regressão** | Crítico — dinheiro órfão |
| **Dependências** | A205; A206; A229 |

---

## A169 — Mux HLS reduced latency live

| Campo | Valor |
|-------|-------|
| **ID** | A169 |
| **Nome** | Playback HLS live com latência reduzida |
| **Pré-condições** | Live activa com Mux stream |
| **Passos** | 1. Entrar player 2. Observar latência vs studio 3. Verificar HLS URL |
| **Resultado esperado** | Stream HLS playable; latência aceitável (<10–15s staging); sem stall prolongado |
| **Componentes afectados** | Mux player, HLS config |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live activa, rede estável |
| **Validar BD** | mux playback url |
| **Validar UI** | Vídeo fluido; badge LIVE |
| **Risco de regressão** | Médio — live-streaming.mdc |
| **Dependências** | A054; A145 |

---

## A170 — Player sem liveId fallback PDP

| Campo | Valor |
|-------|-------|
| **ID** | A170 |
| **Nome** | Rota player inválida — fallback seguro |
| **Pré-condições** | Deep link ou rota sem `liveId` válido |
| **Passos** | 1. Abrir rota player malformed 2. Observar comportamento |
| **Resultado esperado** | Fallback PDP ou erro amigável; **sem** crash |
| **Componentes afectados** | `nav.dart`, player route guards |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | URI inválida |
| **Validar BD** | — |
| **Validar UI** | Snack/redirect; no red screen |
| **Risco de regressão** | Médio |
| **Dependências** | — |

---

## A171 — originLiveId no PDP

| Campo | Valor |
|-------|-------|
| **ID** | A171 |
| **Nome** | PDP marketplace preserva contexto live |
| **Pré-condições** | Navegação player → PDP (se permitido) com `originLiveId` |
| **Passos** | 1. Abrir artigo com param origin 2. Ver PDP |
| **Resultado esperado** | `originLiveId` passado; CTA voltar à live se regra activa |
| **Componentes afectados** | PDP params, navigation extras |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | product + live_id |
| **Validar BD** | — |
| **Validar UI** | Banner/link live origem |
| **Risco de regressão** | Baixo — BATATA no checkout in-player |
| **Dependências** | A145 |

---

## A172 — Carousel KPI Reservas inclui cross

| Campo | Valor |
|-------|-------|
| **ID** | A172 |
| **Nome** | KPI Reservas carrossel inclui cross-live/blocked |
| **Pré-condições** | Item com reservas noutro directo ou `blocked_qty` |
| **Passos** | 1. Seed cross reservation 2. Ver label Reservas no carrossel buyer |
| **Resultado esperado** | Contador inclui unidades cross conforme regra v6 |
| **Componentes afectados** | carrossel KPI, `cross_reserved_qty` |
| **Prioridade** | P0 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | cross-pool setup |
| **Validar BD** | RPC cross_reserved |
| **Validar UI** | Reservas label match seller A141 |
| **Risco de regressão** | Alto — A3/A6 patch v6 |
| **Dependências** | A141; A340+ |

---

## A173 — Badge indisponível vs waitlist

| Campo | Valor |
|-------|-------|
| **ID** | A173 |
| **Nome** | UI distingue indisponível de waitlist |
| **Pré-condições** | Stock cheio; reserva waitlist permitida |
| **Passos** | 1. Esgotar stock com aceite 2. Novo buyer reserva 3. Ver badges |
| **Resultado esperado** | **Sem** badge ESGOTADO bloqueante; CTA reservar/waitlist; chip Espera no saco |
| **Componentes afectados** | carrossel badges, `isSoldOut`, waitlist UX |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | stock 1 + aceite + 2º buyer |
| **Validar BD** | pending waitlist row |
| **Validar UI** | Reservar ainda activo; Espera no saco |
| **Risco de regressão** | Crítico — BATATA esgotado |
| **Dependências** | A133; A150; A181 |

---

## A174 — Gorjeta buyer flow (P15)

| Campo | Valor |
|-------|-------|
| **ID** | A174 |
| **Nome** | Enviar gorjeta na live |
| **Pré-condições** | Live activa; feature tip; buyer autenticado |
| **Passos** | 1. Player → Gorjeta 2. Escolher valor 3. Pagar Stripe/wallet |
| **Resultado esperado** | Tip registada; aparece painel seller; **sem** metadata saco |
| **Componentes afectados** | `live_tip_flow.dart`, tip edge |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | live_id, Stripe test |
| **Validar BD** | tip transaction row |
| **Validar UI** | CTA gorjeta + confirmação |
| **Risco de regressão** | Médio — clash A229 |
| **Dependências** | A145; A224 |

---

## A175 — Re-enter player announce purchases 30min

| Campo | Valor |
|-------|-------|
| **ID** | A175 |
| **Nome** | Reentrada player — anúncio compras recentes |
| **Pré-condições** | Compras converted na live últimos 30 min |
| **Passos** | 1. Sair player 2. Reentrar mesma live 3. Ver FOMO/banner |
| **Resultado esperado** | Banner ou msgs «comprou» recentes; dedupe A289 |
| **Componentes afectados** | purchase announce, FOMO hooks |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | converted recent |
| **Validar BD** | converted timestamps |
| **Validar UI** | Anúncio visível 1× |
| **Risco de regressão** | Baixo |
| **Dependências** | A206; A210 |

---

## A176 — Landscape portrait lock

| Campo | Valor |
|-------|-------|
| **ID** | A176 |
| **Nome** | Orientação ecrã player |
| **Pré-condições** | Player aberto |
| **Passos** | 1. Rodar device landscape 2. Voltar portrait |
| **Resultado esperado** | Layout adapta ou lock conforme BATATA; sem crash; controls acessíveis |
| **Componentes afectados** | player orientation, `live-streaming.mdc` |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | device físico |
| **Validar BD** | — |
| **Validar UI** | UI intacta ambas orientações |
| **Risco de regressão** | Médio — layout fixo |
| **Dependências** | A145 |

---

## A177 — Catalog cache SharedPreferences stale

| Campo | Valor |
|-------|-------|
| **ID** | A177 |
| **Nome** | Cache catálogo invalida após mutação seller |
| **Pré-condições** | Buyer entrou player; seller altera stock/preço |
| **Passos** | 1. Buyer vê carrossel 2. Seller +/- stock 3. Esperar poll/realtime |
| **Resultado esperado** | Carrossel actualiza; prefs cache não serve stale >TTL |
| **Componentes afectados** | catalog cache SharedPreferences, poll A139 |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 2 sessions |
| **Validar BD** | qty nova |
| **Validar UI** | Qtd label actualizada |
| **Risco de regressão** | Médio — R32 stale |
| **Dependências** | A144; A178; A139 |

---

## A178 — Realtime catalog update buyer

| Campo | Valor |
|-------|-------|
| **ID** | A178 |
| **Nome** | Supabase realtime actualiza carrossel |
| **Pré-condições** | Buyer no player; subscription activa |
| **Passos** | 1. Seller muda vitrine ou preço 2. Observar buyer <3s |
| **Resultado esperado** | Carrossel refresh via realtime/poll; highlight A159 sync |
| **Componentes afectados** | `fleaber_live_player_widget.dart` catalog channel |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id, 2 users |
| **Validar BD** | mutation applied |
| **Validar UI** | UI buyer match seller |
| **Risco de regressão** | Alto |
| **Dependências** | A130; A159 |

---

## A179 — Realtime bag update buyer

| Campo | Valor |
|-------|-------|
| **ID** | A179 |
| **Nome** | Saco actualiza realtime (aceite/reject) |
| **Pré-condições** | Buyer com saco aberto ou player activo |
| **Passos** | 1. Seller aceita/rejeita 2. Buyer vê update sem reload |
| **Resultado esperado** | Saco/card player actualiza <5s; card verde R1 |
| **Componentes afectados** | bag realtime stream, `_loadLiveBagCount` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Bot + Maestro |
| **Dados necessários** | pending → accepted |
| **Validar BD** | status change |
| **Validar UI** | Banner A152; card A151 |
| **Risco de regressão** | Crítico — R1 delay |
| **Dependências** | A151; A152; A081 |

---

## A180 — Accept realtime sem user_id no msg

| Campo | Valor |
|-------|-------|
| **ID** | A180 |
| **Nome** | Aceite realtime robusto — payload sem user_id |
| **Pré-condições** | Reserva pending; simular payload realtime incompleto |
| **Passos** | 1. Seller aceita 2. Buyer recebe evento 3. Ver card/banner |
| **Resultado esperado** | UI actualiza mesmo se msg realtime omitir `user_id`; fallback scan saco |
| **Componentes afectados** | player accept handler, realtime parser |
| **Prioridade** | P1 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | staging logs |
| **Validar BD** | accepted |
| **Validar UI** | Card verde aparece |
| **Risco de regressão** | Alto — R1 root cause histórico |
| **Dependências** | A151; A179 |

---

## A181 — Friendly error item_reserved_full vs waitlist

| Campo | Valor |
|-------|-------|
| **ID** | A181 |
| **Nome** | Erro amigável — fila vs bloqueio total |
| **Pré-condições** | Edge case stock/reserva |
| **Passos** | 1. Tentar acção que falha (reserva duplicada inválida vs waitlist OK) 2. Ler snack |
| **Resultado esperado** | Mensagem clara; waitlist **não** mostra «Erro: item_reserved_full» genérico |
| **Componentes afectados** | error mapping, reservation RPC errors |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | error scenarios |
| **Validar BD** | — |
| **Validar UI** | Copy PT amigável |
| **Risco de regressão** | Médio |
| **Dependências** | A173; A150 |

---

## A182 — Multi-ref carrossel scroll

| Campo | Valor |
|-------|-------|
| **ID** | A182 |
| **Nome** | Carrossel com muitos artigos — scroll e performance |
| **Pré-condições** | Live com ≥8 items |
| **Passos** | 1. Entrar player 2. Scroll carrossel 3. Reservar item no extremo |
| **Resultado esperado** | Scroll fluido; item extremo reservável; highlight A159 OK |
| **Componentes afectados** | carrossel ListView, imagens cache |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | live com catálogo grande |
| **Validar BD** | — |
| **Validar UI** | Todos items acessíveis |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A148 |

---

## A183 — isLive hint Home vs BD status

| Campo | Valor |
|-------|-------|
| **ID** | A183 |
| **Nome** | Feed Home coerente com BD `status`/`is_active` |
| **Pré-condições** | Lives em estados mix (live, ended, stale) |
| **Passos** | 1. Query BD 2. Comparar cards Home 3. Terminar live 4. Refresh feed |
| **Resultado esperado** | Só `status=live AND is_active=true` como LIVE; ended não LIVE |
| **Componentes afectados** | `home_live_feed_grid.dart` query filter |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | lives seed |
| **Validar BD** | status/is_active |
| **Validar UI** | Badge LIVE correcto |
| **Risco de regressão** | Alto — cards fantasma |
| **Dependências** | A058; A075; A145 |

---

## A184 — forceVod query param

| Campo | Valor |
|-------|-------|
| **ID** | A184 |
| **Nome** | Param `forceVod` força modo replay |
| **Pré-condições** | Live com playback; deep link com `forceVod=true` |
| **Passos** | 1. Abrir link forceVod 2. Ver player |
| **Resultado esperado** | Modo VOD mesmo se BD ainda live (debug/staging); guards chat A162 |
| **Componentes afectados** | player route params, `_isVodReplay` |
| **Prioridade** | P2 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | deep link forceVod |
| **Validar BD** | — |
| **Validar UI** | Comportamento VOD |
| **Risco de regressão** | Baixo — debug only |
| **Dependências** | A146; A162 |

---

## A185 — sellerId param player

| Campo | Valor |
|-------|-------|
| **ID** | A185 |
| **Nome** | Param `sellerId` na rota player |
| **Pré-condições** | Deep link com sellerId + liveId |
| **Passos** | 1. Abrir rota 2. Ver header follow/perfil |
| **Resultado esperado** | Seller correcto no header; follow target OK |
| **Componentes afectados** | player route params |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | sellerId, liveId |
| **Validar BD** | seller match live |
| **Validar UI** | Nome/avatar seller |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A157 |

---

## A186 — Comprador 2 devices mesma conta saco

| Campo | Valor |
|-------|-------|
| **ID** | A186 |
| **Nome** | Multi-device — saco sync mesma conta |
| **Pré-condições** | Mesmo buyer JWT em 2 devices |
| **Passos** | 1. Device A reserva 2. Device B abre saco 3. Device A cancela |
| **Resultado esperado** | Saco B actualiza; sem estado divergente permanente |
| **Componentes afectados** | bag fetch, realtime A179 |
| **Prioridade** | P2 |
| **Automatizável** | Não |
| **Tipo recomendado** | Manual |
| **Dados necessários** | 2 devices |
| **Validar BD** | single source truth |
| **Validar UI** | Saco coerente |
| **Risco de regressão** | Médio |
| **Dependências** | A148; A179; A160 |

---

## A187 — Anonymous ref visit depois login

| Campo | Valor |
|-------|-------|
| **ID** | A187 |
| **Nome** | Referral visit anónimo atribuído pós-login |
| **Pré-condições** | Guest abre link `?ref=` 2. Login |
| **Passos** | 1. Abrir link logged out 2. Login 3. Permanecer 60s |
| **Resultado esperado** | Visit atribuída ao user autenticado; qualify A214 |
| **Componentes afectados** | referral persistence, auth bridge |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | referral token |
| **Validar BD** | referral visit user_id preenchido |
| **Validar UI** | Player live correcta |
| **Risco de regressão** | Médio |
| **Dependências** | A147; A214 |

---

## A188 — Participar rifa sidebar (R1 rifa)

| Campo | Valor |
|-------|-------|
| **ID** | A188 |
| **Nome** | Join rifa via sidebar player |
| **Pré-condições** | Rifa activa; buyer autenticado; live activa |
| **Passos** | 1. Player → sidebar rifa 2. Tocar Participar |
| **Resultado esperado** | +1 entrada; UI confirma inscrição; sem duplicar tap |
| **Componentes afectados** | `live_raffle_buyer_card.dart`, sidebar raffle |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | live_id com raffle |
| **Validar BD** | `raffle_entries` +1 |
| **Validar UI** | Estado «inscrito» |
| **Risco de regressão** | Baixo |
| **Dependências** | A145; A212 |

---

## A189 — Participar rifa sheet +1 (R3)

| Campo | Valor |
|-------|-------|
| **ID** | A189 |
| **Nome** | Join rifa via sheet modal +1 entrada |
| **Pré-condições** | Rifa activa; buyer no player |
| **Passos** | 1. Abrir sheet rifa 2. Participar 3. Ver contador |
| **Resultado esperado** | +1 entrada base; contador actualizado; alinhado A212 |
| **Componentes afectados** | raffle sheet UI, join RPC |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | raffle_id, buyer |
| **Validar BD** | entries count +1 |
| **Validar UI** | Sheet confirma +1 |
| **Risco de regressão** | Baixo — R3 rifa |
| **Dependências** | A188; A212 |

---

## Apêndice A — Resumo A130–A189

| Bloco | IDs | Foco |
|-------|-----|------|
| Seller catálogo | A130–A144 | Vitrine, stock Total·Disp, sold/repor, ESGOTADO, quick edit, marketplace, KPI P14, sync qty |
| Buyer entrada + reserva | A145–A159 | Home/VOD, referral, reservar, waitlist, aceite UX, Pagar, chips, follow, comprar já, highlight |
| Buyer player alargado | A160–A189 | Cancel, chat, portes preview, Stripe resume, realtime, cross KPI, gorjeta, rifa, edge routes |

**Total fichas:** 60 (A130–A189).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| Stock Total vs Disp (A3) | A131, A139, A144, A172 |
| ESGOTADO vs waitlist BATATA | A133, A150, A173, A181 |
| Aceite UX comprador (R1–R4) | A151, A152, A153, A154, A155, A179, A180 |
| Reserva qty increment (R6) | A148, A149, A154 |
| Cross-pool / blocked_qty | A131, A139, A172, A340+ |
| Realtime seller→buyer | A178, A179, A159 |
| Preço live vs marketplace | A134, A138, A166, A167 |
| Rifa entrada comprador | A147, A157, A188, A189, A212 |

---

## Apêndice B — P0 desta faixa (28)

| ID | Nome curto |
|----|------------|
| A130 | Activar vitrine |
| A131 | Total·Disp A3 |
| A132 | Repor qty R32 |
| A133 | ESGOTADO pós-aceite |
| A138 | Marketplace toggle |
| A140 | P14.1 vendidos |
| A142 | P14.3 barra multi |
| A145 | Entrar live Home |
| A146 | Entrar gravado |
| A148 | Reservar 1ª vez |
| A149 | Increment qty R6 |
| A150 | Waitlist |
| A151 | Card verde R1 |
| A152 | Banner aceite R2 |
| A153 | Pagar R3/A1 |
| A154 | Stepper qty R4 |
| A155 | Chips #1#2#3 A2 |
| A160 | Cancelar reserva #4 |
| A162 | Chat off gravado |
| A166 | Portes pré-checkout |
| A167 | Seguro preview |
| A168 | App resume Stripe |
| A172 | KPI Reservas cross |
| A173 | Badge vs waitlist |
| A179 | Realtime bag |

---

## Apêndice C — Top 10 a automatizar primeiro

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A133 | Regra ESGOTADO BATATA — blocker UX | Bot |
| 2 | A149 | Increment qty R6 — duplicação rows | Bot |
| 3 | A150 | Waitlist + chips — A2 histórico | Bot |
| 4 | A173 | Waitlist vs esgotado — confusão comprador | Bot |
| 5 | A148 | createRequest base — toda fila | Bot + Maestro |
| 6 | A179 | Realtime bag — R1 delay | Bot + Maestro |
| 7 | A144 | quantity sync — R32 | Integration |
| 8 | A145 | Smoke entrada player | Maestro |
| 9 | A160 | bag_remove — stock + KPI vendedor | Integration |
| 10 | A178 | Realtime catálogo — vitrine/preço |

---

## Apêndice D — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | A167 |
| **Integration** | A132, A138, A144, A147, A160, A177, A183, A185, A187 |
| **Bot** | A133, A141, A148, A149, A150, A156, A161, A173, A178, A179 |
| **Maestro** | A145, A146, A152, A153, A162, A164, A166, A182, A184, A188, A189 |
| **Manual** | A130, A131, A134, A135, A136, A137, A139, A140, A142, A143, A151, A154, A155, A158, A159, A163, A165, A168, A169, A170, A171, A172, A174, A175, A176, A180, A181, A186 |
| **Híbrido** | A130 (Bot+Manual), A132 (Integration+Manual), A147 (Integration+Manual), A160 (Maestro+Integration), A167 (Unit+Manual), A179 (Bot+Maestro), A148 (Bot+Maestro) |

---

## Apêndice E — Riscos críticos (levantamento)

1. **A3 Total vs Disp (A131, A172):** catálogo mostra bruto; barra/comprador mostram disponível — puzzle cross-live desalinhado (FAIL v5/v6).
2. **ESGOTADO prematuro (A133, A173):** badge só pós-aceite — regressão bloqueia waitlist BATATA.
3. **R1 card verde (A151, A179, A180):** delay 30s ou dialog duplicado — aceite UX quebrada.
4. **A1 Pagar sumiu (A153):** `buyerCanPayBagReservation` — CTA ausente saco/player.
5. **A2 chips posição (A155, A150):** ranking por unidade verde/âmbar — saco confuso multi-qty.
6. **R6 increment (A149):** 2ª reserva duplica row ou banner aceite em pending.
7. **R32 repor stock (A132, A144):** catálogo 8 vs editor 10 — carrossel stale.
8. **Marketplace toggle (A138):** `list_on_marketplace` errado quebra TYPE A checkout (Z52).
9. **Realtime bag (A179):** comprador não vê aceite — perde janela pagamento.
10. **Stripe resume (A168):** app background perde reconcile — order órfã (overlap A206).

---

*Fim A130–A189.*
