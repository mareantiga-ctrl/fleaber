# Auditoria técnica Fleaber — preparação para escala

**Data:** Maio 2026  
**Âmbito:** análise read-only do repositório (sem alterações de código)  
**Cenário-alvo:** 100 sellers activas · 10 000 utilizadores · centenas de lives/semana · expansão multi-país  

**Inventário do repo:** ~200 ficheiros Dart · 49 scripts SQL · 9 edge functions · sem pasta `supabase/migrations/` (deploy manual por scripts BATATA)

---

## Sumário executivo

O Fleaber é uma plataforma **feature-rich** com camada SQL densa (`batata_*`, ~69 RPCs), fluxos paralelos de reserva (marketplace `orders` vs live `live_reservation_requests`), e UI monolítica no player live e studio vendedora. A arquitectura actual **suporta bem dezenas de sellers e centenas de utilizadores simultâneos**, mas **não está pronta** para 500 viewers num único directo popular nem para operação multi-país sem trabalho de hardening.

**Riscos mais urgentes (antes de escala comercial):**

1. **Segurança:** RPC `batata_live_reservation_stripe_convert` executável por qualquer utilizador autenticado sem verificação de ownership.
2. **Pagamentos:** ausência de webhook Stripe — liquidação depende de return URL + reconcile no cliente.
3. **Realtime:** app subscreve tabelas não publicadas no `supabase_realtime` → polling/RPC redundantes; fan-out catastrófico com muitos viewers.
4. **Deploy SQL:** 49 scripts ad-hoc; produção pode correr versões antigas de stock/reservas.
5. **Estados presos:** timestamps de expiração sem cron de enforcement.

**O que rebenta primeiro (A2):** Realtime + RPC `batata_live_viewer_ping` num directo com ~300–500 viewers; em seguida N+1 de `batata_live_item_stock` no studio em flash sales.

---

# Secção A1 — CRÍTICO (base de dados, segurança, integridade)

## A1.1 Arquitectura de dados

### Modelo híbrido FlutterFlow + BATATA

| Origem | Tabelas | Risco |
|--------|---------|-------|
| Criadas em SQL repo | `lives`, `live_items`, `live_messages`, `live_reservation_requests`, `products`, `wallets`, `order_disputes`, etc. (23) | Versionadas no repo |
| Referenciadas mas **sem CREATE** no repo | `orders`, `profiles`, `chats`, `reviews`, `chat_messages` | Schema de produção pode divergir do assumido pelos scripts |

**Impacto:** scripts BATATA assumem colunas (`live_id`, `live_item_id`, `reservation_expires_at`, `wallet_release_processed_at`) que podem não existir se migrações FlutterFlow não foram aplicadas em sincronia.

**Gravidade:** ALTA · **Correcção:** média-alta (inventário schema + migrations versionadas)

### Dual ownership em `lives`

Colunas `seller_id` e `vendedor_id` coexistem. RPCs e RLS verificam `coalesce(seller_id, vendedor_id)` — qualquer código que só leia uma coluna gera **reservas invisíveis** ou lives órfãs.

**Gravidade:** MÉDIA · **Correcção:** média (normalizar + backfill)

### `logical_item_id` e linhagens (V1.5)

Backfill por `live_item` individual (não seller+ref) — correcto para refs reutilizadas. Duplicação de lógica entre `live_ops_hotfix_batata.sql`, `live_logical_item_id_batata.sql`, `live_items_inventory_batata.sql`.

**Gravidade:** BAIXA (manutenção) · **Correcção:** baixa se hotfix for fonte única

---

## A1.2 Foreign keys e integridade referencial

| Tabela | FK | Lacuna |
|--------|-----|--------|
| `live_items` | → `lives`, `products` | OK |
| `live_reservation_requests` | → `lives`, `live_items`, `profiles` (seller/buyer) | `seller_id` não valida contra dono da live |
| `live_vendor_studio_logs` | **Nenhuma** | UUIDs livres — logs spoofáveis |
| `orders` | (externo) | `live_item_id` pode apontar para item de outra live |
| `fleaber_commissions` | → `orders` | OK |

### Estados órfãos identificados

| Estado órfão | Como surge | Consequência |
|--------------|------------|--------------|
| Reserva `pending`/`accepted` para live `ended` | Live termina sem cleanup | Stock bloqueado; popup início directo |
| Order `reserva_pendente` sem acção seller | Sem cron | Suporte manual |
| Order `pago` + reserva não `converted` | Return URL falhou | Reconcile cliente; saco incoerente |
| `live_items.status = sold` com qty reposta | Edição catálogo pós-venda | Corrigido no hotfix mas depende de deploy |
| Shadow `products` com price 0 | live_only sem preço | Mitigado V1 price pending |
| Wallet nunca libertada | Buyer não avalia ≥4★ | Seller sem payout |

**Gravidade:** ALTA (pagamentos/reservas) · **Correcção:** média (webhook + cron + constraints)

---

## A1.3 Índices

Índices relevantes existem para filas live (`live_reservation_requests`), tips Stripe, wallet idempotency, `logical_item_id`, unique `(live_id, product_id)`.

**Lacunas prováveis em escala:**

- `orders(seller_id, status, created_at)` — studio subscreve **todos** orders do seller
- `live_reservation_requests(live_id, status, queue_position)` — OK no script base
- `live_messages(live_id, created_at)` — chat sem paginação; índice ajuda mas não resolve volume

**Gravidade:** MÉDIA · **Correcção:** baixa-média

---

## A1.4 RLS (Row Level Security)

| Área | Política | Problema |
|------|----------|----------|
| `profiles` | SELECT `using (true)` para auth **e anon** | **Exposição PII** — qualquer user lê todos os perfis |
| `orders` | SELECT/UPDATE buyer/seller | Sem DELETE; admin via RPC |
| `live_reservation_requests` | Hotfix alarga SELECT a live-owner | Depende de hotfix aplicado |
| `app_logs` | INSERT aberto (anon+auth) | Spam / injecção JSON |
| `wallet_transactions` | SELECT próprio | INSERT só via RPC — OK |
| `live_tips` | SELECT participantes | INSERT via RPC — OK |

### RPCs SECURITY DEFINER

~69 funções `batata_*` contornam RLS por design. Aumenta superfície: **cada RPC precisa validação explícita de `auth.uid()`**.

**Gravidade:** ALTA (profiles + RPCs mal restritas) · **Correcção:** média

---

## A1.5 Achados de segurança CRÍTICOS

### C1 — `batata_live_reservation_stripe_convert` sem autorização

**Ficheiro:** `supabase/sql/live_ops_hotfix_batata.sql` (~L947)  
**Grant:** `authenticated`, `service_role`  
**Problema:** qualquer user autenticado pode passar `p_request_id` arbitrário e forçar `status = converted`, disparando recompute stock, FOMO, etc.  
**Gravidade:** **CRÍTICA**  
**Impacto:** fraude de stock, esgotamento falso, manipulação de fila  
**Correcção:** baixa (restringir a `service_role` ou validar buyer/order)

### C2 — `batata_find_user_id_by_email` (enumeração)

**Ficheiro:** `supabase/sql/seller_helpers_staff_batata.sql`  
**Grant:** `authenticated`  
**Problema:** revela UUID por email  
**Gravidade:** ALTA · **Correcção:** baixa

### C3 — Edge `verify_jwt = false` em pagamentos

**Ficheiros:** `create-payment-intent`, `create-live-tip-checkout`  
Mitigado por `getUser()` interno, mas regressão futura é risco.  
**Gravidade:** MÉDIA · **Correcção:** baixa

### C4 — Deploy SQL sem versionamento

49 scripts; último aplicado ganha. Produção pode ter `batata_process_live_reservation_request` com bug `products.id = live_item.id` (ficheiro antigo).  
**Gravidade:** ALTA · **Correcção:** alta (migrations + CI)

---

## A1.6 Triggers e concorrência

| Trigger | Risco |
|---------|-------|
| `batata_live_reservation_assign_queue` | `max(queue_position)+1` **sem lock** → posições duplicadas em burst |
| `batata_mark_product_sold_on_paid_order` | OK com idempotency |
| `batata_wallet_order_status_trg` | OK |
| Wallet `FOR UPDATE SKIP LOCKED` em cron offers | Bom padrão |

**Gravidade fila:** MÉDIA em flash sales · **Correcção:** média (advisory lock ou serializable)

---

## A1.7 Edge functions

| Function | JWT | Função |
|----------|-----|--------|
| `create-payment-intent` | false | Checkout Stripe + settle GET |
| `create-live-tip-checkout` | false | Tips |
| `create-mux-live` / `complete-mux-live` | true | Streaming |
| `livekit-mux-publish` | true | LiveKit + egress |
| `livekit-egress-cleanup` | false | Cron cleanup |
| `create-connect-account` | true | Stripe Connect |
| `resolve-mux-playback` | true | VOD |
| `send-sms-bulkgate` | webhook | SMS auth |

**Lacuna crítica:** **sem webhook Stripe** (`checkout.session.completed`). Todo o fluxo `pago` depende de:
- browser abrir success URL
- `FleaberStripeCheckoutContext.tryResumeOnAppResumed`
- RPC `batata_live_reconcile_stripe_order`

**Gravidade:** CRÍTICA para produção · **Correcção:** média

---

## A1.8 Realtime e storage

### Realtime

**Publicados em SQL:** `live_messages`, `live_private_messages`  
**Subscritos na app mas NÃO publicados:** `live_items`, `live_reservation_requests`, `orders`, `user_notifications`

Consequência: features dependem de **polling** (4s reservas studio, 8s/20s player) e RPC queue. Comentário no hotfix: queue RPC existe porque «select directo + realtime falha sob RLS».

**Gravidade:** ALTA · **Correcção:** baixa (Dashboard publication + testar)

### Storage

Bucket `chat_media` referenciado em comentário; **políticas não estão no repo**. Auditoria de storage impossível só pelo código.

**Gravidade:** MÉDIA · **Correcção:** baixa (documentar + RLS storage)

---

## A1.7 Tabela resumo A1

| ID | Achado | Gravidade | Impacto | Dificuldade |
|----|--------|-----------|---------|-------------|
| C1 | RPC stripe_convert sem auth | Crítica | Fraude stock/fila | Baixa |
| C2 | Sem webhook Stripe | Crítica | Pagamentos presos | Média |
| C3 | Profiles SELECT aberto | Alta | PII / GDPR | Média |
| C4 | SQL deploy ad-hoc | Alta | Comportamento divergente | Alta |
| C5 | Realtime publication gap | Alta | Polling excessivo / UX morta | Baixa |
| C6 | Estados sem cron expire | Alta | Suporte manual | Média |
| C7 | Email → UUID RPC | Alta | Enumeração | Baixa |
| C8 | Queue position race | Média | Fila inconsistente | Média |
| C9 | `live_vendor_studio_logs` sem FK | Média | Logs inválidos | Baixa |
| C10 | `app_logs` insert aberto | Média | Abuso escrita | Baixa |
| C11 | Tabelas core fora do repo | Média | Drift schema | Alta |
| C12 | Storage policies ausentes | Média | Segurança media | Baixa |

---

# Secção A2 — ESCALABILIDADE

## Cenário de carga

| Dimensão | Valor assumido |
|----------|----------------|
| Sellers simultâneas | 100 |
| Viewers simultâneos (total) | 500 |
| Pico num directo popular | 300–500 viewers |
| Lives por dia | 100 |
| Utilizadores registados | 10 000 |

## O que rebenta primeiro?

**Ordem de colapso (directo popular):**

```
1. Supabase Realtime (conexões + fan-out postgres changes)
      ↓
2. RPC batata_live_viewer_ping (~25 req/s só num stream a 500 viewers / 20s)
      ↓
3. Refetch catálogo live_items SEM LIMIT em cada update × N viewers
      ↓
4. Connection pool Postgres / rate limits Supabase
      ↓
5. Studio seller: N+1 batata_live_item_stock (50 RPCs por reload) + poll 4s
```

**Com carga distribuída** (100 lives × ~5 viewers): o gargalo desloca-se para **home feed + queries sem limite** e **chat threads longas**, não para Realtime global.

---

## A2.1 Hotspots de leitura

| Local | Padrão | Ficheiro |
|-------|--------|----------|
| Player catálogo | `live_items` por `live_id` **sem limit** | `fleaber_live_player_widget.dart` |
| Player show events | sem limit | idem |
| Home | lives `.range(0,19)` OK; marketplace 40 produtos + 120 orders | `home_page_widget.dart` |
| Lista conversas | **todos** os chats do user | `lista_conversas_widget.dart` |
| Chat | stream **sem paginação** | `chat_page_widget.dart` |
| Studio métricas | até 3× 500 orders + tips | `live_vendor_studio_panel.dart` |
| Favoritos sync | limit 10 000 | `favorites_util.dart` |

---

## A2.2 Hotspots de escrita

| Local | Padrão |
|-------|--------|
| `batata_live_viewer_ping` | 1 insert/upsert por viewer / 20s |
| `live_reservation_requests` | burst em flash sale |
| `live_messages` | chat activo + system broadcasts |
| `live_vendor_studio_logs` | debug logging em acções studio |
| `app_logs` | crash reports client |
| `orders` | checkout Stripe |

---

## A2.3 Realtime por cliente

### Comprador no player (1 sessão)

~4–5 channels · 9–11 listeners `onPostgresChanges` · 2 stream subs

| Channel | Tabelas |
|---------|---------|
| `live_room:{id}` | messages, lives |
| `live_catalog:{id}` | live_items |
| `live_bag:{id}:{buyer}` | reservations |
| `live_buyer_checkout:{id}:{buyer}` | orders, products, reservations |
| `live_private:{id}:{uid}` | private messages |

**500 viewers ⇒ ~2000–2500 channel attachments** no mesmo `live_id`.

### Vendedora no studio (1 sessão)

- **Duplicado:** `LiveRoomService` no panel **e** no broadcast header → 2× presence
- 4× `.stream()` (reservations, items, **orders seller-wide**, tips)
- Poll reservas **4s** mesmo com realtime

---

## A2.4 RPCs em excesso

| RPC | Frequência estimada (pico) |
|-----|---------------------------|
| `batata_live_viewer_ping` | 25/s por stream @ 500 viewers |
| `batata_live_item_stock` | 50× por reload catalog studio; por modal comprador |
| `batata_live_reservation_queue_for_live` | 0.25/s poll + cada evento realtime |
| `batata_process_live_reservation_request` | por aceite/recusa |

`LiveCatalogStockService.fetchMany` — **loop sequencial**, não batch.

---

## A2.5 Páginas lentas em escala

| Página | Risco | Sintoma |
|--------|-------|---------|
| `fleaber_live_player_widget` | **Crítico** | Lag UI, desconexões realtime, timeouts |
| `live_vendor_studio_panel` | **Alto** | Jank em fila grande; RPC storm |
| `chat_page_widget` | Médio | Threads 5k+ msgs |
| `lista_conversas_widget` | Médio | Sellers com 200+ chats |
| `home_page_widget` | Baixo-médio | Timeout 20s em rede lenta |
| `minhas_encomendas` | Baixo | limit razoável |

---

## A2.6 Recomendações escalabilidade (sem implementar)

| Prioridade | Acção | Impacto |
|------------|-------|---------|
| P0 | Agregar viewer count server-side; 1 ping/live não 1 ping/viewer | -95% RPC presence |
| P0 | `limit` + paginação catálogo live; debounce realtime catalog | -fan-out |
| P0 | Publicar tabelas realtime ou abandonar postgres changes falsos | Menos poll |
| P1 | RPC batch stock (`batata_live_items_stock_many`) | -50 RPCs/reload |
| P1 | Um `LiveRoomService` por device | -50% presence seller |
| P1 | Scope `orders.stream` a `live_id` | Menos refresh studio |
| P2 | Paginar chat e lista conversas | Memória |

---

# Secção A3 — FLUXO DE NEGÓCIO

## A3.1 Mapa do ciclo completo

```
┌─────────────┐
│   SELLER    │
└──────┬──────┘
       │ registo (user_type: vendedor default)
       ▼
┌─────────────┐     ┌──────────────────┐
│  Produto    │────►│ marketplace TYPE A│──► product_details checkout
│  live_only  │     └──────────────────┘
└──────┬──────┘
       │ prep refs / catálogo
       ▼
┌─────────────┐     aviso reservas abertas (logical_item_id)
│    LIVE     │────► Mux/LiveKit
└──────┬──────┘
       │
       ├──────────────────────────────────────┐
       ▼                                      ▼
┌─────────────────┐                  ┌─────────────────┐
│ live_reservation│                  │ orders (chat/   │
│ _requests       │                  │  marketplace)   │
│ pending→accepted│                  │ reserva_pendente│
│ →converted      │                  │ →reservado→pago │
└────────┬────────┘                  └────────┬────────┘
         │                                   │
         └─────────────┬─────────────────────┘
                       ▼
              ┌─────────────────┐
              │ Stripe Checkout │  (sem webhook)
              │ protection fee  │
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │ pago → enviado  │  (envio simulado 2s)
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │ concluido       │
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │ review ≥4★      │──► wallet seller - commission
              └────────┬────────┘
                       ▼
              ┌─────────────────┐
              │ disputa (opt.)  │──► devolvida / partial refund
              └─────────────────┘
```

## A3.2 Dois sistemas de reserva (confusão operacional)

| Aspecto | Marketplace `orders` | Live `live_reservation_requests` |
|---------|---------------------|----------------------------------|
| Estados | reserva_pendente, reservado, pago… | pending, accepted, converted |
| Aceite seller | Obrigatório (marketplace) | Opcional antes pagar (bag permite pending) |
| Expiração | 5d UI em reservado; **sem cron** | 45min `expires_at`; **sem cron** |
| Ponte Stripe | order_id | tag `stripe_checkout:{orderId}` |

**Situações de suporte manual:**

- Buyer pagou, order `pago`, saco ainda mostra reserva aberta
- Seller nunca aceita — buyer espera indefinidamente (marketplace)
- Live `pending` 3 anos — ainda conta no popup início (by design V1.5 L18)
- Wallet bloqueada — buyer não avalia
- Direct payment `aguarda_confirmacao` sem timeout
- Comprador paga sem preço (mitigado V1 price pending)

## A3.3 Estados impossíveis / loops

| Situação | Possível? | Notas |
|----------|-----------|-------|
| `converted` + stock disponível | Sim (repor qty) | Hotfix permite |
| `pago` + product `is_sold=false` | Raro | reconcile |
| Dupla posição fila | Sim | race trigger |
| Reserva + order pago desligados | Sim | sem webhook |

**Não há state machine central** — transições são PATCHes ad-hoc em Dart + RPCs.

---

# Secção A4 — MONETIZAÇÃO

## A4.1 Implementado hoje

| Fonte | Mecanismo | Ficheiros | Captura receita |
|-------|-----------|-----------|-----------------|
| **Seguro Fleaber** | 0,65 € + 5% (artigo+portes) | `fee_calculator.dart`, checkout UI | Buyer paga no total; `fleaber_commissions` na libertação wallet |
| **Tips live** | 2,9% + 0,40 € processing | `live_tip_flow.dart`, edge tip | Cobre Stripe; margem Fleaber unclear |
| **Stripe Connect** | Express onboarding | `create-connect-account` | Sellers recebem payout; sem take rate explícito na edge |
| **Ofertas preço** | Chat marketplace | `product_offers_batata.sql` | Indirecto (mais GMV) |
| **Bundles** | Descontos seller | `seller_bundle_discounts_batata.sql` | UI studio: «em breve» |

**Comissão só materializa** quando: order `concluido` + review ≥4★ + `batata_release_seller_wallet_for_order`.  
Pagamentos **directos** (fora Stripe) podem **nunca** gerar commission ledger.

## A4.2 Ideias futuras — matriz priorização

| Ideia | Potencial receita | Complexidade | Prioridade |
|-------|-------------------|--------------|------------|
| Webhook + enforcement fees em todos os pagamentos | Alto (reduz leakage) | Média | **P0** |
| Comissão % sobre GMV live (take rate seller) | Alto | Média | **P1** |
| Subscrição seller (analytics, slots live, staff) | Médio-alto | Alta | P1 |
| Destaque live na Home / feed promovido | Médio | Média | P1 |
| Taxa fixa por live hosted (Mux/LiveKit cost+) | Médio | Baixa-média | P2 |
| Publicidade in-feed (não live player) | Médio | Alta | P2 |
| Coleções curadas / comissão afiliado | Baixo-médio | Média | P2 |
| Analytics seller premium (export, funil) | Baixo-médio | Média | P2 |
| Labels envio com markup (CTT/API) | Médio | Alta | P2 |
| Micro-transacções (stickers, super-chat) | Baixo-médio | Média | P3 |
| Multi-moeda / FX spread | Alto (internacional) | Muito alta | P3 |

---

# Secção A5 — ONBOARDING

## A5.1 Jornada seller nova (mapa)

```
Registo (/registo)
  │ default user_type: vendedor (!)
  │ phone opcional
  ▼
Home (comprador E seller misturados)
  │
  ├─► Criar → Sheet «Novo Anúncio» → seller_product_form
  │
  └─► Criar → «Novo Direto» → preparar_directo
        │ pressão longa refs (#1…#N)
        │ sheet linhagem (se histórico)
        ▼
      criar_directo → popup reservas abertas → LIVE
        │
        ▼
      Primeira reserva (comprador) → aceitar → pagar
        │
        ▼
      Stripe Connect (para levantar saldo)
```

## A5.2 Pontos de abandono e confusão

| # | Ponto | Problema | Gravidade |
|---|-------|----------|-----------|
| O1 | Registo | Todos entram como `vendedor` | Alta — confunde buyers |
| O2 | Primeiro produto vs primeiro directo | Dois caminhos sem guia | Alta |
| O3 | Preparar directo — refs | Pressão longa não óbvia | Alta |
| O4 | Sheet linhagem | Conceito «linhagem» técnico | Média |
| O5 | Stripe Connect | Obrigatório para payout; erro se não configurado | Alta |
| O6 | Dois sacos mentais | Bag live vs encomenda chat | Alta |
| O7 | Preço opcional live | Novo V1 — seller pode não perceber | Média |
| O8 | Aceitar reserva | Marketplace exige; live bag não | Média |
| O9 | Deep link Stripe | Retorno pode cair na Home | Alta |
| O10 | Funcionalidades escondidas | Staff helpers, bundles «em breve», duplicar/arquivar stub | Baixa |

## A5.3 Onboarding comprador

- Registo mesmo fluxo seller-default
- Descoberta live via Home feed (20 cards)
- Reservar no player — relativamente claro
- Pagamento Stripe sai da app — fricção conhecida

**Recomendação:** wizard pós-registo com role split + checklist «1.º anúncio / 1.ª live / Connect / 1.ª venda».

---

# Secção A6 — DÍVIDA TÉCNICA

## A6.1 Código duplicado / monólitos

| Item | Localização | Notas |
|------|-------------|-------|
| Player live | `fleaber_live_player_widget.dart` ~4.4k linhas | Checkout, bag, chat, catalog, tips |
| Studio vendedora | `live_vendor_studio_panel.dart` ~6k linhas | Catálogo, fila, chat, métricas |
| Chat | `chat_page_widget.dart` ~6k linhas | Orders, disputes, shipping |
| `LiveRoomService` duplicado | player + studio + header | 2× presence seller |
| Resolução produto | `_resolveProductForLiveItem` vs `_productForLiveItem` | 5 queries vs cache |
| Stock | RPC vs fallback orders no player | Inconsistência qty |
| `perfil_vendedor_copy/` | 2 ficheiros | **Morto** — não exportado |
| SQL `batata_*` | hotfix + 4 ficheiros espelho | Manutenção 5× |

## A6.2 RPCs / serviços redundantes

- `batata_live_reservation_queue_for_live` vs SELECT directo (workaround RLS)
- `reconcileStripePaidOrder` + `reconcileStalePaidReservationsForLive` + edge GET settle — triple path
- Poll 4s + realtime no studio — redundante

## A6.3 Features incompletas (stubs)

- Catálogo: Duplicar / Arquivar → `_catalogMenuSoon`
- Bundles studio → «em breve»
- Envio real → `_onSellerConfirmShipment` delay 2s simulado
- Cron expiração reservas → timestamps only
- i18n → hardcoded `pt_PT`, `€` (bloqueio multi-país)

## A6.4 FlutterFlow legacy

- `flutter_flow/` theme, nav, models
- Tabelas `orders`, `profiles` geridas fora BATATA
- Padrão `queryRows` sem limit defensivo

---

# RELATÓRIO FINAL — Roadmap por prioridade

## 🔴 A1 — Resolver ANTES do lançamento (escala comercial / dinheiro real)

| # | Item | Área | Esforço |
|---|------|------|---------|
| 1 | Restringir `batata_live_reservation_stripe_convert` a service_role + validação ownership | Segurança SQL | S |
| 2 | Webhook Stripe `checkout.session.completed` como source of truth | Edge + SQL | M |
| 3 | Confirmar produção com `live_ops_hotfix_batata.sql` completo aplicado | Ops | S |
| 4 | Publicar realtime: `live_items`, `live_reservation_requests`, `orders` | Supabase Dashboard | S |
| 5 | RLS `profiles` — restringir SELECT a campos públicos ou relações | Segurança | M |
| 6 | Cron: expirar live `pending` (>45min), `reservado` (>5d), opcional `reserva_pendente` | SQL + pg_cron | M |
| 7 | Price pending V1 + edge `create-payment-intent` deployados | Já implementado — validar deploy | S |
| 8 | Inventário schema `orders`/`profiles` vs scripts BATATA | Documentação + migração | M |
| 9 | Testes manuais L1–L18 + P1–P15 antes de tráfego pago | QA | M |

**Sem estes itens:** risco financeiro, fraude de fila, pagamentos presos, PII exposta.

---

## 🟠 A2 — Resolver nos primeiros 3 meses (100 sellers / centenas de lives)

| # | Item | Área | Esforço |
|---|------|------|---------|
| 10 | Viewer presence agregado (1 RPC/live, não por cliente) | Escalabilidade | M |
| 11 | `limit` + paginação catálogo live + debounce catalog realtime | Player | M |
| 12 | RPC batch stock `fetchMany` | SQL + Dart | M |
| 13 | Consolidar `LiveRoomService` (remover duplicado header) | Dart | S |
| 14 | Studio: remover poll 4s onde realtime funciona; scope orders por `live_id` | Dart | M |
| 15 | Migrations versionadas (`supabase/migrations/`) | Ops | L |
| 16 | Advisory lock fila reservas | SQL | M |
| 17 | Wallet auto-release após N dias em `concluido` (sem review) | SQL | M |
| 18 | Onboarding: role split registo + checklist seller | Produto | M |
| 19 | Restringir `batata_find_user_id_by_email` | Segurança | S |
| 20 | Paginação chat + lista conversas | Dart | M |
| 21 | Monitoring: `app_logs` aggregation, alertas RPC error rate | Ops | M |
| 22 | Documentar + auditar storage `chat_media` policies | Segurança | S |

**Objectivo:** suportar 100 lives/dia e picos de 200–300 viewers/stream sem degradação severa.

---

## 🟢 A3 — Resolver mais tarde (10k users, multi-país, monetização avançada)

| # | Item | Área | Esforço |
|---|------|------|---------|
| 23 | i18n / multi-moeda / tax/VAT por país | Produto | L |
| 24 | Take rate % GMV live + dashboard receita Fleaber | Monetização | M |
| 25 | Subscrição seller + analytics premium | Monetização | L |
| 26 | Feed promovido / destaque lives | Monetização | M |
| 27 | Integração transportadora real (CTT, etc.) | Logística | L |
| 28 | Unificar modelo reserva (orders ↔ live_requests) | Arquitectura | L |
| 29 | Dividir monólitos player/studio/chat em módulos | Refactor | L |
| 30 | Remover `perfil_vendedor_copy`, stubs catálogo | Cleanup | S |
| 31 | State machine formal orders + reservations | Arquitectura | L |
| 32 | CDN/cache catálogo live para viewers | Infra | M |
| 33 | Maestro/E2E automatizado pós-deploy | QA | M |
| 34 | GDPR: export/delete user, retenção `app_logs` | Compliance | M |

---

## Métricas de sucesso sugeridas (pós-hardening)

| Métrica | Alvo pré-escala |
|---------|-----------------|
| Pagamentos `pago` sem reconcile manual | > 99,5% |
| Tempo médio RPC `batata_live_item_stock` p95 | < 100ms |
| Viewers máximos/stream sem erro Realtime | ≥ 300 |
| Reservas `pending` > 24h (sem acção) | < 1% |
| Tickets suporte «paguei mas não aparece» | < 0,5% GMV |

---

## Apêndice — Ficheiros-chave auditados

| Domínio | Paths |
|---------|-------|
| SQL core | `supabase/sql/live_ops_hotfix_batata.sql`, `live_reservation_requests_batata.sql`, `wallets_batata.sql`, `live_items_inventory_batata.sql` |
| Edge pagamentos | `supabase/functions/create-payment-intent/index.ts` |
| Player | `lib/fleaber_live_player/fleaber_live_player_widget.dart` |
| Studio | `lib/widgets/live_vendor_studio_panel.dart` |
| Reservas | `lib/utils/live_reservation_queue_service.dart` |
| Checkout | `lib/utils/live_in_stream_checkout.dart`, `lib/utils/fleaber_stripe_checkout_context.dart` |
| Fees | `lib/utils/fee_calculator.dart` |
| Orders UI | `lib/minhas_encomendas/minhas_encomendas_widget.dart`, `lib/order_cancel_eligibility.dart` |
| Chat lifecycle | `lib/chat_page/chat_page_widget.dart` |
| Onboarding | `lib/pages/registo/registo_widget.dart`, `lib/widgets/fleaber_create_sheet.dart` |
| Deploy checklist | `docs/deploy-checklist-v1.5-price-pending.md` |

---

*Relatório gerado por auditoria estática do repositório. Não substitui penetration test, load test em produção, nem revisão legal (GDPR/PCI). Recomenda-se load test com k6/Artillery no RPC `batata_live_viewer_ping` e Realtime antes de campanha de aquisição.*
