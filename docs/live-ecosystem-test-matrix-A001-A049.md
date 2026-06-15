# Matriz expandida — A001 a A049

**Área:** Preparação directo · linhagem refs · preço pendente (prep) · marketplace sync  
**Versão:** 1.0 · **2026-06-14**  
**Estado:** Fichas expandidas — **sem implementação de testes**.

Substitui a tabela compacta A001–A049 em `live-ecosystem-test-matrix.md`.

**Nota:** A004–A018, A023–A029, A038 cobrem linhagem **L1–L18**; A046–A049 cobrem preço pendente **P1–P4** (prep/go-live); A042 cobre **Z52** (merge sync não apaga marketplace). **A044** é N/A — quick edit descrição só em live (Z53).

**Queries SQL de referência:** ver Apêndice F (`Query A` / `B` / `C` em `deploy-checklist-v1.5-price-pending.md`).

---

## A001 — Entrada Novo Directo pelo sheet Criar

| Campo | Valor |
|-------|-------|
| **ID** | A001 |
| **Nome** | Sheet «Criar» → Novo Directo |
| **Pré-condições** | Vendedor autenticado; conta com permissão seller |
| **Passos** | 1. Abrir sheet Criar (Home/Mensagens/Perfil) 2. Tocar «Novo Directo» |
| **Resultado esperado** | Navega para `/prepararDirecto`; sem crash; sem duplicar bottom sheet |
| **Componentes afectados** | `fleaber_create_sheet.dart`, `nav.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | seller JWT |
| **Validar BD** | Opcional: draft criado após entrar prep (A011) |
| **Validar UI** | Sheet glass DRY; item «Novo Directo»; rota prep |
| **Risco de regressão** | Médio — entry point de todo fluxo live |
| **Dependências** | — |

---

## A002 — Preparar directo sem artigos no catálogo

| Campo | Valor |
|-------|-------|
| **ID** | A002 |
| **Nome** | Catálogo vazio bloqueia avanço |
| **Pré-condições** | Seller sem produtos `available_for_live`; prep sem refs adicionadas |
| **Passos** | 1. Preparar directo 2. Ver tab Meu Catálogo vazia 3. Tentar Continuar |
| **Resultado esperado** | UI vazia clara; Continuar bloqueado ou aviso explícito |
| **Componentes afectados** | `preparar_directo_page_widget.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | seller sem catálogo live |
| **Validar BD** | Draft pode existir; 0 `live_items` |
| **Validar UI** | Empty state; CTA Continuar disabled |
| **Risco de regressão** | Baixo |
| **Dependências** | A001 |

---

## A003 — Preparar com produtos marketplace no catálogo

| Campo | Valor |
|-------|-------|
| **ID** | A003 |
| **Nome** | Seleccionar produto marketplace no prep |
| **Pré-condições** | ≥1 produto com `available_for_live=true` |
| **Passos** | 1. Preparar 2. Tab Meu Catálogo 3. Seleccionar produto |
| **Resultado esperado** | Produto aparece no draft; qty/preço herdados do marketplace |
| **Componentes afectados** | `preparar_directo_page_widget.dart`, `live_catalog_prep_service.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro + Integration |
| **Dados necessários** | product_id marketplace |
| **Validar BD** | `live_items` draft com `product_id`; preço/qty coerentes |
| **Validar UI** | Chip/card produto no prep |
| **Risco de regressão** | Médio — TYPE A path (A029) |
| **Dependências** | A001; A011 |

---

## A004 — Adicionar referência manual (#N) sem histórico

| Campo | Valor |
|-------|-------|
| **ID** | A004 |
| **Nome** | Ref nova — sem sheet linhagem (L1) |
| **Pré-condições** | Ref #99 (ou alta) nunca usada pela seller |
| **Passos** | 1. Tab Referências 2. Long-press #99 3. Título + Guardar |
| **Resultado esperado** | Chip #99 no prep; **sem** sheet «já foi usada antes»; snack confirmação |
| **Componentes afectados** | `live_prep_refs.dart`, `live_prep_ref_details.dart`, `live_ref_lineage_prep_gate.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ref_code inédita |
| **Validar BD** | Query A: `ref_code=99`, `live_status=draft`, `logical_item_id` UUID novo |
| **Validar UI** | Sem sheet linhagem; chip preenchido |
| **Risco de regressão** | Médio — falso positivo L1 abre sheet fantasma |
| **Dependências** | A001; **L1** |

**Cobertura linhagem (L1):** ref nunca usada → fluxo directo, UUID novo.

---

## A005 — Long-press ref com histórico abre sheet linhagem

| Campo | Valor |
|-------|-------|
| **ID** | A005 |
| **Nome** | Sheet linhagem com ≥2 cards (L3) |
| **Pré-condições** | Query A: ≥2 linhagens mesmo `ref_code` (ex. #15 Puzzle + Boneca) |
| **Passos** | 1. Long-press #15 2. Guardar título 3. Ver sheet |
| **Resultado esperado** | Sheet «A referência #15 já foi usada antes»; ≥2 cards; «Continuar» + «Usar como novo artigo» |
| **Componentes afectados** | `live_ref_lineage_prep_gate.dart`, lineage preview RPC |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Manual + Maestro |
| **Dados necessários** | histórico #15 multi-linhagem (L3 seed) |
| **Validar BD** | Query A: 2+ rows #15, `logical_item_id` distintos |
| **Validar UI** | Sheet modal; cards separados; botões Continuar/Novo |
| **Risco de regressão** | Crítico — núcleo V1.5 linhagem |
| **Dependências** | A015 (L2 backfill); **L3** |

---

## A006 — Continuar linhagem Puzzle (herdar logical_item_id)

| Campo | Valor |
|-------|-------|
| **ID** | A006 |
| **Nome** | Continuar Puzzle — herda reservas abertas (L4) |
| **Pré-condições** | Puzzle #15 com reservas `pending`/`accepted`; Boneca #15 sem (L4) |
| **Passos** | 1. A005 2. Continuar — Puzzle 3. Criar directo 4. Iniciar live |
| **Resultado esperado** | Popup aviso só reservas Puzzle; draft `logical_item_id` = Puzzle; go-live OK |
| **Componentes afectados** | lineage SQL, `live_start_open_reservations_service.dart`, `live_logical_item_id_batata.sql` |
| **Prioridade** | P0 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration + Manual |
| **Dados necessários** | Query B anotada antes; Puzzle UUID conhecido |
| **Validar BD** | Query C: draft item `logical_item_id` = Puzzle; Query B inalterada pré-go-live |
| **Validar UI** | Popup origem/reservas Puzzle only |
| **Risco de regressão** | Crítico — popup errado herda Boneca (L4 FAIL) |
| **Dependências** | A005; A038; **L4** |

---

## A007 — Novo artigo na mesma ref (logical_item_id novo)

| Campo | Valor |
|-------|-------|
| **ID** | A007 |
| **Nome** | «Usar como novo artigo» — UUID novo (L5) |
| **Pré-condições** | Puzzle #15 com reservas abertas (L5) |
| **Passos** | 1. Sheet #15 2. «Usar como novo artigo» 3. Iniciar directo |
| **Resultado esperado** | Popup **sem** reservas Puzzle; novo `logical_item_id` UUID; stock pool separado |
| **Componentes afectados** | `live_logical_item_id_batata.sql`, `live_ref_lineage_prep_gate.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Puzzle reservas Query B |
| **Validar BD** | Query C: UUID ≠ Puzzle; Query B Puzzle inalterada |
| **Validar UI** | Sem popup reservas Puzzle |
| **Risco de regressão** | Crítico — L5 vs L4 confusão |
| **Dependências** | A005; A009; **L5** |

---

## A008 — Cancelar sheet linhagem sem gravar

| Campo | Valor |
|-------|-------|
| **ID** | A008 |
| **Nome** | Cancelar sheet — draft inalterado (L11) |
| **Pré-condições** | Sheet linhagem aberto (A005) |
| **Passos** | 1. Tocar Cancelar / fechar sheet 2. Query C |
| **Resultado esperado** | Fecha; draft inalterado; sem inherit; sem write fantasma |
| **Componentes afectados** | `live_ref_lineage_prep_gate.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | sheet aberto |
| **Validar BD** | Query C: mesmos registos que antes do sheet |
| **Validar UI** | Volta ao prep; chip ref estado anterior |
| **Risco de regressão** | Médio — L11 cancel grava UUID errado |
| **Dependências** | A005; A026; **L11** |

---

## A009 — Reservas antigas intactas após inherit (L6)

| Campo | Valor |
|-------|-------|
| **ID** | A009 |
| **Nome** | Reservas Puzzle não alteradas pós L4/L5 |
| **Pré-condições** | Query B baseline antes de A006 ou A007 |
| **Passos** | 1. Correr A006 ou A007 2. Query B depois 3. Comparar |
| **Resultado esperado** | Reservas Puzzle antigas: `status`, `requested_qty`, ids inalterados |
| **Componentes afectados** | `live_reservation_requests` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Query B snapshot |
| **Validar BD** | Diff zero em rows Puzzle |
| **Validar UI** | — (BD-only) |
| **Risco de regressão** | Crítico — L6 regressão altera filas históricas |
| **Dependências** | A006 ou A007; **L6** |

---

## A010 — Purge refs sessão anterior no novo prep

| Campo | Valor |
|-------|-------|
| **ID** | A010 |
| **Nome** | Novo prep limpa refs locais anteriores |
| **Pré-condições** | Prep anterior com refs guardadas localmente; sessão encerrada |
| **Passos** | 1. Novo Preparar directo (A001) 2. Ver grelha refs |
| **Resultado esperado** | Refs/chips da sessão anterior limpos; estado fresco `LiveCatalogPrepService` |
| **Componentes afectados** | `live_catalog_prep_service.dart`, `live_prep_refs.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Integration |
| **Dados necessários** | prep session anterior |
| **Validar BD** | Novo draft ou items limpos |
| **Validar UI** | Grelha sem chips stale |
| **Risco de regressão** | Médio — refs fantasma no go-live |
| **Dependências** | A001; A011 |

---

## A011 — Draft live criado no servidor (ensure_draft)

| Campo | Valor |
|-------|-------|
| **ID** | A011 |
| **Nome** | RPC `batata_ensure_draft_live` na 1.ª entrada prep |
| **Pré-condições** | Primeiro prep da sessão seller |
| **Passos** | 1. Preparar directo 2. Query lives draft |
| **Resultado esperado** | Row `lives.status=draft` associada ao seller |
| **Componentes afectados** | RPC `batata_ensure_draft_live` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | seller UUID |
| **Validar BD** | `select id, status from lives where seller_id=$s and status='draft'` |
| **Validar UI** | Prep carrega sem erro |
| **Risco de regressão** | Alto — sem draft sync falha A012 |
| **Dependências** | A001 |

---

## A012 — Migrar catálogo draft → live real no create-mux-live

| Campo | Valor |
|-------|-------|
| **ID** | A012 |
| **Nome** | `batata_migrate_live_catalog` no go-live |
| **Pré-condições** | Draft com ≥1 `live_items` |
| **Passos** | 1. Criar directo 2. create-mux-live / go-live 3. Query items |
| **Resultado esperado** | Items migrados para `live_id` final; catálogo visível no directo |
| **Componentes afectados** | `criar_directo_page_widget.dart`, migrate RPC |
| **Prioridade** | P0 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | draft com items |
| **Validar BD** | `live_items.live_id` = live final; count preservado |
| **Validar UI** | Carrossel seller/comprador com items |
| **Risco de regressão** | Crítico — catálogo vazio em live |
| **Dependências** | A011; A019; A074 (A050+) |

---

## A013 — Scheme chip + detalhes (preço, qty, título)

| Campo | Valor |
|-------|-------|
| **ID** | A013 |
| **Nome** | Detalhes ref sync para `live_items` |
| **Pré-condições** | Ref com scheme/cor preenchida |
| **Passos** | 1. Editar detalhes ref (título, preço, qty) 2. Sync / Continuar 3. Query draft |
| **Resultado esperado** | `live_items` reflectem preço/qty/título; scheme visível no chip |
| **Componentes afectados** | `live_prep_ref_details.dart`, `live_catalog_sync.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ref com scheme |
| **Validar BD** | `title`, `price`, `quantity` no draft item |
| **Validar UI** | Chip scheme; detalhes no editor |
| **Risco de regressão** | Médio — desync prep vs BD |
| **Dependências** | A004 ou A003 |

---

## A014 — Conflito ref bloqueada noutro directo activo

| Campo | Valor |
|-------|-------|
| **ID** | A014 |
| **Nome** | Gate aviso ref activa noutro live |
| **Pré-condições** | Outro live `status=live` com mesma ref bloqueada |
| **Passos** | 1. Prep com mesma ref 2. Tentar guardar/sync |
| **Resultado esperado** | Gate avisa conflito; opções claras (cancelar / prosseguir conforme regra) |
| **Componentes afectados** | `live_ref_lineage_prep_gate.dart`, blocked_qty RPC |
| **Prioridade** | P1 |
| **Automatizável** | Bot + Manual |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | 2 lives; ref partilhada |
| **Validar BD** | `blocked_qty` > 0 noutro live |
| **Validar UI** | Dialog/snackbar conflito |
| **Risco de regressão** | Alto — double-sell cross-live |
| **Dependências** | A054 (live activo); A340+ (Z82) |

---

## A015 — Backfill logical_item_id em artigos antigos (L2)

| Campo | Valor |
|-------|-------|
| **ID** | A015 |
| **Nome** | SQL A2 — UUID único por artigo histórico (L2) |
| **Pré-condições** | SQL A2 (`live_ops_hotfix_batata.sql`) aplicado |
| **Passos** | 1. Query A 2. Procurar mesma `ref_code` 2+ linhas 3. Comparar UUIDs |
| **Resultado esperado** | Sem NULL; mesma ref títulos diferentes → `logical_item_id` diferentes |
| **Componentes afectados** | `live_logical_item_id_batata.sql` |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | seller com histórico #15 Puzzle+Boneca |
| **Validar BD** | Query A: 0 NULL; UUIDs distintos por título |
| **Validar UI** | — (SQL-only) |
| **Risco de regressão** | Crítico — L2 falha quebra L3–L6 |
| **Dependências** | Deploy A2; **L2** |

---

## A016 — Preview linhagem não mistura Puzzle com Boneca (L3)

| Campo | Valor |
|-------|-------|
| **ID** | A016 |
| **Nome** | Cards sheet — stats/títulos separados (L3, L8) |
| **Pré-condições** | A005; Query A ≥2 linhagens #15 |
| **Passos** | 1. Abrir sheet #15 2. Inspeccionar cada card |
| **Resultado esperado** | Stats vendas/reservas separados por linhagem; títulos Puzzle ≠ Boneca; contexto visual completo (L8) |
| **Componentes afectados** | lineage preview RPC, `live_ref_lineage_prep_gate.dart` |
| **Prioridade** | P0 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | L3 seed |
| **Validar BD** | Preview RPC retorna 2 grupos `logical_item_id` |
| **Validar UI** | 2 cards distintos; sem merge stats |
| **Risco de regressão** | Crítico — seller escolhe linhagem errada |
| **Dependências** | A005; A015; **L3**, **L8** |

---

## A017 — Deep link `/prepararDirecto`

| Campo | Valor |
|-------|-------|
| **ID** | A017 |
| **Nome** | Deep link abre prep autenticado |
| **Pré-condições** | App instalada; seller logado |
| **Passos** | 1. Abrir `fleaber://fleaber.com/prepararDirecto` |
| **Resultado esperado** | Ecrã prep abre; sessão autenticada; sem login loop |
| **Componentes afectados** | `fleaber_deep_link_service.dart`, `nav.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | deep link URI |
| **Validar BD** | Opcional draft A011 |
| **Validar UI** | `preparar_directo_page_widget` visível |
| **Risco de regressão** | Baixo |
| **Dependências** | A001 |

---

## A018 — Helper não inicia prep como owner

| Campo | Valor |
|-------|-------|
| **ID** | A018 |
| **Nome** | Staff/helper bloqueado em Novo Directo |
| **Pré-condições** | Conta helper sem permissão criar live |
| **Passos** | 1. Login helper 2. Tentar Novo Directo / prep |
| **Resultado esperado** | Bloqueado ou redirect helper access; sem draft seller alheio |
| **Componentes afectados** | `seller_staff_service.dart`, `fleaber_create_sheet.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | helper account |
| **Validar BD** | Sem draft criado em nome owner |
| **Validar UI** | CTA oculto ou erro permissão |
| **Risco de regressão** | Médio — helper publica live não autorizado |
| **Dependências** | A370+ (helpers) |

---

## A019 — Continuar prep → Criar directo com catálogo sincronizado

| Campo | Valor |
|-------|-------|
| **ID** | A019 |
| **Nome** | Fluxo prep → criar directo v1.04 |
| **Pré-condições** | ≥1 item no prep (ref ou catálogo) |
| **Passos** | 1. Continuar no prep 2. Ver criar directo 3. Confirmar catálogo |
| **Resultado esperado** | Catálogo visível no criar; título live editável; items sync |
| **Componentes afectados** | `preparar_directo_page_widget.dart`, `criar_directo_page_widget.dart`, v1_04 path |
| **Prioridade** | P1 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | ≥1 live_item draft |
| **Validar BD** | Query C count = UI count |
| **Validar UI** | Lista catálogo; título campo |
| **Risco de regressão** | Alto — bypass prep perde catálogo |
| **Dependências** | A003 ou A004; A012 |

---

## A020 — Prep com artigo preço zero / pendente

| Campo | Valor |
|-------|-------|
| **ID** | A020 |
| **Nome** | Item sem preço no prep → «Preço pendente» live |
| **Pré-condições** | Item ref ou catálogo com preço vazio/0 |
| **Passos** | 1. Incluir no prep 2. Iniciar live 3. Comprador vê carrossel |
| **Resultado esperado** | Comprador vê «Preço pendente»; checkout bloqueado até definir (P-series) |
| **Componentes afectados** | `live_price_pending_batata.sql`, P-series, carrossel buyer |
| **Prioridade** | P0 |
| **Automatizável** | Bot + Maestro |
| **Tipo recomendado** | Bot + Manual |
| **Dados necessários** | item price null |
| **Validar BD** | `live_items.price` null/0 |
| **Validar UI** | Badge preço pendente; sem Pagar |
| **Risco de regressão** | Crítico — Stripe 0€ se gate falhar |
| **Dependências** | A046–A049; A202 (A190+) |

---

## A021 — Múltiplas refs no mesmo prep

| Campo | Valor |
|-------|-------|
| **ID** | A021 |
| **Nome** | Três refs distintas no draft |
| **Pré-condições** | Seller autenticado |
| **Passos** | 1. Adicionar #1 #2 #3 2. Sync / Continuar 3. Query C |
| **Resultado esperado** | 3 `live_items` distintos no draft/live; refs independentes |
| **Componentes afectados** | prep + `live_catalog_sync.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 3 ref_codes |
| **Validar BD** | Query C: 3 rows, `ref_code` distintos |
| **Validar UI** | 3 chips no prep |
| **Risco de regressão** | Médio |
| **Dependências** | A004 |

---

## A022 — Voltar atrás do prep sem perder crash

| Campo | Valor |
|-------|-------|
| **ID** | A022 |
| **Nome** | Navegação back prep — estado previsível |
| **Pré-condições** | Prep a meio (refs adicionadas) |
| **Passos** | 1. Back 2. Reentrar prep via A001 |
| **Resultado esperado** | Estado recuperado ou draft limpo previsível; sem crash |
| **Componentes afectados** | prep navigation, `live_catalog_prep_service.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | prep parcial |
| **Validar BD** | Draft consistente |
| **Validar UI** | Reentrada sem tela branca |
| **Risco de regressão** | Baixo |
| **Dependências** | A001 |

---

## A023 — Ref com vendas só em gravado (histórico)

| Campo | Valor |
|-------|-------|
| **ID** | A023 |
| **Nome** | Sheet mostra «Última: Gravado» + stats (L7) |
| **Pré-condições** | Gravado `ended` com vendas ref #X; sem live activo |
| **Passos** | 1. Reutilizar #X no prep 2. Long-press → sheet |
| **Resultado esperado** | Card com «Última: Gravado»; stats vendas na linhagem certa |
| **Componentes afectados** | `ref_histories_batata.sql`, lineage preview |
| **Prioridade** | P1 |
| **Automatizável** | Integration + Manual |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended live + converted orders ref #X |
| **Validar BD** | ref_histories row; vendas agregadas correctas |
| **Validar UI** | Label Gravado; contagem vendas |
| **Risco de regressão** | Médio — L7 stats wrong lineage |
| **Dependências** | A005; **L7** |

---

## A024 — Ref com reservas só em marketplace

| Campo | Valor |
|-------|-------|
| **ID** | A024 |
| **Nome** | Popup aviso origem Marketplace no go-live |
| **Pré-condições** | Reserva marketplace aberta mesmo logical pool |
| **Passos** | 1. Prep ref 2. Iniciar live 3. Confirmar aviso |
| **Resultado esperado** | Popup aviso origem **Marketplace**; seller confirma ou cancela |
| **Componentes afectados** | `live_start_open_reservations_batata.sql`, `live_start_reservations_warning_sheet.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | marketplace reservation open |
| **Validar BD** | open reservations check retorna marketplace |
| **Validar UI** | Sheet aviso com origem Marketplace |
| **Risco de regressão** | Alto — cross-pool surprise |
| **Dependências** | A006; A055 (A050+) |

---

## A025 — Ghost logical_item_id (L10)

| Campo | Valor |
|-------|-------|
| **ID** | A025 |
| **Nome** | Script L10 — detecção uso fantasma |
| **Pré-condições** | Artigo histórico sem reservas recentes |
| **Passos** | 1. `dart run tool/live_logical_item_id_check.dart` L10 (ou script doc) |
| **Resultado esperado** | PASS — uso fantasma detectado/OK; dois «Continuar» com nomes diferentes no sheet |
| **Componentes afectados** | `live_logical_item_id_check.dart`, lineage preview |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | staging seller seed |
| **Validar BD** | Script exit 0 |
| **Validar UI** | L10 manual: cards com títulos distintos (L10) |
| **Risco de regressão** | Médio |
| **Dependências** | A015; **L10** |

---

## A026 — Cancel-no-write UI (L9)

| Campo | Valor |
|-------|-------|
| **ID** | A026 |
| **Nome** | Cancelar sheet — reaparece quando relevante (L9) |
| **Pré-condições** | Sheet linhagem disponível |
| **Passos** | 1. Cancelar sheet 2. Reabrir prep / re-editar ref 3. Ver se sheet reaparece |
| **Resultado esperado** | Sheet reaparece quando histórico relevante; sem write fantasma no servidor |
| **Componentes afectados** | `live_ref_lineage_prep_gate.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ref com histórico |
| **Validar BD** | Query C estável após cancel |
| **Validar UI** | Sheet reabre em novo prep |
| **Risco de regressão** | Médio — L9 vs L13 segunda edição |
| **Dependências** | A008; **L9** |

---

## A027 — Inherit preview RPC (L16)

| Campo | Valor |
|-------|-------|
| **ID** | A027 |
| **Nome** | RPC preview — venda ~18 meses ainda relevante (L16) |
| **Pré-condições** | Staging; ref com venda antiga (~18 meses) |
| **Passos** | 1. `live_logical_item_id_check` L16 2. Long-press ref na app |
| **Resultado esperado** | PASS script; sheet ainda abre com histórico antigo |
| **Componentes afectados** | RPC preview, `ref_histories_batata.sql` |
| **Prioridade** | P1 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | old sale row |
| **Validar BD** | Preview returns lineage |
| **Validar UI** | Sheet visível para venda antiga |
| **Risco de regressão** | Médio — cutoff tempo errado |
| **Dependências** | A023; **L16** |

---

## A028 — Relevância sheet vazia (L17 / L18)

| Campo | Valor |
|-------|-------|
| **ID** | A028 |
| **Nome** | Sem sheet quando irrelevante; com sheet se reservas antigas (L17, L18) |
| **Pré-condições** | **Caso A:** ref uso antigo sem vendas/reservas (L17). **Caso B:** reservas abertas há anos (L18) |
| **Passos** | **A:** Long-press ref nova/inactiva → sem sheet. **B:** Query B reserva antiga → long-press → sheet |
| **Resultado esperado** | L17: fluxo normal sem sheet. L18: sheet **sempre** com reservas abertas antigas |
| **Componentes afectados** | lineage gate, relevância RPC |
| **Prioridade** | P2 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | refs L17 vs L18 seed |
| **Validar BD** | Query B para L18; vazio para L17 |
| **Validar UI** | Sheet on/off conforme caso |
| **Risco de regressão** | Médio — L18 miss esconde reservas críticas |
| **Dependências** | A004; A005; **L17**, **L18** |

---

## A029 — Marketplace listing no prep (TYPE A — L12)

| Campo | Valor |
|-------|-------|
| **ID** | A029 |
| **Nome** | TYPE A — toggle listar; sem sheet linhagem (L12) |
| **Pré-condições** | Produto marketplace `available_for_live` |
| **Passos** | 1. Prep → seleccionar produto 2. Toggle «Listar no marketplace» ON 3. Go-live |
| **Resultado esperado** | `list_on_marketplace=true`; checkout via `product_id`; **sem** sheet linhagem TYPE A (L12) |
| **Componentes afectados** | `batata_upsert_marketplace_live_item`, prep catálogo |
| **Prioridade** | P0 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | TYPE A product |
| **Validar BD** | `list_on_marketplace`, `product_id` ligado |
| **Validar UI** | Toggle ON; sem sheet linhagem |
| **Risco de regressão** | Alto — L12 + Z52 |
| **Dependências** | A003; A042; **L12** |

---

## A030 — Bundle/conjunto no catálogo prep (se activo)

| Campo | Valor |
|-------|-------|
| **ID** | A030 |
| **Nome** | Bundles no prep — comportamento documentado |
| **Pré-condições** | Seller com bundle activo (`batata_bundle_discounts`) |
| **Passos** | 1. Abrir prep Meu Catálogo 2. Procurar bundles |
| **Resultado esperado** | Bundles aparecem ou ficam ocultos conforme feature flag — comportamento **documentado**, sem crash |
| **Componentes afectados** | `batata_bundle_discounts`, prep catálogo |
| **Prioridade** | P3 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | bundle product |
| **Validar BD** | — |
| **Validar UI** | Lista coerente com spec |
| **Risco de regressão** | Baixo |
| **Dependências** | A003 |

---

## A031 — Tab Referências vs Meu Catálogo switch

| Campo | Valor |
|-------|-------|
| **ID** | A031 |
| **Nome** | Alternar tabs prep sem perder estado |
| **Pré-condições** | Prep aberto |
| **Passos** | 1. Tab Referências → adicionar ref 2. Tab Meu Catálogo 3. Voltar Referências |
| **Resultado esperado** | Tabs switch instantâneo; refs guardadas; catálogo independente |
| **Componentes afectados** | `preparar_directo_page_widget.dart`, tabs prep |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | seller |
| **Validar BD** | — |
| **Validar UI** | Tab indicator; conteúdo correcto |
| **Risco de regressão** | Baixo |
| **Dependências** | A001 |

---

## A032 — Editar título live no prep

| Campo | Valor |
|-------|-------|
| **ID** | A032 |
| **Nome** | Título do directo editável no prep |
| **Pré-condições** | Prep aberto |
| **Passos** | 1. Campo título live 2. Editar «Directo Teste A032» 3. Continuar |
| **Resultado esperado** | Título persiste até criar directo; pré-preenche ecrã seguinte |
| **Componentes afectados** | `preparar_directo_page_widget.dart`, draft `lives.title` |
| **Prioridade** | P2 |
| **Automatizável** | Parcial |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | — |
| **Validar BD** | `lives.title` no draft |
| **Validar UI** | Campo título visível |
| **Risco de regressão** | Baixo |
| **Dependências** | A019 |

---

## A033 — Foto produto no prep herdada

| Campo | Valor |
|-------|-------|
| **ID** | A033 |
| **Nome** | Imagem marketplace herdada no item prep |
| **Pré-condições** | Produto marketplace com foto |
| **Passos** | 1. Seleccionar produto catálogo 2. Ver thumbnail prep 3. Go-live → carrossel |
| **Resultado esperado** | Foto produto visível no prep e no live item (`image_url`) |
| **Componentes afectados** | prep catálogo, `live_items.image_url` |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | product com imagem |
| **Validar BD** | `live_items.image_url` not null |
| **Validar UI** | Thumbnail ≠ placeholder |
| **Risco de regressão** | Médio — checkout fotos (A196) |
| **Dependências** | A003 |

---

## A034 — Item duplicado mesmo produto 2x no prep

| Campo | Valor |
|-------|-------|
| **ID** | A034 |
| **Nome** | Mesmo produto adicionado duas vezes |
| **Pré-condições** | Produto marketplace |
| **Passos** | 1. Adicionar produto 2. Tentar adicionar mesmo produto outra vez |
| **Resultado esperado** | Bloqueio ou 2 linhas distintas conforme regra BATATA — comportamento consistente documentado |
| **Componentes afectados** | `live_catalog_prep_service.dart` |
| **Prioridade** | P2 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | 1 product_id |
| **Validar BD** | 1 ou 2 rows conforme spec |
| **Validar UI** | Feedback duplicado |
| **Risco de regressão** | Médio |
| **Dependências** | A003 |

---

## A035 — Remover item do prep antes de criar

| Campo | Valor |
|-------|-------|
| **ID** | A035 |
| **Nome** | Remover ref/produto do draft prep |
| **Pré-condições** | ≥2 items no prep |
| **Passos** | 1. Remover 1 item 2. Query C 3. Continuar |
| **Resultado esperado** | Item removido do draft; sync não reintroduz; go-live sem item removido |
| **Componentes afectados** | prep UI, `live_catalog_sync.dart` |
| **Prioridade** | P1 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | draft 2+ items |
| **Validar BD** | Query C count decrementado |
| **Validar UI** | Item desaparece da lista |
| **Risco de regressão** | Médio — item fantasma no live |
| **Dependências** | A021 |

---

## A036 — Prep offline / rede fraca retry

| Campo | Valor |
|-------|-------|
| **ID** | A036 |
| **Nome** | Resiliência rede no prep/sync |
| **Pré-condições** | Prep com item; rede instável |
| **Passos** | 1. Desactivar rede mid-sync 2. Reactivar 3. Retry guardar |
| **Resultado esperado** | Snackbar erro amigável; retry grava; sem corrupção draft local |
| **Componentes afectados** | `live_catalog_prep_service.dart`, sync retry |
| **Prioridade** | P2 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | device network toggle |
| **Validar BD** | Draft eventualmente consistente |
| **Validar UI** | Loading/retry states |
| **Risco de regressão** | Médio |
| **Dependências** | A013 |

---

## A037 — Seller staff context loja correcta

| Campo | Valor |
|-------|-------|
| **ID** | A037 |
| **Nome** | Prep usa catálogo da loja activa (staff) |
| **Pré-condições** | Staff multi-loja ou owner+staff |
| **Passos** | 1. Switch loja 2. Abrir prep 3. Ver catálogo |
| **Resultado esperado** | Produtos/refs da loja seleccionada; draft seller_id correcto |
| **Componentes afectados** | `seller_staff_service.dart`, prep context |
| **Prioridade** | P1 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | staff 2 lojas |
| **Validar BD** | `lives.seller_id` = loja activa |
| **Validar UI** | Catálogo correcto |
| **Risco de regressão** | Alto — vendas loja errada |
| **Dependências** | A018; A370+ |

---

## A038 — Query C draft logical_item_id pós-escolha

| Campo | Valor |
|-------|-------|
| **ID** | A038 |
| **Nome** | Draft reflecte escolha linhagem (Query C) |
| **Pré-condições** | Sheet linhagem (A005); Puzzle UUID conhecido |
| **Passos** | 1. Continuar Puzzle (A006) **ou** Novo artigo (A007) 2. Query C imediata |
| **Resultado esperado** | **A006:** `logical_item_id` = Puzzle. **A007:** UUID novo ≠ Puzzle |
| **Componentes afectados** | draft persist, lineage gate |
| **Prioridade** | P0 |
| **Automatizável** | Sim |
| **Tipo recomendado** | Integration |
| **Dados necessários** | Query C SQL; Puzzle UUID |
| **Validar BD** | Query C match escolha UI |
| **Validar UI** | — (BD gate) |
| **Risco de regressão** | Crítico — L4/L5 diagnóstico |
| **Dependências** | A006, A007; **L4**, **L5**, **L13** |

---

## A039 — Ref com caracteres especiais (#15a)

| Campo | Valor |
|-------|-------|
| **ID** | A039 |
| **Nome** | Ref alfanumérica — normalização |
| **Pré-condições** | Feature refs alfanuméricas activa |
| **Passos** | 1. Adicionar ref «15a» ou «#15a» 2. Guardar 3. Query A |
| **Resultado esperado** | Ref normalizada; sem crash; lineage gate funciona |
| **Componentes afectados** | `live_prep_refs.dart`, ref_code normalizer |
| **Prioridade** | P3 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | ref alfanumérica |
| **Validar BD** | `ref_code` consistente |
| **Validar UI** | Chip exibe ref correcta |
| **Risco de regressão** | Baixo |
| **Dependências** | A004 |

---

## A040 — Prep após live anterior sem cleanup manual

| Campo | Valor |
|-------|-------|
| **ID** | A040 |
| **Nome** | Novo prep pós-live ended — estado limpo |
| **Pré-condições** | Live anterior `ended`; seller terminou normalmente |
| **Passos** | 1. Novo Directo 2. Ver prep 3. Adicionar refs |
| **Resultado esperado** | Sem items stale do live anterior; draft novo ou purge correcto |
| **Componentes afectados** | `live_catalog_prep_service.dart`, A010 |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | ended live recente |
| **Validar BD** | Novo draft ou items limpos |
| **Validar UI** | Prep fresco |
| **Risco de regressão** | Médio |
| **Dependências** | A010; A058 (A050+) |

---

## A041 — Múltiplos drafts — só um activo

| Campo | Valor |
|-------|-------|
| **ID** | A041 |
| **Nome** | Um draft activo por seller |
| **Pré-condições** | Seller |
| **Passos** | 1. Abrir prep 2 vezes / 2 devices 3. Query drafts |
| **Resultado esperado** | ≤1 draft `status=draft` activo; reutiliza ou merge |
| **Componentes afectados** | `batata_ensure_draft_live` |
| **Prioridade** | P2 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | seller UUID |
| **Validar BD** | `count(*) draft` ≤ 1 |
| **Validar UI** | — |
| **Risco de regressão** | Médio — catálogo split |
| **Dependências** | A011 |

---

## A042 — Sync merge não apaga marketplace (Z52)

| Campo | Valor |
|-------|-------|
| **ID** | A042 |
| **Nome** | LiveCatalogSync merge preserva listing (Z52) |
| **Pré-condições** | Item TYPE A com `list_on_marketplace=true`; `product_id` marketplace |
| **Passos** | 1. Prep sync 2. Editar preço/qty 3. Re-sync 4. Query marketplace |
| **Resultado esperado** | `list_on_marketplace` mantém; `product_id` intacto; listing marketplace **não** apagado |
| **Componentes afectados** | `live_catalog_sync.dart`, `batata_upsert_marketplace_live_item`, `batata_update_live_item` |
| **Prioridade** | P0 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | TYPE A item toggle ON |
| **Validar BD** | `products` row intacta; flags marketplace unchanged |
| **Validar UI** | Toggle marketplace ainda ON |
| **Risco de regressão** | Crítico — Z52 regressão apagou listings (A349) |
| **Dependências** | A029; A349 |

**Cobertura transversal (Z52):** merge prep/live **nunca** DELETE marketplace product; shadow `checkout_product_id` separado.

---

## A043 — preserveScroll refresh prep (Z50)

| Campo | Valor |
|-------|-------|
| **ID** | A043 |
| **Nome** | Scroll prep preservado em refresh (Z50) |
| **Pré-condições** | Prep com lista longa refs/catálogo |
| **Passos** | 1. Scroll até item #40 2. Trigger refresh/sync 3. Ver posição scroll |
| **Resultado esperado** | Scroll position preservada ou restore previsível (Z50) |
| **Componentes afectados** | prep list scroll controller |
| **Prioridade** | P3 |
| **Automatizável** | Manual |
| **Tipo recomendado** | Manual |
| **Dados necessários** | lista longa |
| **Validar BD** | — |
| **Validar UI** | Sem jump to top agressivo |
| **Risco de regressão** | Baixo — UX |
| **Dependências** | A031 |

---

## A044 — Quick edit desc no prep N/A (skip)

| Campo | Valor |
|-------|-------|
| **ID** | A044 |
| **Nome** | Quick edit descrição — **N/A no prep** (só em live Z53) |
| **Pré-condições** | — |
| **Passos** | — |
| **Resultado esperado** | **SKIP / N/A** — funcionalidade «Editar rápido» descrição existe **apenas** no catálogo **em directo** (`Z53`), não no ecrã Preparar directo |
| **Componentes afectados** | — (fora de scope prep; ver A134 live catálogo) |
| **Prioridade** | P3 |
| **Automatizável** | **N/A** |
| **Tipo recomendado** | **N/A — skip documentado** |
| **Dados necessários** | — |
| **Validar BD** | — |
| **Validar UI** | Confirmar ausência de acção «editar descrição rápida» no prep (regressão negativa) |
| **Risco de regressão** | N/A |
| **Dependências** | A134 (positivo — live only); **não executar** no runner prep |

**Nota ficha:** mantida na matriz A001–A049 por completude de numeração; execução real → **A134** (vendedor em directo).

---

## A045 — Import ref scheme persistido SharedPreferences

| Campo | Valor |
|-------|-------|
| **ID** | A045 |
| **Nome** | Scheme/cores ref persistem localmente entre sessões prep |
| **Pré-condições** | Seller; scheme configurado numa ref |
| **Passos** | 1. Configurar scheme ref #20 2. Fechar app 3. Reabrir prep |
| **Resultado esperado** | Scheme/cores visíveis no chip sem re-import; SharedPreferences sync |
| **Componentes afectados** | `live_prep_refs.dart`, SharedPreferences keys |
| **Prioridade** | P1 |
| **Automatizável** | Integration |
| **Tipo recomendado** | Integration |
| **Dados necessários** | scheme JSON |
| **Validar BD** | — (local first) |
| **Validar UI** | Chip cores após restart |
| **Risco de regressão** | Baixo |
| **Dependências** | A013 |

---

## A046 — Preço pendente: reserva sem preço (P1)

| Campo | Valor |
|-------|-------|
| **ID** | A046 |
| **Nome** | Reserva permitida com artigo price 0/null (P1) |
| **Pré-condições** | Live `status=live`; item sem preço (A020); A3 edge deployada |
| **Passos** | 1. Seller mostra artigo 2. Buyer carrossel → Reservar 3. Query reservas |
| **Resultado esperado** | Reserva `pending` criada; chat «reservou»; **sem** erro preço |
| **Componentes afectados** | `createRequest`, carrossel, P1 series |
| **Prioridade** | P0 |
| **Automatizável** | Bot |
| **Tipo recomendado** | Bot |
| **Dados necessários** | buyer JWT; item price null |
| **Validar BD** | `live_reservation_requests.status=pending`; `live_items.price` null/0 |
| **Validar UI** | Reserva OK; modal sem preço |
| **Risco de regressão** | Crítico — bloqueio errado P1 |
| **Dependências** | A020; **P1** |

---

## A047 — Preço pendente: seller define preço (P2/P4)

| Campo | Valor |
|-------|-------|
| **ID** | A047 |
| **Nome** | Seller define preço — grava BD + shadow (P2 label / P4 acção) |
| **Pré-condições** | A046 — reserva existente; item ainda sem preço |
| **Passos** | 1. Seller catálogo live → Editar rápido **ou** Definir preço € 2. Preço 12,00 → Guardar 3. SQL item |
| **Resultado esperado** | `live_items.price=12`; shadow `checkout_product_id` sync se existir; card vermelho resolve |
| **Componentes afectados** | quick edit live catálogo, `live_price_pending_batata.sql` |
| **Prioridade** | P0 |
| **Automatizável** | Bot |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_item_id |
| **Validar BD** | `li.price=12`; `shadow_price=12` se shadow |
| **Validar UI** | 12,00 € no card seller |
| **Risco de regressão** | Crítico — P4 gravação falha |
| **Dependências** | A046; A048; **P4** (acção); **P2** (estado saco buyer) |

---

## A048 — Preço pendente: broadcast chat (P3)

| Campo | Valor |
|-------|-------|
| **ID** | A048 |
| **Nome** | Chat sistema «preço definido» após P4 (P3) |
| **Pré-condições** | A047 completo — preço definido |
| **Passos** | 1. Seller grava preço 2. Buyer vê chat público 3. (Opcional) notificação |
| **Resultado esperado** | Msg sistema humanizada «preço definido» / equivalente; compradores informados |
| **Componentes afectados** | price broadcast RPC, `LiveSystemChatHumanizer` |
| **Prioridade** | P0 |
| **Automatizável** | Bot + Manual |
| **Tipo recomendado** | Bot |
| **Dados necessários** | live_id; item com preço novo |
| **Validar BD** | `live_messages` system row |
| **Validar UI** | Chat linha visível buyer |
| **Risco de regressão** | Médio — spam P15 debounce |
| **Dependências** | A047; A283; **P3** |

---

## A049 — Preço pendente: checkout bloqueado até preço (P4)

| Campo | Valor |
|-------|-------|
| **ID** | A049 |
| **Nome** | Saco sem Pagar até preço; desbloqueia após P4 (P4 gate) |
| **Pré-condições** | A046 reserva; **antes** A047: sem preço. **Depois** A047: com preço |
| **Passos** | **Fase 1:** Buyer saco → «Preço a definir» → sem Pagar. **Fase 2:** Após A047 → reabrir saco → Pagar activo |
| **Resultado esperado** | Fase 1: sem Stripe; label cinzento. Fase 2: preço teal + CTA Pagar (liga A227) |
| **Componentes afectados** | `live_bag_sheet.dart`, `live_item_price_gate.dart`, P4 |
| **Prioridade** | P0 |
| **Automatizável** | Maestro |
| **Tipo recomendado** | Maestro |
| **Dados necessários** | buyer; reserva pending/accepted |
| **Validar BD** | price null → sem order; price 12 → payable |
| **Validar UI** | «Preço a definir» vs «12,00 €» + Pagar |
| **Risco de regressão** | Crítico — Pagar 0€ (A202) |
| **Dependências** | A046, A047; A202; A227; **P4** |

**Cobertura transversal (P1–P4):** P1 reserva OK → P2 saco label → P3 impossível pagar → P4 seller define → saco desbloqueia.

---

## Apêndice A — Resumo A001–A049

| Bloco | IDs | Foco |
|-------|-----|------|
| Entrada prep | A001–A003 | Criar sheet, catálogo vazio/cheio |
| Linhagem refs | A004–A009, A015–A016, A023, A025–A028, A038 | L1–L18, Query A/B/C |
| Draft & sync | A010–A014, A019, A021, A035, A040–A042 | ensure_draft, migrate, Z52 |
| Navegação & aux | A017–A018, A022, A031–A037, A039, A041, A043, A045 | deep link, staff, scroll |
| Preço pendente | A020, A046–A049 | P1–P4 prep→live |
| N/A / P3 baixa | A030, A044 | bundles, quick edit skip |
| Marketplace TYPE A | A029, A042 | L12 + Z52 |

**Total fichas:** 49 (A001–A049), incluindo **1 skip** (A044).

### Temas transversais (sem ID próprio — cobertos nas fichas acima)

| Tema | Fichas principais |
|------|-------------------|
| Linhagem L1–L18 | A004–A009, A015–A016, A023, A025–A029, A038 |
| Query A / B / C | A005, A006, A007, A009, A015, A038, A046 |
| Preço pendente P1–P4 | A020, A046–A049 |
| Marketplace sync Z52 | A029, A042 |
| TYPE A vs live_only | A003, A029, A042 |
| Draft lifecycle | A010, A011, A040, A041 |
| Cross-session reservas | A006, A007, A009, A024, A028 |

---

## Apêndice B — Mapeamento linhagem L1–L18 → A

| Legado | Objetivo curto | Ficha(s) A |
|--------|----------------|------------|
| **L1** | Ref nova — sem sheet | A004 |
| **L2** | Backfill UUID antigos | A015 |
| **L3** | Sheet ≥2 linhagens separadas | A005, A016 |
| **L4** | Continuar Puzzle — herda reservas | A006, A038 |
| **L5** | Novo artigo — UUID novo | A007, A038 |
| **L6** | Reservas antigas intactas | A009 |
| **L7** | Stats gravado na linhagem certa | A023 |
| **L8** | Cards contexto visual completo | A016 |
| **L9** | Cancel — sheet reaparece | A026, A008 |
| **L10** | Dois Continuar nomes diferentes | A025 |
| **L11** | Cancel — sem write servidor | A008 |
| **L12** | TYPE A — sem sheet linhagem | A029 |
| **L13** | 2.ª edição mesmo draft — sem re-sheet | A038, A026 |
| **L14** | Checkout artigo novo não estraga Puzzle | A007, A009 (+ A206+) |
| **L15** | Regressão chat directo/gravado | — (A280+) |
| **L16** | Venda ~18 meses — sheet abre | A027 |
| **L17** | Uso antigo sem vendas — sem sheet | A028 (caso A) |
| **L18** | Reservas abertas antigas — sheet | A028 (caso B) |

---

## Apêndice C — Preço pendente P1–P4 → A

| Legado | Objetivo curto | Ficha A | Validação chave |
|--------|----------------|---------|-----------------|
| **P1** | Reservar sem preço permitido | A046 | Reserva `pending`; price null |
| **P2** | Saco «Preço a definir»; sem Pagar | A049 (fase 1) | Label cinzento; botão ausente |
| **P3** | Impossível pagar / Stripe bloqueado | A049 (fase 1), A202 | Sem checkout 0€ |
| **P4** | Seller define preço | A047 | `live_items.price` > 0 |
| *(P5)* | Pagar activo pós-preço | A049 (fase 2), A227 | CTA Pagar enabled |

**Deploy mínimo P-series:** SQL A2 + edge A3 + APK seller/comprador (ver checklist v1.5).

---

## Apêndice D — Z52 marketplace sync

| Cenário | Ficha | Assert |
|---------|-------|--------|
| Toggle marketplace no prep | A029 | `list_on_marketplace=true` |
| Re-sync prep não apaga listing | A042 | product row intacta |
| Regressão pós-live sync | A349 (A280+) | flags unchanged |
| Shadow checkout separado | A047, A225 | `checkout_product_id` ≠ apagar marketplace |

**Regra Z52:** qualquer `LiveCatalogSync` merge **preserva** `products` marketplace; altera apenas campos live/shadow autorizados.

---

## Apêndice E — P0 desta faixa (18)

| ID | Nome curto |
|----|------------|
| A005 | Sheet linhagem L3 |
| A006 | Continuar Puzzle L4 |
| A007 | Novo artigo L5 |
| A009 | Reservas intactas L6 |
| A012 | Migrate catálogo go-live |
| A015 | Backfill L2 |
| A016 | Preview não mistura L3 |
| A020 | Preço pendente prep |
| A029 | Marketplace TYPE A L12 |
| A038 | Query C pós-escolha |
| A042 | Z52 merge sync |
| A046 | P1 reserva sem preço |
| A047 | P4 seller define preço |
| A048 | P3 broadcast chat |
| A049 | P4 gate saco/checkout |

---

## Apêndice F — Queries SQL (prep / linhagem)

Substituir `SELLER_UUID` / `BUYER_UUID` / `LIVE_ITEM_UUID` conforme checklist v1.5.

**Query A — artigos live_only seller** (L2, L3, L4, L5, L6, L13…)

```sql
select li.id, li.ref_code, li.title, li.logical_item_id, li.price,
       li.live_id, l.status as live_status, li.created_at
from public.live_items li
join public.lives l on l.id = li.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and li.item_kind = 'live_only'
order by li.created_at desc limit 30;
```

**Query B — reservas em aberto** (L4, L6, L18, P1…)

```sql
select r.id, r.status, r.requested_qty, r.live_item_id,
       li.ref_code, li.title, li.logical_item_id, r.created_at
from public.live_reservation_requests r
join public.live_items li on li.id = r.live_item_id
join public.lives l on l.id = r.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and r.status in ('pending', 'accepted')
  and coalesce(r.notes, '') not ilike '%bag_removed%'
order by r.created_at desc limit 30;
```

**Query C — draft actual** (L4, L5, L11, L13, A038)

```sql
select li.id, li.title, li.ref_code, li.logical_item_id, li.price, l.id as live_id
from public.live_items li
join public.lives l on l.id = li.live_id
where coalesce(l.seller_id, l.vendedor_id) = 'SELLER_UUID'
  and l.status = 'draft'
order by li.updated_at desc;
```

---

## Apêndice G — Top 10 a automatizar primeiro (prep)

| # | ID | Porquê | Tipo |
|---|-----|--------|------|
| 1 | A015 | L2 backfill — base de toda linhagem | Integration |
| 2 | A038 | Query C — diagnóstico L4/L5 | Integration |
| 3 | A042 | Z52 — regressão apagou listings | Integration |
| 4 | A007 | L5 UUID novo — Integration pura | Integration |
| 5 | A009 | L6 integridade reservas | Integration |
| 6 | A046 | P1 — bot reserva sem preço | Bot |
| 7 | A047 | P4 — bot define preço | Bot |
| 8 | A011 | ensure_draft — blocker sync | Integration |
| 9 | A012 | migrate catálogo go-live | Integration |
| 10 | A049 | P4 gate saco — Maestro smoke | Maestro |

---

## Apêndice H — Classificação por tipo (faixa completa)

| Tipo | IDs |
|------|-----|
| **Unit** | — (faixa prep/UI) |
| **Integration** | A003, A007, A009–A011, A012–A013, A015, A021, A023–A025, A027–A028, A034, A035, A040–A042, A045, A038 |
| **Bot** | A020, A046, A047, A048 |
| **Maestro** | A001–A002, A004, A008, A017, A019, A022, A031–A032, A035, A049 |
| **Manual** | A005–A006, A016, A018, A026, A029–A030, A033, A036–A037, A039, A043 |
| **N/A / Skip** | A044 |
| **Híbrido** | A003 (Maestro+Integration), A005 (Manual+Maestro), A006 (Integration+Manual), A020 (Bot+Manual), A048 (Bot+Manual), A014 (Bot+Manual) |

---

## Apêndice I — Riscos críticos (levantamento)

1. **Linhagem L4/L5 (A006–A007, A038):** escolha errada no sheet → popup reservas incorrectas ou stock pool partilhado indevidamente.
2. **L6 (A009):** inherit altera reservas históricas — regressão SQL/RPC crítica.
3. **L2 backfill (A015):** NULL `logical_item_id` → sheet/preview quebrados.
4. **Z52 merge (A042):** sync prep apaga `products` marketplace — perda revenue listing.
5. **P1–P4 (A046–A049):** reserva bloqueada ou Stripe 0€ se price gate omitido.
6. **Migrate catálogo (A012):** go-live sem items — directo vazio.
7. **TYPE A L12 (A029):** sheet linhagem abre indevidamente em produto marketplace.
8. **Staff context (A037):** prep catálogo loja errada.
9. **Conflito ref activa (A014):** double-sell mesma ref dois lives.
10. **A044 scope:** não confundir com A134 — quick edit desc **só live**; teste prep é regressão negativa apenas.

---

*Fim A001–A049. Fichas A050+ em `live-ecosystem-test-matrix-A050-A079.md`.*
