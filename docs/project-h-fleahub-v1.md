# Projecto H — FleaHub v1 (scope fechado)

> Documento de scope para a fase **FleaHub público completo**.  
> Complementa `docs/live-hub-master-plan.md`; não substitui decisões globais Hub.

**Estado:** `IMPLEMENTAÇÃO VISUAL` — H-v1 (2026-06-20)  
**Fase anterior fechada:** MVP FleaHub seller (gestão in-app)

---

## Princípio estratégico (funil 80/20)

> **O FleaHub serve primeiro a seller e a sua presença online, mas funciona também como um funil natural para o ecossistema Fleaber.**

| Peso | Objectivo |
|------|-----------|
| **~80%** | Valor próprio do FleaHub — presença da seller, directos, gravados, marketplace, opiniões, confiança |
| **~20%** | Aquisição natural para a Fleaber — perceber que existe app, comunidade e vantagens em entrar na plataforma |

**Tom:** nem landing agressiva, nem totalmente neutra. Quem visita deve sentir que está **dentro do ecossistema Fleaber**, sem CTAs invasivos.

**Esta fase (v1):** sem CTAs agressivos novos. Arquitectura e UX **devem deixar espaço** para aquisição futura.

---

## Princípio estratégico (tráfego externo)

> **O FleaHub não existe para substituir a Fleaber. Existe para trazer para dentro da Fleaber pessoas que hoje compram fora dela.**

**Hierarquia pretendida:**

```
Facebook / TikTok / Instagram / WhatsApp
              ↓
           FleaHub
              ↓
           Fleaber
```

| Objectivo | Como |
|-----------|------|
| Servir a seller | Presença, directos, gravados, marketplace, opiniões |
| Agregar presença online | URL partilhável, vitrine coerente |
| Captar tráfego externo | SEO + links em redes (seller partilha o FleaHub) |
| Encaminhar para Fleaber | Funil natural (~20%), **sem CTAs agressivos** |

**Risco a evitar:** o FleaHub evoluir para uma **segunda Fleaber paralela**. Mantém identidade Hub (seller-first); a app Fleaber continua o ecossistema completo.

---

## O que é o FleaHub (entidade)

O FleaHub **não** é apenas uma página pública SEO.

É a **entidade Hub** dentro da Fleaber: destino partilhável (`fleaber.pt/{handle}`) e ponto central do ecossistema Hub, preparado para crescer com:

- reservas externas (Facebook, TikTok) — *futuro*
- pagamentos externos — *futuro*
- histórico público, reputação, ferramentas de confiança — *futuro*
- cockpit operacional unificado — *futuro, pós-v1*

**Não implementar** essas peças nesta fase. Apenas **não bloquear** extensão (domain layer, secções plugáveis, capabilities stub).

---

## Coexistência com Perfil Fleaber

| | **FleaHub** | **Perfil Fleaber** |
|--|-------------|-------------------|
| Papel | Destino Hub público + funil | Perfil interno app (compradores Fleaber) |
| Identidade | `handle` / URL | `sellerID` (UUID) |
| Esta fase | Completar experiência v1 | **Sem alterações** (excepto copy FleaHub já fechada no seller) |

**Decisão:** coexistem. **Não** substituir Perfil Fleaber pelo FleaHub nesta fase. Avaliar convergência **depois** de v1 público fechado.

---

## Paridade app ↔ browser

Visitante que abre um endereço FleaHub vê a **mesma experiência** (mesmos widgets, `HubTheme`, secções) na app e no browser.

- Rotas Hub activas na app para superfícies FleaHub (além de `kIsWeb`).
- Perfil Fleaber buyer **não** é redirect forçado para FleaHub em v1.

---

## Entregáveis v1 (única frente aberta)

### Home `/{handle}`

**Hero:** foto · nome · localização · estrelas · **seguidores** · Seguir · Partilhar · Entrar no directo (se live)

**Secções (ordem — H-v1.1, 2026-06-20):**

1. **Hero**
2. **Em direto agora** — só se live activa → `/{handle}/live`
3. **Marketplace** — grelha + link `/shop` *(antes dos gravados — vende sem live)*
4. **Gravados** — recentes (`pastLives`)
5. **Opiniões** — amostra + link `/reviews`
6. **Sobre** — só se existir `hub_bio`
7. **Rodapé Fleaber** — `HubInstallBanner`

**Rodapé funil (suave, já alinhado 80/20):** `HubInstallBanner` — tom informativo, não popup. Login-on-action em Seguir / Reservar / Comprar (padrão existente).

### Superfícies relacionadas (já existem; polish v1)

- `/{handle}/live` — player, FOMO, catálogo live
- `/{handle}/shop` — marketplace
- `/{handle}/reviews` — opiniões

### Dados (mínimo)

- **Seguidores** — estender `hub_profiles_public` ou RPC read-only
- **Bio** — `profiles` + view (se «Sobre» entrar em v1)

---

## Funil Fleaber — v1 vs futuro

### v1 (permitido, não agressivo)

| Mecanismo | Papel 80/20 |
|-----------|-------------|
| Marca / tom Fleaber no tema Hub | Ecossistema visível, seller em foco |
| `HubInstallBanner` | ~20% — benefícios app (notificações, reserva, proteção) |
| Login-on-action (seguir, reservar) | Conversão natural no momento de intenção |
| Produto → `productDetails` in-app | Funil compra sem interromper FleaHub |

### Futuro (arquitectura preparada, **sem UI v1**)

- Notificações de directos da seller seguida
- Minhas reservas / encomendas
- Descobrir outras sellers
- Checkout web vs app (R37)
- Slots de secção «Descobre na Fleaber» (opcional, colapsável)
- `HubCapabilities` — flags FB/TT/pagamentos externos (stub null)

**Proibido em v1:** popups, interstitials, barras fixas «Baixa a app», countdown, bloqueio de conteúdo sem login.

---

## Arquitectura (extensível, não SEO-centric)

```
FleaHub (entidade: handle, profileId, capabilities*)
    │
    ├── HubPublicRepository  ← hub_* views only
    ├── HubProfileBundle / HubLiveBundle
    ├── Surfaces: Home · Live · Shop · Reviews
    └── FleaHubPublicHomeView (shared app + web)

* HubCapabilities stub — v1 sempre vazio/false (`crossChannelReservations: false`)
```

**Secções home:** lista ordenada plugável (`FleaHubSection` pattern) — adicionar slot futuro sem refactor total.

**SEO:** camada periférica (`hub_seo_*`, bootstrap) — não centrar desenho na «landing».

---

## Home vs FleaHub Live (direcção — sem UI nesta fase)

| Superfície | Papel |
|------------|--------|
| **Home** `/{handle}` | Montra — identidade, reputação, marketplace, gravados, opiniões, descoberta |
| **Live** `/{handle}/live` | Experiência operacional do comprador ligada ao directo |

**Home não é cockpit.** Não transformar a home em superfície operacional.

**Live — princípios (futuro):**

- **Vídeo primeiro.** Operação associada ao directo (não página autónoma de reservas).
- Comprador continua a ver/ouvir a live enquanto acompanha reservas, fila, pagamentos, estados dos artigos.
- UI concreta (sheet, painel expansível, secção na página Live) — **decisão posterior**.

### Expectativa comprador — Live Hub (A9, requisito funcional)

> **Não implementado nesta ronda.** Este bloco é **requisito funcional** da Live Hub — não nota vaga.

A **Home** `/{handle}` permanece **montra** (identidade, marketplace, gravados, opiniões).

A página **`/{handle}/live`** (directo ou gravado via `?liveId=`) deve convergir para a **UX operacional completa** do directo/gravado Fleaber, com vídeo sempre presente, e camada Hub por cima:

| Área | Requisito funcional |
|------|---------------------|
| **Vídeo** | Directo ou gravado seleccionado; elemento principal; sticky/mini-player em scroll (decisão UX posterior) |
| **Artigos** | Cards por referência; item activo; estados/cores por artigo |
| **Chat** | Acompanhar conversa em tempo real (não só feed estático) |
| **Opções do directo** | Acções principais visíveis (reservar, comprar, etc.) alinhadas com player Fleaber |
| **Reservas comprador** | Lista das reservas **da utilizadora autenticada** com estado claro |
| **Filas / posição** | Quando aplicável, posição na fila visível sem sair do vídeo |
| **Detalhe referência** | Expandir uma referência para ver detalhes do artigo/reserva |
| **Hub cross-canal** | Reservas originadas no FleaHub **e** futuras via PS (Facebook/TikTok) convergem na mesma lista/estado |
| **Compradora externa** | Ex.: veio do Facebook → abre FleaHub → login → **vê as suas reservas e estados na Live**, não só o vídeo |

**Princípio:** toda a operação vive **na Live Hub** — não é uma página autónoma de reservas.

**Cenário obrigatório (aceitação futura):** compradora com reservas associadas (Hub ou PS) abre `/{handle}/live`, autentica-se, e acede de imediato às suas reservas/estados **dentro** da superfície Live, com vídeo visível.

Validação real prevista: TCL (seller) + Xiaomi (comprador), live e reservas reais.

---

## Projecto Spy (PS) — relação com H

| | **PS** | **H (FleaHub)** |
|--|--------|-----------------|
| Nome | Projecto Spy | Projecto H |
| Papel | Motor de ingestão cross-canal | Superfície pública + funil |
| Spec | `docs/live-cross-channel-ingest-spec.md` | Este documento |

**Objectivo A (PS):** captar reservas externas — não perder vendas Facebook/TikTok.  
**Objectivo B (PS):** transformar compradores externas em utilizadoras Fleaber.

**Fluxo alvo:**

```
Facebook / TikTok / Instagram / WhatsApp
              ↓
             PS
              ↓
           FleaHub
              ↓
           Fleaber
```

**Nesta fase:** não implementar PS, UI PS, OCR, nem novos épicos. Apenas documentar relação H ↔ PS e stub `HubCapabilities.crossChannelReservations = false` em `lib/hub/data/hub_models.dart`.

---

## Fora de scope (não abrir)

- Cockpit operacional seller
- Helper avançado
- Integrações Facebook / TikTok
- Pagamentos externos (UI)
- Substituir / fundir Perfil Fleaber
- App Links (#22) — pode ser H.1.1 se urgente; não blocker v1 core

---

## Ordem de execução

| Passo | Conteúdo |
|-------|----------|
| **H-v1** | Dados (seguidores, bio) + UI home completa + gravados + paridade app |
| **H-v1.1** | Ordem secções (marketplace antes gravados) + hero compacto + docs Live/PS |
| **H-v1 review** | Screenshots pasta datada + testes |
| **H-v1.2** | Auditoria superfícies + fix gravados `?liveId=` + entradas app |
| **H-v2** | Avaliar convergência Perfil ↔ FleaHub (decisão produto) |
| **H-v3+** | Capabilities, integrações externas, cockpit |

---

## Testes manuais (numeração A#)

| ID | Área | Estado |
|----|------|--------|
| A0 | Entrada FleaHub perfil privado | PASS |
| A1 | Criar FleaHub (sheet) | Depende de **B1/B2** — telemóvel verificado (`phone_verified_at`) |
| A2 | Copiar link (sheet) | PASS |
| A3 | Partilhar (= copiar + feedback) | PASS |
| A3a | Partilhar nativo (share sheet) | **TODO backlog** — ver secção TODO |
| A4 | Ver FleaHub perfil visitante | PASS |
| A5 | FleaHub perfil vendedor próprio | PASS |
| A6 | FAB «Copiar link» Live | **Corrigido** — ícone na AppBar (sem overlay) |
| A7 | Gravados player VOD | **Corrigido** — `MuxPlaybackResolve` + placeholder se indisponível |
| A8 | Hero Home altura TCL | **Corrigido** — hero compacto (~136–152px, conteúdo no topo) |
| A9 | Live Hub ≈ Live Fleaber | **Requisito funcional** — ver secção Live acima |
| B1 | Telefone persiste em Editar Perfil | **Corrigido** — guarda rascunho antes de SMS |
| B2 | SMS `SEND_SMS_HOOK_SECRET` staging | Ver `supabase/functions/send-sms-bulkgate/SETUP.md` |

---

## TODO produto (registo)

- **A3a:** Substituir partilha temporária (clipboard) por share sheet nativo Android/iOS/Web quando existir integração aprovada (`share_plus` ou equivalente). **Não implementar até decisão explícita.**
- **A9:** Live Hub — requisitos funcionais na secção «Live Hub (A9)»; implementação em ronda dedicada.
- **B2:** Configurar secrets SMS no projecto staging `fxdknzrqjenzqcvnwqqq` — guia em `supabase/functions/send-sms-bulkgate/SETUP.md`.

---

## Referência código actual

- Pages: `lib/hub/pages/hub_profile_page.dart`, `hub_live_page.dart`, …
- Widgets: `lib/hub/widgets/hub_content_widgets.dart`, `hub_shared_widgets.dart`
- Data: `lib/hub/data/hub_public_repository.dart`, `supabase/sql/hub_public_views_batata.sql`
- Funil suave: `HubInstallBanner`, `HubActions`, login-on-action
