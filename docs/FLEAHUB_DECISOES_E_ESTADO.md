# FleaHub — decisões e estado (homepage)

Documento persistente. Actualizar no fim de cada intervenção na landing / páginas informativas.

**Última actualização:** 2026-10-26 (Entrega 109.1 — H06 copy final + capturas desktop; aprovada visualmente · CDN pendente)  
**Ambiente de desenvolvimento:** código e builds apontam a **produção** (`bpmpkzwnrbmuqnhgdscf`). Localhost = pré-visualização do mesmo build, não um ambiente paralelo.  
**Google Drive:** este ficheiro é só local — **não** sincronizado automaticamente.  
**Fonte inventário:** `00-fleahub-zips/0000087-fleaber-hub-web-auditoria-final-dossier/00-INVENTARIO-PAGINAS.md` (actualizado 2026-10-25 · Entrega 103).

---

## Inventário oficial de páginas FleaHub (confirmado 2026-10-25 · rev. Entrega 97)

Critério: **1 ecrã / 1 destino de navegação** com URL ou fluxo crítico documentado. Não contar tabs, painéis, modais nem o mesmo ecrã duas vezes.  
**H04/H05** mantêm o código de inventário (não renumerar) mas passam a **rotas de compatibilidade** → H02.

### Totais

| | |
|--|--|
| Total anterior (série 01–14, Out-2022) | **14** |
| Páginas novas acrescentadas | **5** (H15–H19 informativas + Contactos) |
| **Total IDs inventário** | **19** (H01–H19; H04/H05 = compat, não ecrãs autónomos) |
| **Ecrãs autónomos efectivos** | **17** (H02 absorve loja + opiniões) |

### A — Páginas do inventário (19 IDs)

| # | Nome | Rota (hash sob `/fleahub/`) | Ficheiro principal | Origem | Estado visual |
|---|------|----------------------------|--------------------|--------|---------------|
| H01 | Landing / Home Hub | `#/fleahub` | `lib/hub/pages/fleahub_landing_page.dart` | Original (14) | Chrome partilhado — GO humano pendente |
| H02 | Perfil vendedor (público) | `#/<handle>` (± `?tab=`) | `lib/hub/pages/hub_profile_page.dart` | Original | Entrega 102 fecho visual — **GO humano ainda pendente (não publicada)** |
| H03 | Live Hub | `#/<handle>/live` (± `?liveId=`) | `lib/hub/pages/hub_live_page.dart` | Original | **Entrega 106** polish layout/MP/saco/modal/gorjeta/FB — **GO humano pendente (não publicada)** |
| H04 | Loja / Marketplace | `#/<handle>/shop` | redirect → H02 `?tab=marketplace` | Original | **Integrada em H02** (compat URL) |
| H05 | Opiniões / Reviews | `#/<handle>/reviews` | redirect → H02 `?tab=opinioes` | Original | **Integrada em H02** (compat URL) |
| H06 | Not Found | secção/handle inválido | `lib/hub/pages/hub_not_found_page.dart` | Original | **Aprovada e concluída** (Entrega 109/109.1) · chrome claro H01/H02 · **CDN não publicado** |
| H07 | Hub Dev launcher | `#/hub-dev` | `lib/hub/pages/hub_dev_launcher_page.dart` | Original · QA interno | Interno — fora do caminho comercial |
| H08 | Login (+ returnTo Hub) | `#/login` | widget Login (app partilhado) | Original | A melhorar vs chrome FleaHub |
| H09 | Registo | `#/registo` | widget Registo | Original | A melhorar; registo público pode estar off |
| H10 | Mensagens | `#/listaConversas` (± tab notificações) | `lib/lista_conversas_widget.dart` | Original | A melhorar vs home |
| H11 | Perfil app / conta | `#/perfil` | `lib/perfil_widget.dart` | Original | A melhorar vs home |
| H12 | Infra / URLs / deep links | hash vs paths · redirects | docs / `hub_urls.dart` | Original | **Não é ecrã** — checklist técnico |
| H13 | Detalhe produto Hub | — | — | Original | **UI ausente** (documental) |
| H14 | Saco / reservas / checkout | overlay na Live (+ UC bag) | `hub_live_bag_sheet.dart` + fluxos | Original | **Sheet / fluxo**, não rota isolada; UI a alinhar |
| H15 | Como funciona | `#/fleahub/como-funciona` | `lib/hub/pages/fleahub_info_pages.dart` | **Nova** (pós-14) | Chrome alinhado (`FleaHubSiteScaffold`); corpo institucional |
| H16 | Comprar com segurança | `#/fleahub/comprar-com-seguranca` | idem | **Nova** | Chrome alinhado |
| H17 | Vender na Fleaber | `#/fleahub/vender` | idem | **Nova** | Chrome alinhado |
| H18 | Ajuda | `#/fleahub/ajuda` | idem | **Nova** | Chrome alinhado |
| H19 | Contactos e identificação legal | `#/fleahub/contactos` | idem (`FleaHubContactsPage`) | **Nova** | Chrome alinhado; conteúdo legal OK |

### B — Não contar como página extra (componentes / estados / alternativas)

| Tipo | Exemplos | Nota |
|------|----------|------|
| Separadores da landing | Diretos / Marketplace · `?tab=` · `?q=` | Mesmo H01 |
| Separadores H02 | Diretos / Marketplace / Opiniões · `?tab=` | Mesmo H02 (não contar H04/H05) |
| Rotas compat H04/H05 | `/shop` · `/reviews` | Redirect para H02 — IDs inventário preservados |
| Painel notificações | Sino topbar → overlay / bottom sheet | Componente; lista completa = tab em H10 |
| Sheet saco na live | Bag overlay | Já coberto por H14 |
| Rail direita | Saco / encomendas / Facebook / logos | Widgets da H01 |
| Cookie banner | Consent | Overlay global |
| Loading / skeleton Hub | `hub_loading_page` / `hub_skeleton_page` | Transitório |
| Chat thread | `#/chatPage` a partir de H10 | Continuação de Mensagens — não duplicar inventário |
| Encomendas app | `#/minhasEncomendas` (atalho rail/topbar) | App partilhada; **não** estava nas 14; destino lateral, não página Hub nativa nova no inventário canónico |

### C — Ligações externas / documentos legais (fora do contador 19)

| Destino | Como abre | Nota |
|---------|-----------|------|
| Termos / Privacidade / Cookies / Reembolsos | Rodapé → `LegalDocumentPageWidget` (`#/legalDocument?kind=…`) ou `fleaber.pt/*.html` no web | Uma superfície legal com kinds; HTML público no domínio |
| Livro de Reclamações | URL externa `livroreclamacoes.pt` | Externo |
| Google Play | Badge «Em breve» | Sem loja |

### Prioridade de melhoria visual (coerência com homepage aprovada)

1. **Alta:** GO humano H02 + H03 Entrega 103 (depois H04 só com autorização).  
2. **Média:** H10 Mensagens · H11 Perfil app · H08/H09 Login/Registo · H14 sheet saco.  
3. **Baixa / já alinhadas:** H15–H19 (chrome `FleaHubSiteScaffold` + tipografia Fleaber).  
4. **Feito / em GO:** H01 Landing · H02 (fecho 102, GO pendente) · H03 (reform 103, GO pendente).  
5. **Compat (não polish autónomo):** H04/H05 redirects.  
6. **Excluir do polish comercial:** H07 Hub Dev · H12 infra · H13 ausente.

---

## Aprovação visual (mantida)

Homepage visualmente aprovada. Nesta ronda:

- **Não** redesenhar grelha/nav/pesquisa/cores/proporções 17/62/21.
- Excepção autorizada: **sino de notificações** na topbar (auth).
- Rodapé slim + `/fleahub/contactos` (já implementados).

Pendentes **sem** integração técnica nesta ronda: Facebook (APIs), Google Play «Em breve», MB WAY/DPD só visuais, telefone actual sem alteração.

---

## Estrutura final da homepage

| Zona | Função | Proporção desktop (≥1180px) |
|------|--------|------------------------------|
| **Topbar** | Logo, pesquisa, **mensagens · sino · saco · avatar** (ou Entrar) | 68px / 58px compact |
| **Esquerda** | Explorar + info + Google Play Em breve | ~17% |
| **Centro** | Grelha Ao vivo / Gravados / FleaHubs / pesquisa | ~62% |
| **Direita** | Saco, encomendas, Facebook, pagamentos, pitch | ~21% |
| **Rodapé** | Marca + entidade (NIF) + Contactos + legais + copyright | 3 colunas |

---

## Centro de notificações (2026-10-25)

### Decisão

Reutilizar a arquitectura já existente — **sem tabela nova**, sem enfraquecer RLS:

| Peça | Função |
|------|--------|
| `public.user_notifications` | Inbox (kind, title, body, chat_id, is_read, …) |
| RLS select/update own | Isolamento por `auth.uid()` |
| Triggers / inserts (propostas, bundles, …) | Geração de eventos |
| `FleaberUserNotificationHub` | Realtime insert → badge tick |
| Mensagens → tab Notificações | Inbox completa na app |
| Home app → sino | Já existia (abre ListaConversas) |

### FleaHub (web + chrome partilhado)

- Sino discreto na topbar **só se autenticado**, entre Mensagens e Saco.
- Badge com **contagem** de não lidas (`FleaberNotificationsInbox.unreadCount`).
- Painel: lista, marcar uma / todas lidas, «Ver todas em Mensagens».
- Navegação por `kind`: chat/mensagens · saco (reservas) · encomendas · convite ajudante.
- Ficheiros: `lib/utils/fleaber_notifications_inbox.dart`, `lib/hub/widgets/fleahub_notification_center.dart`, wiring em `fleahub_site_chrome.dart`.

### Hardening

- Sem políticas RLS novas destrutivas; só cliente a ler/actualizar linhas próprias.
- Smoke produção (API): insert temporário service_role → user vê → mark read → delete cleanup. RLS cross-user = 0 linhas. Relatório: `tool/reports/fleahub_notif_center_2026-10-25/notif_lifecycle_smoke.json`.

---

## Rodapé slim + Contactos

- Rodapé: sem morada/tel/email; mantém marca, Mare Antiga, NIF, copyright, legais + link Contactos.
- Página `/fleahub/contactos`: dados de `LegalTexts` (morada, emails, telefone +351 937 475 638).
- Telefone: classificação pessoal vs profissional **não confirmada** — mantido; não substituir sem autorização.

---

## Preview local (7380)

```text
http://127.0.0.1:7380/fleahub/#/fleahub
http://127.0.0.1:7380/fleahub/#/fleahub/contactos
http://127.0.0.1:7380/fleahub/#/fleahub/ajuda
```

Pasta: `C:\Users\Casa\Desktop\FleaHub-Landing-Preview`  
Stamp: `h03-final-five-zones-2026-10-25`  
SHA `main.dart.js`: ver `fleahub/FLEAHUB_PREVIEW_STAMP.txt`  
Servidor: `tool/reports/fleahub_landing_3zones_final_2026-10-25/serve_preview_nocache.py`  
Capturas Entrega 104: `tool/reports/fleahub_entrega104_h03_final_2026-10-25/captures/`

**URL H01 preview:** `http://127.0.0.1:7380/fleahub/#/fleahub`  
**URL H02 preview:** `http://127.0.0.1:7380/fleahub/#/vendedora-prod`  
**URL H03 preview:** `http://127.0.0.1:7380/fleahub/#/vendedora-prod/live`  
Tabs H02: `?tab=diretos` · `?tab=marketplace` · `?tab=opinioes` (defeito = marketplace)  
Demo opiniões (só local): `?demo_reviews=1` · empty forçado: `?demo_reviews=0`  
**Pasta publish Hub (não FTP):** `deploy/fleaber_pt/fleahub/`

---

## Layout responsivo H01 (Entrega 93 + 94)

| Breakpoint | Comportamento |
|------------|---------------|
| &lt;720 | Chrome compacto; pesquisa por lupa; **2 tabs** Diretos/Marketplace |
| 720–1179 (incl. 1024) | Chrome compacto; pesquisa inline; 2 tabs; **sem** 2 zonas |
| ≥1180 | Desktop aprovado (3 zonas 17/62/21); rail com Diretos/Marketplace |

Menu ☰ (compacto): Como funciona, Comprar com segurança, Vender, Ajuda, Contactos.  
Auth: sino + avatar; dropdown = Mensagens, Compras/Encomendas, Reservas/Saco, Favoritos, Perfil, Terminar sessão.

### Explorar (Entrega 94)

- **Diretos:** lives activos; se vazio → gravados (`hub_lives_discovery_public`).
- **Marketplace:** `hub_products_public` + secção Lojas FleaHub (vitrines) — hubs não órfãos.
- Query `?tab=diretos|marketplace` (+ aliases legados).

---

## Publicação produção (estado)

| Item | Estado |
|------|--------|
| Build web Prod | **OK** → `deploy/fleaber_pt/fleahub/` stamp `h03-final-five-zones-2026-10-25` |
| Preview local | **Actualizado** (Entrega 104) |
| CredMan FTP | **Em falta** → **CDN não publicado** (proibido publicar sem confirmação) |
| BD / migrações | Nenhuma |
| Meta / DPD / pagamentos / reservas | **Não tocados** (regras H03 preservadas) |

---

## Auditoria funcional (resumo actualizado)

| Elemento | Estado |
|----------|--------|
| Pesquisa / discovery / nav / info pages | Funcional |
| Rodapé slim + Contactos | Funcional |
| Sino + inbox (auth) | Funcional (código + API Prod); UI auth depende sessão |
| Google Play | Não implementado (Em breve) |
| Facebook rail | Parcial (CTA login/encomendas; APIs Meta pendentes) |
| MB WAY CPI / DPD | Visual only |

---

## Ficheiros principais

- `lib/hub/widgets/fleahub_site_chrome.dart`
- `lib/hub/widgets/fleahub_notification_center.dart`
- `lib/utils/fleaber_notifications_inbox.dart`
- `lib/hub/pages/fleahub_info_pages.dart` (`FleaHubContactsPage`)
- `lib/utils/fleaber_user_notification_hub.dart` (Realtime existente)
- `lib/lista_conversas_widget.dart` (tab notificações app)
- `lib/legal/legal_texts.dart`

---

## Dossier 87 (actualizado 2026-10-25)

- Pasta: `00-fleahub-zips/0000087-fleaber-hub-web-auditoria-final-dossier/`
- Índice: `00-INDICE.md` (H01–H19)
- Inventário: `00-INVENTARIO-PAGINAS.md`
- ZIP agregado: `00-fleahub-zips/87-fleaber-hub-web-auditoria-final-dossier.zip`
- ZIPs novos: `87.15` … `87.19` (Como funciona, Segurança, Vender, Ajuda, Contactos) — capturas preview 390/768/1440
- H12/H13/H14 mantidos como especiais (infra / UI ausente / sheet)

## Entrega 92 — Validação visual H01 (2026-10-25)

- ZIP: `00-fleahub-zips/92-fleaber-h01-validacao-visual-home-20261025.zip`
- Diagnóstico (chips cortados, 1024 comprimido, cookies, sino guest) — **sem** código.

## Entrega 93 — Correcção responsiva H01 (2026-10-25)

- ZIP: `00-fleahub-zips/93-fleaber-h01-responsive-compact-20261025.zip`
- Chrome compacto ☰ + 3 tabs (histórico; substituído na 94).

## Entrega 94 — Diretos/Marketplace + topbar slim (2026-10-25)

- ZIP: `00-fleahub-zips/94-fleaber-h01-diretos-marketplace-topbar-20261025.zip`
- Stamp histórico H01 tabs + topbar slim.

## Entrega 95 — H02 perfil visual H01 (2026-10-25) — **rejeitada**

- ZIP: `00-fleahub-zips/95-fleaber-h02-perfil-visual-h01-20261025.zip`
- Motivo: cartões panorâmicos; grelhas empilhadas; opiniões no fundo; CTAs full-width no desktop.

## Entrega 96 — H02 perfil tabs + cards H01 (2026-10-25)

- ZIP: `00-fleahub-zips/96-fleaber-h02-perfil-tabs-cards-h01-20261025.zip`
- Base aprovada para Entrega 97 (decisões de layout dois eixos + 3.ª tab).

## Entrega 97 — H02 perfil final (2026-10-25)

- ZIP: `00-fleahub-zips/97-fleaber-h02-perfil-final-20261025.zip`
- Base estrutural (dois eixos + 3 tabs) aprovada para polish 98.

## Entrega 98 — H02 polish tipografia / loading / demo (2026-10-25)

- ZIP: `00-fleahub-zips/98-fleaber-h02-polish-type-loading-demo-20261025.zip`
- Stamp: `h02-polish-type-loading-demo-2026-10-25` · preview OK · **CDN não publicado**
- Tipografia: tokens `FleaHubSiteLayout` partilhados (Home = referência)
- Topbar bleed + loading claro com skeletons (sem ecrã preto)
- Mobile: identidade compacta + tabs sticky
- Demo `vendedora-prod`: artigos realistas (Unsplash + títulos/preços); `ref_code` internos mantidos
- Seguir própria conta: mensagem explícita (fix snackbar genérico em QA)
- Relatório: `tool/reports/fleahub_entrega98_polish_2026-10-25/01-RESUMO.md`
- **STOP** — não publicar sem autorização

## Entrega 99 — H01/H02 correções visuais (2026-10-25)

- ZIP: `00-fleahub-zips/99-fleaber-h01-h02-visual-corrections-20261025.zip`
- Stamp: `h01-h02-visual-corrections-2026-10-25` · preview OK · **CDN não publicado**
- Decisões aplicadas: hairline 1 px; H02 tab inicial Marketplace; H02 MP 5/6 cols (Diretos 6 intactos); H01 `MarketplaceProductCard` partilhado; mobile compacto (Seguir / Partilhar / Instalar menu / Sobre sheet); empty Opiniões centrado
- Capturas C1: só m390 auth — desktop a cargo do responsável
- Relatório: `tool/reports/fleahub_entrega99_visual_2026-10-25/01-RESUMO.md`
- Google Drive mestre: **não actualizado** (sem acesso API nesta sessão; ficheiro local **não** sincroniza sozinho)
- **STOP** — não publicar sem autorização; não iniciar entrega seguinte

## Entrega 100 — H02 acabamento visual (2026-10-25)

- ZIP: `00-fleahub-zips/100-fleaber-h02-finish-spacing-footer-back-20261025.zip`
- Stamp: `h02-finish-spacing-footer-back-2026-10-25` · preview OK · **CDN não publicado**
- Gap topbar↔conteúdo 14/8; rodapé centrado max 960; mobile Seguir|Partilhar 60/40; voltar na topbar (`popOrLanding`)
- Relatório: `tool/reports/fleahub_entrega100_h02_finish_2026-10-25/01-RESUMO.md`
- Google Drive mestre: **não actualizado** (sem acesso nesta sessão)
- **STOP** — não publicar; não iniciar outra página/entrega

## Entrega 101 — H02 validação final (2026-10-25)

- ZIP: `00-fleahub-zips/101-fleaber-h02-final-responsive-demo-reviews-20261025.zip`
- Stamp: `h02-final-responsive-demo-reviews-2026-10-25` · **CDN não publicado**
- 14 px topbar→hairline (fora do contentor); rodapé sem Contactos duplicado; 12 demo reviews locais; matriz 10 viewports (67 capturas)
- Relatório: `tool/reports/fleahub_entrega101_h02_final_2026-10-25/README.md`
- Google Drive mestre: **não actualizado** (sem acesso)
- Base para fecho visual Entrega 102.

## Entrega 102 — Fecho H02 + H03 Live light (2026-10-25)

- ZIP: `00-fleahub-zips/102-fleaber-h02-close-h03-live-light-20261025.zip`
- Base light H03; substituída visualmente pela Entrega 103 no mobile/desktop axes.

## Entrega 103 — H03 reformulação (2026-10-25)

- ZIP: `00-fleahub-zips/103-fleaber-h03-reform-player-axes-20261025.zip`
- Base player mobile + eixos; supersedida visualmente pela 104.

## Entrega 104 — H03 revisão final (2026-10-25)

- ZIP: `00-fleahub-zips/104-fleaber-h03-final-five-zones-20261025.zip`
- Stamp: `h03-final-five-zones-2026-10-25` · **CDN não publicado**
- Desktop: 5 zonas; rail ações; FB permanente (copy antiga).
- **Supersedida pela Entrega 105** (vídeo + layout + chrome).

## Entrega 105 — H03 vídeo + layout + modal/saco/FB (2026-10-26)

- ZIP: `00-fleahub-zips/105-fleaber-h03-video-layout-modals-20261026.zip`
- Vídeo Mux gravado restaurado; base para Entrega 106.

## Entrega 106 — H03 polish final (2026-10-26)

- ZIP: `00-fleahub-zips/106-fleaber-h03-polish-layout-mp-bag-20261026.zip`
- Stamp: `h03-entrega106-polish-2026-10-26` · **CDN não publicado**
- Chat largura fixa (igual live/gravado); gorjeta no rail em gravado; MP 2 cols / faixa @1280; saco contraste claro; modal foto ~45% + «Artigo sem fotografia»; FB «Compraste… / Consultar reservas».
- Inventário controlos + capturas: `tool/reports/fleahub_entrega106_h03_polish_2026-10-26/`
- Pasta local: `deploy/fleaber_pt/fleahub/`
- **STOP** — GO humano; sem CDN; **sem H04**

## Entrega 109 — H06 404 chrome claro (2026-10-26)

- ZIP: `00-fleahub-zips/109-fleaber-h06-not-found-light-20261026.zip`
- Chrome `FleaHubSiteScaffold` + Inter + `FleaberPrimaryButton`
- **Aprovada visualmente** (GO humano)

## Entrega 109.1 — H06 copy final + capturas 1440/1920 (2026-10-26)

- Copy: «A página que procuras não foi encontrada ou já não está disponível…»
- Tipografia: `GoogleFonts.inter` (mesma família H01/H02); tamanhos do título/descrição mantidos
- Capturas desktop: `tool/reports/fleahub_h06_not_found_light_2026-10-26/captures/h06_1440x900.png`, `h06_1920x1080.png`
- **H06 concluída** · **CDN / domínio ainda pendente de confirmação** · **sem H07**

## Próximos (autorização)

1. GO humano H03 (+ H01/H02 se publicar juntos) e confirmação de publicação CDN (incl. H06 quando bundlar).
2. Upload via **FTP** (File Manager web dá HTTP 403 em `main.dart.js`).
3. Confirmar telefone pessoal/profissional.
4. Teste E2E reservas Facebook com conta real.
5. Google Play / MB WAY CPI / DPD quando prontos.
6. H07 só após autorização explícita.

---

## Credenciais

Este documento **não** contém tokens, passwords ou chaves API.
