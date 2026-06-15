# Fleaber — Mapa de fluxos e matriz de testes (ecossistema Directo)

**Versão:** 1.1 · **Data:** 2026-06-14  
**Estado:** Matriz **429/429 expandida** — runner especificado (secção 9), **sem implementação**.  
**Numeração:** `A001`–`A220` — **única e permanente**. Novos testes usam `A221+`.

---

## Índice

1. [Mapa completo de fluxos](#1-mapa-completo-de-fluxos)
2. [Registo de numeração e legado](#2-registo-de-numeração-e-legado)
3. [Arquitectura de testes (5 camadas)](#3-arquitectura-de-testes-5-camadas)
4. [Bot + Maestro — orquestração](#4-bot--maestro--orquestração)
5. [Matriz de testes A001–A429](#5-matriz-de-testes)
   - [Ficheiros expandidos (9)](#ficheiros-expandidos)
6. [Cobertura estimada por área](#6-cobertura-estimada-por-área)
7. [Automatizável vs nunca automatizável](#7-automatizável-vs-nunca-automatizável)
8. [Estratégia de regressão máxima](#8-estratégia-de-regressão-máxima)
9. [Arquitectura do Fleaber Regression Runner](#9-arquitectura-do-fleaber-regression-runner)

---

## 1. Mapa completo de fluxos

### 1.1 Visão sistema

```mermaid
flowchart TB
  subgraph entry [Entrada]
    CS[FleaberCreateSheet]
    CS --> Prep[/prepararDirecto]
    Prep --> Create[/criarDirecto]
    Create --> Live[status=live + publish]
  end

  subgraph seller [Vendedor em directo]
    Live --> Studio[LiveVendorStudioPanel]
    Studio --> Op[Operação: filas]
    Studio --> Cat[Catálogo: vitrine/stock]
    Studio --> ChS[Chat público/privado]
    Studio --> Raf[Rifa vendedor]
    Op --> Acc[Aceitar/Rejeitar/Skip]
    Cat --> Mkt[Marketplace opt-in]
  end

  subgraph buyer [Comprador]
    Player[FleaberLivePlayer]
    Player --> Res[Reservar]
    Player --> Bag[Saco da live]
    Bag --> Chk[Checkout Stripe]
    Player --> RafB[Rifa comprador]
    Player --> ChB[Chat/FOMO]
    Chk --> Ord[orders + converted]
  end

  subgraph end [Fim e persistência]
    Live --> End[Terminar/Sair/Orphan]
    End --> Grav[status=ended + VOD]
    Grav --> Replay[Replay chat/catálogo]
    Grav --> Bag2[Saco/commerce em VOD]
  end

  subgraph cross [Cross-session — logical_item_id / pool]
    Pool[batata_live_items_same_stock_pool]
    Lineage[ref_histories + logical_item_id]
    Prep --> Lineage
    Lineage --> Pool
    Grav --> Pool
    Live --> Pool
    Mkt --> Pool
  end

  Studio -.->|realtime/RPC| Player
  Acc -.->|accepted| Bag
  Ord -.->|mensagens| ChB
```

### 1.2 Vendedor — árvore de decisão

| Nó | Rotas / ficheiros | Transições | Ramos |
|----|-------------------|------------|-------|
| Criar | `fleaber_create_sheet.dart` | Home → Preparar | Novo Anúncio (fora) · **Novo Directo** |
| Preparar | `preparar_directo_page_widget.dart` | Draft `batata_ensure_draft_live` | Catálogo vazio · refs · schemes · detalhes · long-press linhagem |
| Linhagem | `live_ref_lineage_prep_gate.dart` | Preview RPC | Continuar linhagem · Novo artigo · Cancelar |
| Criar directo | `criar_directo_page_widget.dart` | Preview → Iniciar | LiveKit (default) · Haishin RTMP · sem título · sem câmara |
| Aviso reservas | `live_start_reservations_warning_sheet.dart` | Pré go-live | Confirmar · Recusar → pop |
| Studio | `live_vendor_studio_panel.dart` | 3 tabs + sub-painéis | Operação · Chat · Catálogo |
| Operação | `live_reservation_queue_service.dart` | RPC queue | No saco · Pendentes · Aceites · Externos · Sem pagamento · Histórico · Cancelados comprador |
| Acções fila | `batata_process_live_reservation_request` | accept/reject/skip/expire | Normal · overbook confirm · buyer-cancelled (sem acção) |
| Catálogo | `live_catalog_stock_service.dart` | vitrine + stock | Activar · +/- qty · vendido · quick edit · marketplace toggle |
| Pagamentos | reconcile + realtime orders | KPI + lista | Stale reconcile · portes no total |
| Rifa | `live_raffle_service.dart` | create/close/draw/cancel | Top público toggle |
| Terminar | `_teardownLiveSession` | ended imediato | Terminar → Arena gravado · Sair → Home · Back/PopScope |
| VOD | `complete-mux-live` | async playback_id | Sucesso · timeout · falha Mux |
| Pós-live | `live_sales_sessions_page_widget.dart` | `/operacoesLive` | Sessão · detalhe · KPIs |
| Helper | `helper_live_ops_page_widget.dart` | HLS + panel | Permissões staff · sem terminar live |
| Harness | `maestro_seller_studio_page_widget.dart` | debug only | Sem câmara |

### 1.3 Comprador — árvore de decisão

| Nó | Ficheiros | Ramos |
|----|-----------|-------|
| Entrada | `home_live_feed_grid.dart`, `profile_lives_tab.dart`, deep link | LIVE · GRAVADO · `?ref=` rifa |
| Player | `fleaber_live_player_widget.dart` | `_liveIsActive` vs `_isVodReplay` |
| Carrossel | `live_catalog_stock_service.dart` | Reservar · Comprar já · preço pendente · esgotado badge |
| Reserva | `createRequest` | 1ª · 2ª+ incrementa qty · waitlist · chat `�x:�️` |
| Saco | `live_bag_sheet.dart` | In bag · waitlist · purchased · cancelled · #1#2#3 · Espera |
| Aceite UX | player + bag | Card verde player · banner saco · chip aceite |
| Checkout | `live_bag_checkout_sheet.dart`, `live_in_stream_checkout.dart` | 1 ref · multi-ref · qty>stock · portes · seguro |
| Stripe | `fleaber_stripe_checkout_context.dart` | resume app · reconcile · purchase broadcast |
| Rifa | `live_raffle_buyer_card.dart` | Participar · seguir · partilhar · referral · leaderboard |
| Chat | `live_room_service.dart` + humanizer | Público · privado · sistema filtrado |
| Gorjeta | `live_tip_flow.dart` | Stripe/wallet |
| Gravado | guards `_isVodReplay` | Chat off · saco/pay on · replay sync |

### 1.4 Estados — reservas, artigos, lives, encomendas

**Reserva (`live_reservation_requests.status`):**  
`pending` → `accepted` | `rejected` | `skipped` | `expired` → `converted` (pós-pagamento)

**Artigo live (`live_items`):** `available` · `reserved_full` (pós-aceite esgotado) · `sold` · vitrine `is_active`

**Live (`lives.status`):** draft implícito → `live` + `is_active` → `ended` · orphan cleanup

**Encomenda (`orders.status`):** `reserva_pendente` → `pago` · disputa pós-venda (`order_disputes`)

**Mensagens (`live_messages`):** `chat` · `system` · visibilidade via `LiveSystemChatHumanizer` (público vs backoffice)

### 1.5 Cross-pool e linhagem

| Conceito | RPC/SQL | Efeito cross-session |
|----------|---------|----------------------|
| `logical_item_id` | `live_logical_item_id_batata.sql` | Irmãos de linhagem partilham stock pool |
| `batata_live_items_same_stock_pool` | `live_items_inventory_batata.sql` | Z82: vendas gravado+live no mesmo pool |
| `blocked_qty` | stock RPC | Unidades bloqueadas noutro directo |
| `cross_reserved_qty` | stock RPC | Reservas noutras lives mesmo produto |
| Open reservations warning | `batata_live_start_open_reservations_check` | Origem: Direto · Gravado · Marketplace |

---

## 2. Registo de numeração e legado

### 2.1 Faixas permanentes

| Faixa | Domínio |
|-------|---------|
| **A001–A049** | Preparação directo + linhagem refs |
| **A050–A079** | Criação, publish, teardown, gravado origem |
| **A080–A129** | Vendedor — Operação (filas, aceites, pagamentos) |
| **A130–A159** | Vendedor — Catálogo, stock, marketplace toggle |
| **A160–A189** | Comprador — Player, reservas, entrada |
| **A190–A219** | Saco, checkout, portes, qty |
| **A220–A249** | Pagamentos, encomendas, gorjetas, disputas |
| **A250–A279** | Rifa (vendedor + comprador + social) |
| **A280–A309** | Chat, mensagens automáticas, FOMO |
| **A310–A339** | Gravado, replay, commerce em VOD |
| **A340–A369** | Marketplace TYPE A + cross-pool stock (Z82) |
| **A370–A389** | Helpers / equipa / permissões |
| **A390–A419** | Erros, recuperação, multi-device, multi-comprador |
| **A420–A439** | Sincronização BD/UI, arquitectura, cleanup |

### 2.2 Mapeamento legado → A (referência)

| Legado | → A |
|--------|-----|
| L1–L18 (linhagem) | A001–A018, A340–A345 |
| P1–P15 (preço pendente) | A046–A048, A163, A220–A228 |
| R1–R32 (comprador) | A167, A190–A219, A130–A132 |
| T1–T2 (qty checkout) | A206–A207 |
| Z82 (cross-pool) | A340–A348 |
| Manual #3–#8 | A131, A190, A220, A221 |

**Regra:** novos testes **não reutilizam** IDs legados L/P/R/T/Z em código novo; usar sempre `A###`.

---

## 3. Arquitectura de testes (5 camadas)

```
                    —R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
                    — 5. Manual Validation —  Exploratório, vídeo, 2 telemóveis,
                    —    (humano)          —  Stripe real feel, layout BATATA
                    ——�—�—�—�—�—�—�—�—�—���—�—�—�—�—�—�—�—�—�—�—�
                               —
                    —R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
                    — 4. Maestro (UI smoke)—  Login, taps, deep links, asserts texto
                    ——�—�—�—�—�—�—�—�—�—���—�—�—�—�—�—�—�—�—�—�—�
                               — bots preparam BD + msgs
                    —R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
                    — 3. Bot Simulator     —  N viewers, reservas, rifa RPC,
                    —    (API stress)      —  mensagens, cross-pool seed
                    ——�—�—�—�—�—�—�—�—�—���—�—�—�—�—�—�—�—�—�—�—�
                               —
                    —R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
                    — 2. Integration       —  staging RPC/edge/BD scripts
                    —    (tool/*.dart)     —  live_ops_staging_check, logical_item_id
                    ——�—�—�—�—�—�—�—�—�—���—�—�—�—�—�—�—�—�—�—�—�
                               —
                    —R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
                    — 1. Unit Tests        —  Humanizer, fees, parsers, gates
                    —    (flutter test)    —  sem rede
                    ——�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
```

| Camada | Ferramenta | Quando corre | SLA flake |
|--------|------------|--------------|-----------|
| Unit | `flutter test` | Cada PR | 0% |
| Integration | `dart run tool/*.dart` | PR live + pré-APK | <2% |
| Bot | `dart run tool/fleaber_bot_simulator.dart` | Nightly / pré-release | <5% |
| Maestro | `.maestro/flows/` | Pós-bot seed / smoke semanal | <15% |
| Manual | Checklist A### | Pré-release, pós-deploy SQL | N/A |

---

## 4. Bot + Maestro — orquestração

### 4.1 Padrões híbridos

| ID cenário | Bot faz | Maestro faz | Valida |
|------------|---------|-------------|--------|
| **H01** | Seed live `live` + 3 items + 5 reservas pending | Seller login → Operação → Aceitar | UI fila + BD accepted |
| **H02** | 10 bots reservam mesmo item | Seller vê contador + urgent card ao Pagar | KPI reservas |
| **H03** | Bot define preço (price_pending) | Buyer Pagar → sheet (sem Stripe) | Preço fresco |
| **H04** | Bot join rifa + follow | Buyer abre sheet Participar | Entrada BD |
| **H05** | Bot insere msgs sistema (tipos) | Buyer player chat visível | Copy humanizado |
| **H06** | Cross-pool: order pago gravado | Buyer novo directo stock badge | Z82 RPC+UI |
| **H07** | Cleanup desactivado test live | Seller harness accept | Sem fullSweep kill |
| **H08** | N bots chat flood | Seller chat tab scroll | Sem crash 60s |

### 4.2 Contrato bot → Maestro

1. Bot escreve `.maestro/.env` (`MAESTRO_LIVE_ID`, flags, `MAESTRO_SKIP_CLEANUP=1`).
2. Bot marca live `is_test=true` ou título `MAESTRO_*` (quando existir coluna/convención).
3. Maestro **nunca** faz `clearState` no seller se buyer ainda precisa do live.
4. Ordem no **runner** (secção 9): `maestro_prepare` OU `bot seed` → `flutter test` → `bot scenario` → `maestro flow` → verify — **nunca** scripts soltos em CI.

### 4.3 O que bots **não** substituem

Stripe WebView, Mux vídeo, seek replay HLS, sheet linhagem UX, fotos checkout, 3DS.

---

## 5. Matriz de testes

**Formato de cada ficha expandida:** ID · Nome · Pré-condições · Passos · Resultado esperado · Componentes · Prioridade · Automatizável · Tipo · Dados · Validar BD · Validar UI · Risco de regressão · Dependências

### Ficheiros expandidos

| Faixa | Ficheiro | Fichas |
|-------|----------|--------|
| A001–A049 | [`live-ecosystem-test-matrix-A001-A049.md`](./live-ecosystem-test-matrix-A001-A049.md) | 49 |
| A050–A079 | [`live-ecosystem-test-matrix-A050-A079.md`](./live-ecosystem-test-matrix-A050-A079.md) | 30 |
| A080–A129 | [`live-ecosystem-test-matrix-A080-A129.md`](./live-ecosystem-test-matrix-A080-A129.md) | 50 |
| A130–A189 | [`live-ecosystem-test-matrix-A130-A189.md`](./live-ecosystem-test-matrix-A130-A189.md) | 60 |
| A190–A230 | [`live-ecosystem-test-matrix-A190-A230.md`](./live-ecosystem-test-matrix-A190-A230.md) | 41 |
| A231–A279 | [`live-ecosystem-test-matrix-A231-A279.md`](./live-ecosystem-test-matrix-A231-A279.md) | 49 |
| A280–A349 | [`live-ecosystem-test-matrix-A280-A349.md`](./live-ecosystem-test-matrix-A280-A349.md) | 70 |
| A350–A369 | [`live-ecosystem-test-matrix-A350-A369.md`](./live-ecosystem-test-matrix-A350-A369.md) | 20 |
| A370–A429 | [`live-ecosystem-test-matrix-A370-A429.md`](./live-ecosystem-test-matrix-A370-A429.md) | 60 |
| **Total expandido** | | **429** |

**Matriz completa:** todos os A001–A429 têm ficha expandida em 9 ficheiros.

---

### A001–A049 — Preparação e linhagem (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A001-A049.md`](./live-ecosystem-test-matrix-A001-A049.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A001–A010 | Entrada prep, refs, linhagem gate, draft | 10 |
| A011–A030 | Draft/sync, schemes, marketplace TYPE A, L-series | 20 |
| A031–A049 | Prep UX, Z52, P1–P4 preço pendente, Query C | 19 |

**Índice compacto (legado):** prep + linhagem L1–L18 · P1–P4 · Z52 — ver ficheiro expandido.

---

### A050–A079 — Criação, publish, teardown (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A050-A079.md`](./live-ecosystem-test-matrix-A050-A079.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A050–A057 | Criar directo, Mux, aviso reservas, validações | 8 |
| A058–A060 | Teardown, VOD origem (`complete-mux-live`) | 3 |
| A061–A071 | Orphan cleanup, fullSweep, harness Maestro | 11 |
| A072–A079 | Permissões, sync catálogo, multi-device, legacy | 8 |

**Índice compacto (legado):**

| ID | Nome | P |
|----|------|---|
| A050–A054 | Entrada criar + Mux + go-live | P0–P1 |
| A055–A057 | Aviso reservas + BD mark live | P0–P1 |
| A058–A060 | Terminar/Sair + VOD | P0 |
| A061–A069 | Cleanup orphan + egress + prefs | P0–P2 |
| A070–A079 | Helper, harness, feed, multi-device | P1–P3 |

---

### A080–A129 — Vendedor Operação (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A080-A129.md`](./live-ecosystem-test-matrix-A080-A129.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A080–A088 | Filas, aceites, KPI, reconcile | 9 |
| A089–A116 | Secções operações, chat, pagamentos | 28 |
| A117–A129 | Rifa seller, FIFO, qty_confirm, activity | 13 |

---

### A130–A189 — Catálogo seller + Comprador player (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A130-A189.md`](./live-ecosystem-test-matrix-A130-A189.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A130–A144 | Catálogo, stock, marketplace, KPIs | 15 |
| A145–A159 | Player entrada, reservas, saco UX | 15 |
| A160–A189 | Chat, checkout preview, realtime, rifa | 30 |

---

### A190–A230 — Saco, checkout, pagamentos, rifa (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A190-A230.md`](./live-ecosystem-test-matrix-A190-A230.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A190–A194 | Saco UI (in-bag, waitlist, comprado, cancelado) | 5 |
| A195–A204 | Checkout sheet, qty, portes, seguro, price gate, T1/R31 | 10 |
| A205–A210 | Stripe, reconcile, bag settle, broadcast compra | 6 |
| A211–A218 | Rifa pós-checkout + join/share/leaderboard/draw | 8 |
| A219–A224 | Wallet, comissão, disputa, devolução, encomendas, tip | 6 |
| A225–A230 | Shadow, TYPE A, P5/P10, stripe context, bag remove | 6 |

**Índice compacto (legado):**

| ID | Nome | P |
|----|------|---|
| A190–A194 | Saco secções | P0–P1 |
| A195–A204 | Checkout + taxas + gates | P0 |
| A205–A210 | Stripe + reconcile + chat compra | P0 |
| A211–A218 | Rifa | P1–P2 |
| A219–A230 | Pós-venda + catálogo checkout | P0–P2 |

---

### A280–A349 — Mensagens, gravado, marketplace, cross-pool (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A280-A349.md`](./live-ecosystem-test-matrix-A280-A349.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A280–A294 | Mensagens automáticas + FOMO + humanizer | 15 |
| A295–A303 | Gravado core (replay, commerce, RLS) | 9 |
| A304–A309 | Mensagens extendidas (rifa, aceite, ERP) | 6 *(novos)* |
| A310–A339 | Gravado extendido (seek, VOD, transições) | 30 *(novos)* |
| A340–A349 | Cross-pool Z82 + marketplace | 10 |

**Total A280–A349:** 70 testes expandidos linha a linha.

---

### A231–A279 — Pagamentos extendidos + rifa social (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A231-A279.md`](./live-ecosystem-test-matrix-A231-A279.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A231–A249 | Sessões pós-live, refunds, disputas, wallet, gorjetas P15, stale #8 | 19 |
| A250–A279 | Rifa social H04, share/referral, draw, VOD, Maestro smoke | 30 |

**Nota:** A219–A230 em [`A190–A230`](./live-ecosystem-test-matrix-A190-A230.md).

---

### A350–A369 — Marketplace bridge (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A350-A369.md`](./live-ecosystem-test-matrix-A350-A369.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A350–A369 | PDP↔live TYPE A, feed toggle, Z82 sync, preços, badges pool | 20 |

**Nota:** A340–A349 (pool core) em [`A280–A349`](./live-ecosystem-test-matrix-A280-A349.md).

---

### A370–A429 — Helpers, erros, sync (EXPANDIDO)

**Fichas completas:** [`live-ecosystem-test-matrix-A370-A429.md`](./live-ecosystem-test-matrix-A370-A429.md)

| Faixa | Conteúdo | Fichas |
|-------|----------|--------|
| A370–A389 | Helpers, equipa, permissões | 20 |
| A390–A419 | Erros, multi-device, recuperação | 30 |
| A420–A429 | Sync, logs, segurança, R30 | 10 |

---

## 6. Cobertura estimada por área

| Área | Testes A | Cobertura actual* | Alvo pós-implementação |
|------|----------|-------------------|------------------------|
| Prep + linhagem | A001–A049 | 25% (L battery RPC) | 85% |
| Publish + teardown | A050–A079 | 10% | 50% |
| Seller Operação | A080–A129 | 20% (harness accept) | 80% |
| Seller Catálogo | A130–A144 | 15% | 75% |
| Comprador player | A145–A189 | 25% (Maestro smoke) | 80% |
| Saco + checkout | A190–A230 | 30% (unit+partial RPC) | 85% |
| Pagamentos + orders | A219–A249 | 40% (V0.3a) | 90% |
| Rifa | A211–A279 | 35% (unit+bot partial) | 80% |
| Chat + msgs + FOMO | A280–A294 | 45% (unit humanizer) | 85% |
| Gravado + replay | A295–A303 | 5% | 60% |
| Cross-pool + Z82 | A340–A369 | 10% (SQL only) | 90% |
| Marketplace TYPE A | A029,A138,A226,A347,A350–A369 | 5% | 70% |
| Helpers | A370–A376 | 0% | 50% |
| Erros + multi | A390–A400 | 5% | 40% |
| Sync + arquitectura | A420–A429 | 15% | 70% |

\*Cobertura actual = % de testes A com **qualquer** automação verde hoje (unit/integration/bot/maestro), não manual.

**Total registado:** **A001–A429** (429 fichas — **429 expandidas** em 9 ficheiros).

---

## 7. Automatizável vs nunca automatizável

### 7.1 Por tipo de automação (contagem A001–A429)

| Tipo | Aprox. testes | % |
|------|---------------|---|
| **Unit** | ~45 | 10% |
| **Integration** | ~95 | 22% |
| **Bot** | ~75 | 17% |
| **Maestro** | ~55 | 13% |
| **Manual** | ~140 | 33% |
| **Híbrido Bot+Maestro** | ~35 | 8% |
| **N/A / duplicado** | ~4 | 1% |

### 7.2 Nunca (ou quase nunca) automatizável

| Área | Motivo |
|------|--------|
| Stripe 3DS / banco real / produção | Sandbox �0� mundo real |
| Vídeo LiveKit/Mux (latência, áudio, freeze) | Infra externa + flake |
| Layout/player regressão visual BATATA | Sem screenshot diff pipeline |
| Seek replay HLS + sync frame-perfect | Player nativo |
| 2 telemóveis físicos realtime humano | Timing subjetivo |
| Deploy produção SQL + smoke humano | Risco operacional |
| Contas staff/RLS matriz completa | Muitas combinações permissão |
| APK release / Play Store | Pipeline distribuição |
| Gorjeta «feel» + wallet UX | Confiança utilizador |
| Sheet linhagem UX (L7–L9) | Decisão humana visual |

### 7.3 Parcialmente automatizável (bot prepara, humano valida)

- A3 stock visual alinhamento catálogo/barra/carrossel  
- R1 card verde timing  
- A2 chips saco cores/posições  
- Z82 UI badges após pool RPC OK  
- Open reservations warning copy  

---

## 8. Estratégia de regressão máxima

### Fase 0 — Governança (agora)
- [x] Este ficheiro = **fonte única** de IDs A
- [ ] **`fleaber_regression_runner.dart`** = orquestrador único (secção 9) — implementação por fases, **1 comando `--full` no fim**
- [ ] Cada bug fix live → referenciar A### na PR + actualizar `risk_graph.json`
- [ ] Estado persistente por A### em `test/regression/state.json` (não checklists dispersos)

### Fase 1 — Integration core (dentro do runner, ROI máximo)
1. Adaptadores no runner para `live_ops_staging_check.dart` (A088, A206–A210, ⬦)  
2. Fix staging: **lives MAESTRO não morrem** no fullSweep (A063)  
3. Novos adapters: mensagens A280–A294, cross-pool A340–A344  
4. Tudo invocado por `--full`; fases isoladas só via `--range` / `--area` durante desenvolvimento

### Fase 2 — Bot + Maestro (mesmo orquestrador)
1. Runner chama `fleaber_bot_simulator.dart` → escreve `.maestro/.env` → Maestro → verify  
2. Contrato secção 4.2 embutido no runner (sem scripts `.ps1` paralelos)  
3. H01–H08 = **suites** referenciadas por A### no manifest

### Fase 3 — Maestro smoke (filtro do runner, não comando à parte)
1. Flows: prep (A019), player (A145), saco (A190), harness (A071)  
2. Runner regista SKIP se device/emulador indisponível; MANUAL se Stripe/WebView obrigatório

### Fase 4 — Manual gate (output do runner)
- `--full` marca P0 Manual como `MANUAL` + lista em `retest_required.md`  
- Humano actualiza estado via `dart run tool/fleaber_regression_runner.dart --record-manual A205=pass`

### Fase 5 — Contínuo
- **PR:** `dart run tool/fleaber_regression_runner.dart --priority P0` (subconjunto rápido)  
- **Nightly:** `--full`  
- **Pós-fix:** `--retest-required` ou sugestão risk-based (secção 9.8)

### Métrica alvo
- **P0:** �0�80% com automação verde antes do manual  
- **P1:** �0�50%  
- **Tempo ciclo:** `--full` alvo &lt;45 min CI staging; P0 subset &lt;15 min  

---

## 9. Arquitectura do Fleaber Regression Runner

**Princípio:** a matriz A001–A429 é a fonte de verdade; o runner é **um único orquestrador**. A implementação pode ser por fases, mas **nunca** por dezenas de comandos soltos — tudo converge em `tool/fleaber_regression_runner.dart`.

**Estado actual:** especificação (este documento). Implementação pendente.

### 9.1 Comando principal

```bash
dart run tool/fleaber_regression_runner.dart --full
```

Executa **toda** a bateria disponível, na ordem:

1. **Unit** — `flutter test` (packages/fichas do manifest)  
2. **Integration** — adapters `tool/*.dart` + queries Supabase staging  
3. **Bot** — `fleaber_bot_simulator.dart` (seed, stress, mensagens, stock)  
4. **Maestro** — flows `.maestro/` quando device/emulador disponível  
5. **Validações pós-camada** — BD, mensagens, stock, checkout, rifa, gravado (asserts do manifest)  
6. **Síntese** — escreve artefactos em `test/regression/runs/<timestamp>/`

Testes ainda sem adapter → estado `not_implemented` (não falham o `--full`; contam em coverage).

Testes que exigem humano (Stripe WebView, 2 devices, vídeo Mux) → correm até ao limite automático; resultado `MANUAL` + entrada em `retest_required.md`.

### 9.2 Comandos parciais (filtros do mesmo orquestrador)

| Comando | Efeito |
|---------|--------|
| `--full` | Tudo (predefinição release/nightly) |
| `--failed-only` | Re-corre só A### com último estado `fail` ou `flaky` |
| `--retest-required` | Re-corre `retest_required` + sugestões risk-based (9.8) |
| `--range A050-A079` | Subconjunto por ID (inclusive) |
| `--priority P0` | Só P0 do manifest |
| `--area checkout` | Área lógica (`prep`, `publish`, `checkout`, `rifa`, `gravado`, ⬦) |
| `--id A209` | Um teste (debug) |
| `--record-manual A205=pass` | Humano regista resultado manual sem re-correr |

Todos os comandos partilham: mesmo manifest, mesmo `state.json`, mesmos formatos de output.

### 9.3 Estados persistentes por A###

Ficheiro: `test/regression/state.json` (versionado; último resultado por ID).

| Estado | Significado |
|--------|-------------|
| `not_implemented` | Ficha na matriz; sem adapter no runner |
| `automated` | Adapter existe; última execução ainda não corrida neste ambiente |
| `pass` | �altima execução OK |
| `fail` | �altima execução falhou |
| `skip` | Ignorado (env em falta, device offline, flag `--skip-maestro`) |
| `flaky` | Passou após retry; ou falhou 1� e passou 2� |
| `manual` | Requer validação humana; runner não pode fechar sozinho |
| `retest_required` | Marcado após alteração de código (risk graph ou humano) |

Transições típicas:

- `not_implemented` → `pass`/`fail` quando adapter é adicionado  
- `pass` → `retest_required` quando ficheiro/componente afectado muda (9.8)  
- `fail` → `pass` via `--failed-only`  
- execução parcial: IDs fora do filtro **não** alteram estado

### 9.4 Associação A### �  testes reais

Ficheiro: `test/regression/manifest.json`

```json
{
  "version": 1,
  "tests": {
    "A209": {
      "name": "RPC batata_live_reconcile_stripe_order",
      "area": "checkout",
      "priority": "P0",
      "layers": ["integration"],
      "adapters": [
        { "type": "dart_tool", "path": "tool/live_ops_staging_check.dart", "entry": "scenarioReconcile" }
      ],
      "assertions": ["bd.orders.status", "bd.reservation.converted"],
      "depends_on": ["A206"],
      "risk_edges": ["A198", "A206", "A208", "A225", "A227"],
      "maestro": null,
      "bot": null
    }
  }
}
```

Regras:

- **1 A### = 1 ficha** na matriz; pode ter **N adapters** (unit + integration + bot + maestro).  
- `layers` define o que `--full` tenta, por ordem.  
- `H01`–`H08` são suites referenciadas em `bot.suite` / `maestro.flow`, não IDs A.  
- Fichas expandidas (`docs/live-ecosystem-test-matrix-A###.md`) alimentam o manifest (nome, deps, componentes).

### 9.5 Formato `results.json`

Path: `test/regression/runs/<run_id>/results.json`

```json
{
  "run_id": "2026-06-14T22-15-00Z",
  "command": "full",
  "git_sha": "abc123",
  "environment": "staging",
  "duration_ms": 1240000,
  "summary": { "pass": 42, "fail": 3, "skip": 12, "manual": 28, "not_implemented": 344 },
  "tests": [
    {
      "id": "A209",
      "name": "RPC reconcile stripe order",
      "status": "pass",
      "layers_run": ["integration"],
      "duration_ms": 4200,
      "message": null,
      "artifacts": ["logs/A209_integration.log"],
      "bd_checks": [{ "query": "orders.status", "expected": "pago", "actual": "pago", "ok": true }]
    },
    {
      "id": "A205",
      "name": "Stripe WebView abre",
      "status": "manual",
      "layers_run": [],
      "message": "Requer cartão teste + browser; ver retest_required.md"
    }
  ]
}
```

### 9.6 Formato `summary.md`

Path: `test/regression/runs/<run_id>/summary.md`

Conteúdo gerado:

- Cabeçalho: comando, SHA, duração, ambiente  
- Tabela: PASS / FAIL / SKIP / MANUAL / NOT_IMPLEMENTED  
- Lista FAIL com mensagem curta + link log  
- Lista MANUAL com instruções de `docs/` ou ficha A###  
- Próximo passo sugerido: `--failed-only` ou `--retest-required`

### 9.7 Outros artefactos

| Ficheiro | Conteúdo |
|----------|----------|
| `failed.md` | Só FAIL + flaky; passos reprodução; queries BD |
| `retest_required.md` | IDs `retest_required` + sugestões risk-based pendentes |
| `coverage_by_area.md` | Por área: total / pass / fail / manual / not_implemented % |
| `regression_risk.md` | Alterações recentes (git diff) → A### afectados → deps sugeridas |

### 9.8 Risk-based regression

Ficheiro: `test/regression/risk_graph.json` — arestas dirigidas `fix_A209 → [A198, A206, ⬦]` (das fichas **Dependências** / **Risco de regressão**).

Fluxo após fix:

1. PR altera `live_reservation_queue_service.dart`  
2. Runner (ou CI) corre `dart run tool/fleaber_regression_runner.dart --suggest-retest --changed lib/utils/live_reservation_queue_service.dart`  
3. Output: `retest A198, A206, A208, A209, A225, A227`  
4. Estados passam a `retest_required` em `state.json`  
5. `dart run tool/fleaber_regression_runner.dart --retest-required` executa só esse conjunto

O grafo é alimentado pelas expansões da matriz (campos **Dependências** em cada ficha).

### 9.9 Ordem de execução no `--full`

```
—R—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
— fleaber_regression_runner.dart --full                    —
—S—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
— 1. Load manifest.json + state.json + risk_graph.json    —
— 2. Resolve plano (topo-sort depends_on; P0 primeiro)    —
— 3. flutter test          → Unit adapters                —
— 4. dart tool/*           → Integration                  —
— 5. fleaber_bot_simulator → seed + scenarios             —
— 6. maestro test          → UI (se ANDROID_DEVICE set)   —
— 7. BD/message/stock      → asserts SQL pós-bot          —
— 8. Merge resultados      → results.json + *.md          —
— 9. Update state.json     → pass/fail/skip/manual/⬦      —
——�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�—�
```

**Sincronização Bot �  Maestro �  Cursor:** o runner é o ponto único; sessões Cursor devem invocar `--range` / `--retest-required`, nunca `dart run tool/live_ops_staging_check.dart` isolado em CI (o adapter permanece no repo, mas só via runner).

### 9.10 Implementação por fases (sem partir a bateria)

| Fase | Entregável no runner | IDs exemplo |
|------|----------------------|-------------|
| 1 | Manifest + state + `--full` esqueleto | A209, A230 |
| 2 | Integration adapters | A050–A079 subset, A190–A210 |
| 3 | Unit wiring | A199–A201, A280–A294 |
| 4 | Bot + Maestro H01–H08 | A071, A081, A190 |
| 5 | Risk graph + `--retest-required` | todos P0 |

Até à fase 5, `--full` corre o que existir e marca o resto `not_implemented` — **um comando, um relatório**.

---

## Apêndice A — Componentes principais (referência rápida)

| Componente | Path |
|------------|------|
| Player | `lib/fleaber_live_player/fleaber_live_player_widget.dart` |
| Studio | `lib/widgets/live_vendor_studio_panel.dart` |
| Criar | `lib/vendedor/criar_directo_page_widget.dart` |
| Prep | `lib/vendedor/preparar_directo_page_widget.dart` |
| Saco | `lib/widgets/live_bag_sheet.dart` |
| Checkout | `lib/widgets/live_bag_checkout_sheet.dart`, `lib/utils/live_in_stream_checkout.dart` |
| Reservas | `lib/utils/live_reservation_queue_service.dart` |
| Stock | `lib/utils/live_catalog_stock_service.dart` |
| Humanizer | `lib/utils/live_system_chat_humanizer.dart` |
| Rifa | `lib/utils/live_raffle_service.dart` |
| Cleanup | `lib/utils/live_publish_cleanup.dart` |
| SQL core | `supabase/sql/live_ops_hotfix_batata.sql`, `live_items_inventory_batata.sql`, `live_reservation_requests_batata.sql`, `live_raffles_batata.sql`, `ref_histories_batata.sql` |

---

*Documento vivo. Próximo ID livre: **A430**.*
