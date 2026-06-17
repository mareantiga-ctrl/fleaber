# Lista de testes Fleaber — linguagem simples

Gerado: 2026-06-17T11:25:28

## O que é isto?

São **429 verificações** da app Fleaber (mais 21 da bateria T, descrita no fim). Cada uma diz: **o que fazes**, **o que deve acontecer se estiver bem**, **o que a última corrida disse**, e **o que a auditoria dos logs e prints confirmou**.

### Significado dos estados

| Símbolo | Significado |
|---------|-------------|
| ✅ Passou | Correu e deu como esperado |
| ❌ Falhou | Correu mas algo correu mal (muitas vezes o robô de teste, não necessariamente a app) |
| 👤 Manual | Só uma pessoa pode confirmar (ex. pagar com cartão real) |
| ⏸️ Não correu | Faltou preparar dados (ex. criar um directo de teste) |
| 🚫 Bloqueado | Não dá para testar ainda por dependência em falta |
| ⏳ Por fazer | Ainda não foi executado na última corrida completa |
| ⚠️ Passou com aviso | Auditoria viu o essencial mas há pormenores (ex. texto técnico no ecrã) |

### Tipos de falha (quando ❌)

| Tipo | Significado |
|------|-------------|
| 🔧 **INFRA** | Emulador, login do robô, timeout, app não abre, ou teste saltado (dedupe) |
| 🧭 **NAVEGAÇÃO** | Robô não encontrou botão/ecrã — tu confirmaste que manualmente funciona |
| 🗄️ **DADOS/BD** | Dados de teste em falta ou base de dados não bate certo com o esperado |
| 🐛 **BUG FUNCIONAL REAL** | A app parece mesmo estar errada (confirmado em logs/dados, não só no robô) |

### Quantos testes são mesmo manuais?

**Importante:** na corrida completa de **16 Jun** apareciam **131** testes com estado «manual». Isso **não** quer dizer que tens 131 testes para fazer à mão — na altura o robô **nem tentava correr** muitos deles (faltavam adaptadores automáticos).

| Situação | Número |
|----------|--------|
| Testes com robô automático atribuído hoje | **405** |
| Testes que **sempre** precisam de pessoa (checkpoint manual) | **23** |
| Testes guiados (câmara, Stripe ao vivo…) | **1** |
| Total | 429 |

**Garantia actual (política fixa):** todos os testes excepto os **24** da lista explícita (`tool/regression/automation_policy.dart`) têm robô atribuído no `manifest.json`. O comando `dart run tool/regression/coverage_report.dart` falha se algum ficar sem adapter ou se o número sair de **405 automáticos + 24 manuais/guiados**.

**Testes manuais de verdade hoje: 24** (23 manuais + 1 guiado). Lista completa na secção [Só manuais](#só-manuais).

### Resumo da última corrida completa (429 testes, 16 Jun)

- ✅ Passou: 268
- ❌ Falhou: 29
- 👤 Marcado manual (robô nem tentou): 131
- 🚫 Bloqueado: 1
- ⏸️ Não correu (config): 0

### Resumo actualizado (A001–A035 corrida 17 Jun + resto da corrida 16 Jun)

- ✅ Passou: 265
- ❌ Falhou: 34
- 👤 Manual na corrida: 127
- 🚫 Bloqueado: 1
- ⏸️ Não correu (config): 2
- ⏳ Por fazer: 0

### Resumo da auditoria (logs e prints)

- Testes com auditoria de logs/prints: 52
- ✅ Confirmado passou: 25
- ⚠️ Passou com aviso: 13
- ❌ Confirmado falhou: 14
- (Restantes 429 − 52 ainda sem auditoria automática)

### Resumo de falhas por tipo (corrida + auditoria)

- 🔧 **INFRA**: 15 teste(s)
- 🧭 **NAVEGAÇÃO**: 19 teste(s)
- 🗄️ **DADOS/BD**: 0 teste(s)
- 🐛 **BUG FUNCIONAL REAL**: 0 teste(s)

**Bugs funcionais reais confirmados: 0** — nenhuma falha ficou como 🐛 BUG REAL depois de cruzar corrida com auditoria.

**Corrida falhou mas auditoria confirmou OK** (10): A051, A071, A089, A090, A094, A095, A121, A271, A279, A398

**Prep Maestro (NAVEGAÇÃO):** A001, A002, A004, A008, A017, A019, A022, A026, A029, A030, A031, A032, A033, A035
**Infra/dedupe/lançar app:** A051, A054, A061, A066, A071, A079, A094, A095, A121, A122, A151, A188, A189, A272, A324

---

## Só manuais (24 testes)

Estes **não têm robô fiável** — precisam de ti (ou de hardware/contas especiais). Os outros 405 têm automação atribuída; se falharem, muitas vezes é problema do emulador ou do Maestro, não da app.

#### A018 — Staff/helper bloqueado em Novo Directo

**Porque é manual:** Conta de ajudante sem permissão para criar directo — tens de ver se o botão aparece bloqueado.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A037 — Prep usa catálogo da loja activa (staff)

**Porque é manual:** Staff com loja activa diferente do dono — precisa login de colaborador real.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A044 — Quick edit descrição — **N/A no prep** (só em live Z53)

**Porque é manual:** Edição rápida de descrição só existe **durante a live**, não no ecrã de preparar.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A064 — Publish RTMP alternativo (se flag activa)

**Porque é manual:** Publicação RTMP alternativa — depende de flag especial e stream real.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A065 — UX quando câmara recusada

**Porque é manual:** Tens de **recusar a permissão da câmara** no Android e ver a mensagem de erro.

**Última corrida:** 🚫 Bloqueado — Depende de outro teste ou funcionalidade em falta

#### A070 — Staff helper não inicia directo próprio

**Porque é manual:** Ajudante a tentar iniciar directo próprio — permissões de equipa.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A072 — Orientação landscape no encode/view

**Porque é manual:** Rodar o telemóvel para paisagem durante encode/visualização.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A073 — Modo diagnóstico preview (debug)

**Porque é manual:** Modo diagnóstico de preview — só em build de debug.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A076 — Timeout create-mux — UX de espera/erro

**Porque é manual:** Esperar timeout da API Mux — demora real (minutos) difícil no robô.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A077 — Segundo device não publica em paralelo

**Porque é manual:** Precisa de **dois telemóveis** — o segundo não pode publicar em paralelo.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A078 — Helper HLS + painel operações

**Porque é manual:** Ajudante a ver HLS + painel de operações — sessão helper real.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A098 — Helper/staff **sem** permissão não aceita reservas

**Porque é manual:** Ajudante **sem** permissão a tentar aceitar reservas — deve ser bloqueado.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A099 — Owner seller ignora restrições staff context

**Porque é manual:** Dono da loja ignora restrições de staff — comparar duas contas.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A168 — Retomar app após Stripe — reconcile pending

**Porque é manual:** Voltar à app depois de ir ao Stripe pagar — fluxo sandbox real.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A169 — Playback HLS live com latência reduzida

**Porque é manual:** Qualidade e latência do vídeo HLS ao vivo — perceptível a olho humano.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A205 — URL checkout Stripe ao confirmar pagamento

**Porque é manual:** Abrir a página de checkout Stripe no browser ao confirmar pagamento.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A207 — Cancelar checkout Stripe mantém reserva

**Porque é manual:** Cancelar no ecrã Stripe e confirmar que a reserva se mantém na app.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A372 — Painel operacional helper sobre HLS (sem câmara)

**Porque é manual:** Painel operacional do ajudante sobre HLS **sem usar a câmara**.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A379 — Helper sem editar anúncios — catálogo live read-only

**Porque é manual:** Ajudante não pode editar anúncios — catálogo só leitura na live.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A383 — Helper sem ver saldo/wallet/pagamentos

**Porque é manual:** Ajudante não deve ver saldo, wallet nem pagamentos.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A384 — Helper não gere outros colaboradores

**Porque é manual:** Ajudante não pode gerir outros colaboradores.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A388 — Seller muda perms — helper vê gate após refresh

**Porque é manual:** Dono muda permissões — ajudante vê portas bloqueadas após refrescar.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A399 — Checkout com autenticação forte Stripe

**Porque é manual:** Pagamento com autenticação forte Stripe (3D Secure).

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

#### A410 — Pós-Stripe sem rede — context pending sobrevive

**Porque é manual:** Depois do Stripe, cortar a rede e ver se o estado pendente sobrevive.

**Última corrida:** 👤 Manual — Robô não corre — checkpoint manual

---

## Os 429 testes (A001 a A429)

### Preparar directo (antes de ir ao ar)

#### A001 — Sheet «Criar» → Novo Directo

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir sheet Criar (Home/Mensagens/Perfil) 2. Tocar «Novo Directo»

**Se estiver bem:** Navega para `/prepararDirecto`; sem crash; sem duplicar bottom sheet

#### A002 — Catálogo vazio bloqueia avanço

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Preparar directo 2. Ver tab Meu Catálogo vazia 3. Tentar Continuar

**Se estiver bem:** UI vazia clara; Continuar bloqueado ou aviso explícito

#### A003 — Seleccionar produto marketplace no prep

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ✅ Confirmado passou — BD+integration

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Preparar 2. Tab Meu Catálogo 3. Seleccionar produto

**Se estiver bem:** Produto aparece no draft; qty/preço herdados do marketplace

#### A004 — Ref nova — sem sheet linhagem (L1)

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Tab Referências 2. Long-press #99 3. Título + Guardar

**Se estiver bem:** Chip #99 no prep; **sem** sheet «já foi usada antes»; snack confirmação

#### A005 — Sheet linhagem com ≥2 cards (L3)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ✅ Confirmado passou — unit

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Long-press #15 2. Guardar título 3. Ver sheet

**Se estiver bem:** Sheet «A referência #15 já foi usada antes»; ≥2 cards; «Continuar» + «Usar como novo artigo»

#### A006 — Continuar Puzzle — herda reservas abertas (L4)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. A005 2. Continuar — Puzzle 3. Criar directo 4. Iniciar live

**Se estiver bem:** Popup aviso só reservas Puzzle; draft `logical_item_id` = Puzzle; go-live OK

#### A007 — «Usar como novo artigo» — UUID novo (L5)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Sheet #15 2. «Usar como novo artigo» 3. Iniciar directo

**Se estiver bem:** Popup **sem** reservas Puzzle; novo `logical_item_id` UUID; stock pool separado

#### A008 — Cancelar sheet — draft inalterado (L11)

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Tocar Cancelar / fechar sheet 2. Query C

**Se estiver bem:** Fecha; draft inalterado; sem inherit; sem write fantasma

#### A009 — Reservas Puzzle não alteradas pós L4/L5

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Correr A006 ou A007 2. Query B depois 3. Comparar

**Se estiver bem:** Reservas Puzzle antigas: `status`, `requested_qty`, ids inalterados

#### A010 — Novo prep limpa refs locais anteriores

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Novo Preparar directo (A001) 2. Ver grelha refs

**Se estiver bem:** Refs/chips da sessão anterior limpos; estado fresco `LiveCatalogPrepService`

#### A011 — RPC `batata_ensure_draft_live` na 1.ª entrada prep

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Preparar directo 2. Query lives draft

**Se estiver bem:** Row `lives.status=draft` associada ao seller

#### A012 — `batata_migrate_live_catalog` no go-live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Criar directo 2. create-mux-live / go-live 3. Query items

**Se estiver bem:** Items migrados para `live_id` final; catálogo visível no directo

#### A013 — Detalhes ref sync para `live_items`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Editar detalhes ref (título, preço, qty) 2. Sync / Continuar 3. Query draft

**Se estiver bem:** `live_items` reflectem preço/qty/título; scheme visível no chip

#### A014 — Gate aviso ref activa noutro live

**Corrida:** ⏸️ Não correu — Faltou criar o directo de teste na base de dados antes de correr

**Auditoria (logs/prints):** ✅ Confirmado passou — BD+bot

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Prep com mesma ref 2. Tentar guardar/sync

**Se estiver bem:** Gate avisa conflito; opções claras (cancelar / prosseguir conforme regra)

#### A015 — SQL A2 — UUID único por artigo histórico (L2)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ✅ Confirmado passou — BD+integration

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Query A 2. Procurar mesma `ref_code` 2+ linhas 3. Comparar UUIDs

**Se estiver bem:** Sem NULL; mesma ref títulos diferentes → `logical_item_id` diferentes

#### A016 — Cards sheet — stats/títulos separados (L3, L8)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ✅ Confirmado passou — unit

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir sheet #15 2. Inspeccionar cada card

**Se estiver bem:** Stats vendas/reservas separados por linhagem; títulos Puzzle ≠ Boneca; contexto visual completo (L8)

#### A017 — Deep link abre prep autenticado

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir `fleaber://fleaber.com/prepararDirecto`

**Se estiver bem:** Ecrã prep abre; sessão autenticada; sem login loop

#### A018 — Staff/helper bloqueado em Novo Directo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Conta de ajudante sem permissão para criar directo — tens de ver se o botão aparece bloqueado.

**O que fazes:** 1. Login helper 2. Tentar Novo Directo / prep

**Se estiver bem:** Bloqueado ou redirect helper access; sem draft seller alheio

#### A019 — Fluxo prep → criar directo v1.04

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Continuar no prep 2. Ver criar directo 3. Confirmar catálogo

**Se estiver bem:** Catálogo visível no criar; título live editável; items sync

#### A020 — Item sem preço no prep → «Preço pendente» live

**Corrida:** ⏸️ Não correu — Faltou criar o directo de teste na base de dados antes de correr

**Auditoria (logs/prints):** ✅ Confirmado passou — BD+bot

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Incluir no prep 2. Iniciar live 3. Comprador vê carrossel

**Se estiver bem:** Comprador vê «Preço pendente»; checkout bloqueado até definir (P-series)

#### A021 — Três refs distintas no draft

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Adicionar #1 #2 #3 2. Sync / Continuar 3. Query C

**Se estiver bem:** 3 `live_items` distintos no draft/live; refs independentes

#### A022 — Navegação back prep — estado previsível

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Back 2. Reentrar prep via A001

**Se estiver bem:** Estado recuperado ou draft limpo previsível; sem crash

#### A023 — Sheet mostra «Última: Gravado» + stats (L7)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Reutilizar #X no prep 2. Long-press → sheet

**Se estiver bem:** Card com «Última: Gravado»; stats vendas na linhagem certa

#### A024 — Popup aviso origem Marketplace no go-live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep ref 2. Iniciar live 3. Confirmar aviso

**Se estiver bem:** Popup aviso origem **Marketplace**; seller confirma ou cancela

#### A025 — Script L10 — detecção uso fantasma

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. `dart run tool/live_logical_item_id_check.dart` L10 (ou script doc)

**Se estiver bem:** PASS — uso fantasma detectado/OK; dois «Continuar» com nomes diferentes no sheet

#### A026 — Cancelar sheet — reaparece quando relevante (L9)

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Cancelar sheet 2. Reabrir prep / re-editar ref 3. Ver se sheet reaparece

**Se estiver bem:** Sheet reaparece quando histórico relevante; sem write fantasma no servidor

#### A027 — RPC preview — venda ~18 meses ainda relevante (L16)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. `live_logical_item_id_check` L16 2. Long-press ref na app

**Se estiver bem:** PASS script; sheet ainda abre com histórico antigo

#### A028 — Sem sheet quando irrelevante; com sheet se reservas antigas (L17, L18)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** **A:** Long-press ref nova/inactiva → sem sheet. **B:** Query B reserva antiga → long-press → sheet

**Se estiver bem:** L17: fluxo normal sem sheet. L18: sheet **sempre** com reservas abertas antigas

#### A029 — TYPE A — toggle listar; sem sheet linhagem (L12)

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Prep → seleccionar produto 2. Toggle «Listar no marketplace» ON 3. Go-live

**Se estiver bem:** `list_on_marketplace=true`; checkout via `product_id`; **sem** sheet linhagem TYPE A (L12)

#### A030 — Bundles no prep — comportamento documentado

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir prep Meu Catálogo 2. Procurar bundles

**Se estiver bem:** Bundles aparecem ou ficam ocultos conforme feature flag — comportamento **documentado**, sem crash

#### A031 — Alternar tabs prep sem perder estado

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Tab Referências → adicionar ref 2. Tab Meu Catálogo 3. Voltar Referências

**Se estiver bem:** Tabs switch instantâneo; refs guardadas; catálogo independente

#### A032 — Título do directo editável no prep

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Campo título live 2. Editar «Directo Teste A032» 3. Continuar

**Se estiver bem:** Título persiste até criar directo; pré-preenche ecrã seguinte

#### A033 — Imagem marketplace herdada no item prep

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Seleccionar produto catálogo 2. Ver thumbnail prep 3. Go-live → carrossel

**Se estiver bem:** Foto produto visível no prep e no live item (`image_url`)

#### A034 — Mesmo produto adicionado duas vezes

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Adicionar produto 2. Tentar adicionar mesmo produto outra vez

**Se estiver bem:** Bloqueio ou 2 linhas distintas conforme regra BATATA — comportamento consistente documentado

#### A035 — Remover ref/produto do draft prep

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ❌ Confirmado falhou — Maestro exit=1; UX+Maestro

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Remover 1 item 2. Query C 3. Continuar

**Se estiver bem:** Item removido do draft; sync não reintroduz; go-live sem item removido

#### A036 — Resiliência rede no prep/sync

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Maestro (robô no telemóvel))*

**O que fazes:** 1. Desactivar rede mid-sync 2. Reactivar 3. Retry guardar

**Se estiver bem:** Snackbar erro amigável; retry grava; sem corrupção draft local

#### A037 — Prep usa catálogo da loja activa (staff)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Staff com loja activa diferente do dono — precisa login de colaborador real.

**O que fazes:** 1. Switch loja 2. Abrir prep 3. Ver catálogo

**Se estiver bem:** Produtos/refs da loja seleccionada; draft seller_id correcto

#### A038 — Draft reflecte escolha linhagem (Query C)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Continuar Puzzle (A006) **ou** Novo artigo (A007) 2. Query C imediata

**Se estiver bem:** **A006:** `logical_item_id` = Puzzle. **A007:** UUID novo ≠ Puzzle

#### A039 — Ref alfanumérica — normalização

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Maestro (robô no telemóvel))*

**O que fazes:** 1. Adicionar ref «15a» ou «#15a» 2. Guardar 3. Query A

**Se estiver bem:** Ref normalizada; sem crash; lineage gate funciona

#### A040 — Novo prep pós-live ended — estado limpo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Novo Directo 2. Ver prep 3. Adicionar refs

**Se estiver bem:** Sem items stale do live anterior; draft novo ou purge correcto

#### A041 — Um draft activo por seller

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir prep 2 vezes / 2 devices 3. Query drafts

**Se estiver bem:** ≤1 draft `status=draft` activo; reutiliza ou merge

#### A042 — LiveCatalogSync merge preserva listing (Z52)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep sync 2. Editar preço/qty 3. Re-sync 4. Query marketplace

**Se estiver bem:** `list_on_marketplace` mantém; `product_id` intacto; listing marketplace **não** apagado

#### A043 — Scroll prep preservado em refresh (Z50)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Maestro (robô no telemóvel))*

**O que fazes:** 1. Scroll até item #40 2. Trigger refresh/sync 3. Ver posição scroll

**Se estiver bem:** Scroll position preservada ou restore previsível (Z50)

#### A044 — Quick edit descrição — **N/A no prep** (só em live Z53)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Edição rápida de descrição só existe **durante a live**, não no ecrã de preparar.

**O que fazes:** —

**Se estiver bem:** **SKIP / N/A** — funcionalidade «Editar rápido» descrição existe **apenas** no catálogo **em directo** (`Z53`), não no ecrã Preparar directo

#### A045 — Scheme/cores ref persistem localmente entre sessões prep

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Configurar scheme ref #20 2. Fechar app 3. Reabrir prep

**Se estiver bem:** Scheme/cores visíveis no chip sem re-import; SharedPreferences sync

#### A046 — Reserva permitida com artigo price 0/null (P1)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Seller mostra artigo 2. Buyer carrossel → Reservar 3. Query reservas

**Se estiver bem:** Reserva `pending` criada; chat «reservou»; **sem** erro preço

#### A047 — Seller define preço — grava BD + shadow (P2 label / P4 acção)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Seller catálogo live → Editar rápido **ou** Definir preço € 2. Preço 12,00 → Guardar 3. SQL item

**Se estiver bem:** `live_items.price=12`; shadow `checkout_product_id` sync se existir; card vermelho resolve

#### A048 — Chat sistema «preço definido» após P4 (P3)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Seller grava preço 2. Buyer vê chat público 3. (Opcional) notificação

**Se estiver bem:** Msg sistema humanizada «preço definido» / equivalente; compradores informados

#### A049 — Saco sem Pagar até preço; desbloqueia após P4 (P4 gate)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** **Fase 1:** Buyer saco → «Preço a definir» → sem Pagar. **Fase 2:** Após A047 → reabrir saco → Pagar activo

**Se estiver bem:** Fase 1: sem Stripe; label cinzento. Fase 2: preço teal + CTA Pagar (liga A227)


### Publicar e ir ao ar

#### A050 — Deep link `/criarDirecto` salta preparar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir link autenticado 2. Ver ecrã câmara

**Se estiver bem:** `criar_directo_page_widget` abre; catálogo vazio ou último sync; sem crash

#### A051 — Validação título mínimo no criar directo

**Corrida:** ❌ Falhou — O emulador não conseguiu abrir a app (instabilidade, não necessariamente bug na app)

**Tipo de falha:** 🔧 **INFRA** — Emulador não conseguiu abrir a app *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Introduzir título «ab» (2 chars) 2. Tentar Iniciar Directo

**Se estiver bem:** CTA desactivado ou snack/validação; **sem** `status=live`

#### A052 — Edge cria stream Mux no primeiro preview

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Entrar criar directo / preview câmara 2. Aguardar edge

**Se estiver bem:** `mux_stream_key`, `mux_live_id` persistidos em `lives`

#### A053 — Mesmo live_id — não duplica asset Mux

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Reentrar criar directo mesmo draft 2. Query Mux ids

**Se estiver bem:** Mesmo `live_id`; `mux_live_id` inalterado; sem segundo POST create-mux

#### A054 — Go-live com publish activo e studio

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Iniciar Directo 2. Confirmar avisos (A055 se aplicável) 3. Ver studio

**Se estiver bem:** `lives.status=live`, `is_active=true`; LiveKit egress; painel vendedor

#### A055 — Sheet open reservations — confirmar go-live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Iniciar directo 2. Ler popup 3. Confirmar

**Se estiver bem:** Lista correcta de origens; live inicia após confirmar

#### A056 — Recusar aviso cancela go-live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Iniciar 2. Recusar/Cancelar no sheet

**Se estiver bem:** Pop criar directo; `status` **não** `live`

#### A057 — Erro BD ao marcar live — não publicar silenciosamente

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Maestro (robô no telemóvel))*

**O que fazes:** 1. Iniciar com BD indisponível momentâneo

**Se estiver bem:** Erro UI; publish **não** continua sem BD `live`

#### A058 — Teardown explícito navega para player VOD

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Tocar Terminar directo 2. Confirmar

**Se estiver bem:** `status=ended`, `is_active=false`; navega `FleaberLivePlayer` replay

#### A059 — Fechar UI termina live e vai Home

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Maestro (robô no telemóvel))*

**O que fazes:** 1. Tocar X/fechar 2. Ver destino

**Se estiver bem:** Home (não Arena gravado); live `ended` na BD

#### A060 — Edge pós-teardown preenche `mux_vod_playback_id`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Aguardar até 60s 2. Poll `lives`

**Se estiver bem:** `mux_vod_playback_id` not null; replay reproduzível

#### A061 — Botão sistema back fecha directo (não minimiza só)

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Press back 2. Ver BD e destino

**Se estiver bem:** Teardown equivalente; não orphan silencioso

#### A062 — Kill app com live activa — restart fecha órfão

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Kill processo 2. Reabrir app 3. `reconcileOnAppStart`

**Se estiver bem:** Live `ended`; prefs limpas; Mux teardown best-effort

#### A063 — `reconcileOnAppStart(fullSweep:true)` não mata live Maestro partilhado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Bot cria live 2. Seller login/home trigger fullSweep 3. Buyer ainda no player

**Se estiver bem:** Live teste **permanece** `live` quando flag/convenção activa; senão ended (H07)

#### A064 — Publish RTMP alternativo (se flag activa)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Publicação RTMP alternativa — depende de flag especial e stream real.

**O que fazes:** 1. Iniciar via branch RTMP 2. Ver stream

**Se estiver bem:** Live live; path RTMP distinto de LiveKit default

#### A065 — UX quando câmara recusada

**Corrida:** 🚫 Bloqueado — Depende de outro teste ou funcionalidade em falta

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Tens de **recusar a permissão da câmara** no Android e ver a mensagem de erro.

**O que fazes:** 1. Abrir criar directo

**Se estiver bem:** Aviso + CTA definições; não crash; não go-live

#### A066 — UX quando microfone recusado

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Preview 2. Tentar iniciar

**Se estiver bem:** Aviso áudio; política BATATA (bloquear ou mute)

#### A067 — `stop_egress` invocado ao terminar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Terminar live 2. Ver logs edge

**Se estiver bem:** POST `livekit-mux-publish` step `stop_egress`; sem egress zombie

#### A068 — Falha edge — ended sem playback_id

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Terminar 2. Edge falha 3. Query lives

**Se estiver bem:** `ended` mas `mux_vod_playback_id` null; UI gravado degradada documentada

#### A069 — Prefs `batata_active_broadcast_live_id_v1` após kill

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Kill app 2. Ler SharedPreferences antes restart

**Se estiver bem:** Pref contém live_id; usado por A062

#### A070 — Staff helper não inicia directo próprio

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante a tentar iniciar directo próprio — permissões de equipa.

**O que fazes:** 1. Tentar navegar criar directo

**Se estiver bem:** Bloqueio ou redirect; sem publish

#### A071 — `maestro_seller_studio_page_widget` debug

**Corrida:** ❌ Falhou — O emulador não conseguiu abrir a app (instabilidade, não necessariamente bug na app)

**Tipo de falha:** 🔧 **INFRA** — Emulador não conseguiu abrir a app *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir harness 2. Operação → Aceitar

**Se estiver bem:** Studio funcional sem câmara real; H01 pass

#### A072 — Orientação landscape no encode/view

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Rodar o telemóvel para paisagem durante encode/visualização.

**O que fazes:** 1. Rodar telemóvel 2. Ver preview/player

**Se estiver bem:** Vídeo correcto ou letterbox conforme flag

#### A073 — Modo diagnóstico preview (debug)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Modo diagnóstico de preview — só em build de debug.

**O que fazes:** 1. Activar diagnostic 2. Ver overlay/stats

**Se estiver bem:** Info técnica visível só debug; não em release

#### A074 — Catálogo prep sync na BD antes de Iniciar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Continuar prep → criar 2. Query `live_items` antes go-live

**Se estiver bem:** Items na BD com stock/preço; carrossel pronto pós-live

#### A075 — Home feed mostra card LIVE após A054

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Navegar Home 2. Ver grid

**Se estiver bem:** Card LIVE com título; `requestLiveFeedRefresh`

#### A076 — Timeout create-mux — UX de espera/erro

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Esperar timeout da API Mux — demora real (minutos) difícil no robô.

**O que fazes:** 1. Abrir criar 2. Esperar > timeout

**Se estiver bem:** Mensagem «A preparar câmara» → erro retry; não hang infinito

#### A077 — Segundo device não publica em paralelo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Precisa de **dois telemóveis** — o segundo não pode publicar em paralelo.

**O que fazes:** 1. Login device B 2. Tentar go-live

**Se estiver bem:** Bloqueio ou teardown A; política single publish

#### A078 — Helper HLS + painel operações

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante a ver HLS + painel de operações — sessão helper real.

**O que fazes:** 1. Abrir `helper_live_ops` 2. Ver fila

**Se estiver bem:** Painel operações; **sem** terminar live (A374)

#### A079 — Rota antiga não navega

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir `/liveStreamVendor`

**Se estiver bem:** 404 redirect ou home; sem crash


### Operações do vendedor durante a live

#### A080 — Secção «No saco» lista reservas pending com metadata

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Linha visível com nome comprador (`profiles.full_name`), ref/título artigo, `requested_qty`, prazo/deadline se aplicável; chip posição ou estado pending; botões Aceitar/Rejeitar/Skip activos

#### A081 — Aceitar reserva pending → accepted + stock + msg sistema

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** RPC `batata_process_live_reservation_request` action `accept` → `status=accepted`; mensagem sistema no chat (humanizer); stock reservas/vendidos actualiza; secção **Aceites · aguardar pagamento**

#### A082 — Rejeitar reserva pending → rejected + notificação comprador

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** `status=rejected`; comprador vê chip rejeitado no saco; msg sistema P12a no chat; stock libertado; linha sai da fila urgente

#### A083 — Skip reserva pending → skipped; sai da fila urgente

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** `status=skipped`; pedido deixa de aparecer em No saco/Pendentes activos; não converte; comprador informado conforme regra skip

#### A084 — Aceitar qty > stock com dialog confirmação vendedor

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `status=accepted`, `requested_qty=2`; notes contém marca qty/overbook; stock reservas reflecte aceite; **sem** card urgente até comprador **Pagar** (T2)

#### A085 — Reserva `bag_removed` — vendedor sem acções na fila

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** **Sem** botões Aceitar/Rejeitar/Skip; secção cancelados ou histórico; actividade «cancelou» (não «adicionou ao saco»); regra BATATA live-ops

#### A086 — Card vermelho urgente vendedor — T1 sim, T2 não (BATATA)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** T2: zero card `_buildUrgentReservationCard`; T1: card vermelho com breakdown stock (R6); dialog comprador; **sem** abrir Stripe até resolver

#### A087 — KPI Operação «valor vendido» = artigo + portes + seguro (R5)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** KPI ≈ total comprador (~14,83 € para artigo 10 € + taxas); **não** só preço artigo (~10 €); `paid_value_eur` em `live_vendor_studio_logs` alinhado

#### A088 — Order `pago` sem convert — auto-reconcile ao abrir painel

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** `reconcileStalePaidReservationsForLive` converte; reserva → `converted`; stock sold actualiza; log `stale_reconciled` > 0; KPI actualiza

#### A089 — UI usa «Pendentes» — label legacy «A tratar» ausente

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Label **Pendentes** (`SellerOperationSection.queue` / `_ReservationListCategory.pending`); **sem** texto «A tratar»

#### A090 — Secção «Aceites · aguardar pagamento» lista accepted

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Header «Aceites — aguardam pagamento (N)»; linhas accepted com prazo pagamento; sem botão Aceitar

#### A091 — Secção «Sem pagamento» — accepted expirados ou unpaid

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Linhas na categoria `_ReservationListCategory.unpaid`; acções conforme política (re-offer / expire)

#### A092 — Externos e waitlist visíveis ao vendedor

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Secção Externos com linhas correctas; waitlist/external count no summary chip; actividade «pagamento externo» se manual

#### A093 — Histórico de reservas convertidas/rejected/skipped

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Estados terminais visíveis; ordenação cronológica; read-only

#### A094 — Secção/filtro cancelados comprador (`bag_removed`)

**Corrida:** ❌ Falhou — O emulador não conseguiu abrir a app (instabilidade, não necessariamente bug na app)

**Tipo de falha:** 🔧 **INFRA** — Emulador não conseguiu abrir a app *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Cancelados visíveis; **fora** aba Aceites; Pagamentos → «Cancelados pelo comprador»; sem acções

#### A095 — Fluxo T1 → Aceitar → Pagar abre Stripe sem loop urgente

**Corrida:** ❌ Falhou — O emulador não conseguiu abrir a app (instabilidade, não necessariamente bug na app)

**Tipo de falha:** 🔧 **INFRA** — Emulador não conseguiu abrir a app *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Híbrido (dados + ecrã)

**O que fazes:** —

**Se estiver bem:** Sem loop card urgente infinito; checkout qty 2; Stripe URL; sem segunda confirmação bloqueante

#### A096 — Aceite dispara R1 card + R2 banner comprador

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Card verde player (R1); banner saco «Aceite · pronto a pagar» (R2); msg chat sistema

#### A097 — `batata_recompact_reservation_queue` mantém FIFO posições

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Posições recompactadas 1..N sem buracos; ordem FIFO preservada

#### A098 — Helper/staff **sem** permissão não aceita reservas

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante **sem** permissão a tentar aceitar reservas — deve ser bloqueado.

**O que fazes:** —

**Se estiver bem:** Botões Aceitar/Rejeitar ocultos ou disabled; RPC rejeitado se forçado

#### A099 — Owner seller ignora restrições staff context

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Dono da loja ignora restrições de staff — comparar duas contas.

**O que fazes:** —

**Se estiver bem:** Todas acções fila activas; RPC success

#### A100 — Toggle modo chat privado vendedor

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Msgs vão para canal privado; comprador vê thread privada; público não expõe

#### A101 — Badge unread chat privado vendedor

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Badge contador incrementa; limpa ao abrir thread

#### A102 — Filtro chat «Perguntas»

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Só perguntas de compradores visíveis; sistema/compra ocultos

#### A103 — Filtro chat «Reservas»

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Só eventos reserva; resto oculto

#### A104 — Filtro chat «Sistema»

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Só msgs sistema/humanizer; users ocultos

#### A105 — Nome chat = `profiles.full_name` (BATATA)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Labels usam `full_name`/username app; **não** email cru; inclui msgs da própria vendedora

#### A106 — Imagens comprador renderizam no chat público seller

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Thumbnail/cache visível; tap expand se aplicável

#### A107 — Tab Pagamentos lista orders convertidas da live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Lista com buyer, ref, total (incl. portes); estado pago; link order

#### A108 — Log `reservation.load` inclui `stale_reconciled` count

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Evento `reservation.load` com `stale_reconciled` ≥ 1 na 1.ª carga; 0 na 2.ª

#### A109 — Log studio `reservation.accept` com qty metadata

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Row `event='reservation.accept'` com `reserved_qty`, `item_qty`, `live_id`

#### A110 — Log `checkout.pay_qty_gate` ao Pagar qty>stock

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Evento `checkout.pay_qty_gate` com request_id, qty pedida, available

#### A111 — Vários compradores — ordem FIFO na fila seller e chips comprador

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `queue_position` / `created_at` FIFO; seller vê A antes de B; chips comprador #1/#2; após aceite A, B mantém posição waitlist se stock esgotado

#### A112 — Race: dois aceites simultâneos — só um ganha stock

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Um `accepted`, outro rejected/skipped ou waitlist; stock nunca negativo; sem double-sold

#### A113 — Expiração automática reserva pending/accepted

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** `status=expired` (ou skipped conforme SQL); stock libertado; comprador notificado

#### A114 — Waitlist e pedidos externos visíveis na Operação

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Linha waitlist com label externo/espera; summary chip Externos incrementa

#### A115 — Tip/gorjeta visível no painel vendedor

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Linha gorjeta; `_liveTipsValueEur` incrementa; separada de vendas

#### A116 — KPI vendas exclui gorjetas

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** `sales_value_eur` ≠ tips; contadores separados; wallet tip distinto

#### A117 — Vendedor cria rifa activa na live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** RPC `batata_create_live_raffle` ok; row `live_raffles`; ops bar mostra countdown; comprador vê card (A211+)

#### A118 — Fechar entradas rifa (stop join)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `LiveRaffleService.closeEntries`; status entries_closed; join bloqueado; draw ainda possível

#### A119 — Sortear vencedores rifa seller

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** RPC `batata_draw_live_raffle`; rows `live_raffle_winners`; msg chat rifa; rifa status completed

#### A120 — Cancelar rifa activa

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `LiveRaffleService.cancel`; status cancelled; entries inactivas; comprador card some

#### A121 — Toggle leaderboard público rifa

**Corrida:** ❌ Falhou — Ver detalhe técnico no relatório se precisares

**Tipo de falha:** 🔧 **INFRA** — Crash/timeout do próprio Maestro ou emulador *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ⚠️ Passou com aviso — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** ON: top participantes visível buyer; OFF: oculto

#### A122 — Barra operações rifa integrada no painel Operação

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Bar com título, countdown, acções close/draw/cancel; não obscurece fila

#### A123 — Menu «Mais» studio — acções secundárias

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Itens esperados (ajustes, ajuda, etc.) sem regressão navegação

#### A124 — Placeholder bundle discount «em breve»

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Label «em breve» ou disabled; **sem** crash; **sem** alterar preços

#### A125 — Vendedor recusa over-stock no dialog (não aceita qty>stock)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Permanece pending; sem accepted; comprador pode ajustar qty ou cancelar

#### A126 — Aceite bloqueado/aviso quando stock pool noutro directo (Z82)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Aceite falha ou aviso; `batata_live_items_same_stock_pool` reflecte blocked; catálogo Disp correcto (A3)

#### A127 — RPC `batata_live_mark_qty_confirm_needed` ao Pagar qty>stock

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Notes contém `qty_confirm_needed`; persistido via RPC (comprador sem RLS update); card urgente activa; log A110

#### A128 — Strings ERP/qty_confirm **não** aparecem no chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Humanizer filtra ERP/qty_confirm; chat limpo; card urgente só no studio (não público)

#### A129 — Actividade: «adicionou ao saco» só pending aberto; cancel remove evento

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `_appendActivity` bagAdd em create pending; `_syncBuyerCancelActivities` remove res-new/res-acc; **sem** «adicionou» após cancel; regra BATATA cancelados


### Catálogo na live

#### A130 — Activar vitrine (is_active) no catálogo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Abrir tab Catálogo 2. Tocar «Mostrar» / activar artigo B 3. (Opcional) comprador no player observa carrossel

**Se estiver bem:** Artigo B `is_active=true`; outros `is_active=false`; evento `live_item_show_events`; comprador vê highlight B no carrossel

#### A131 — Barra catálogo alinhada com `available_qty` RPC

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Abrir catálogo seller 2. Comparar label Total·Disp vs barra de fundo 3. +/- stock 4. Recomparar

**Se estiver bem:** **Disp** = `available_qty` RPC (não confundir com `quantity` bruto); Total mostra bruto quando diferem

#### A132 — Repor stock após sold — catálogo e carrossel sync

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Menu artigo → +10 unidades (ou edit qty) 2. Ver catálogo seller 3. Ver carrossel comprador

**Se estiver bem:** Catálogo e carrossel **Qtd: 10**; badge sold removido; barra activa

#### A133 — Badge ESGOTADO nunca só por pending

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Comprador reserva qty 1 2. Ver badge carrossel/saco **sem** aceitar

**Se estiver bem:** **Sem** badge ESGOTADO; waitlist/reserva permitida; `reserved_full` só pós-aceite

#### A134 — Editar preço inline no catálogo live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Abrir quick edit preço 2. Alterar valor 3. Guardar 4. Comprador vê carrossel

**Se estiver bem:** `live_items.price` actualizado; carrossel reflecte novo preço; checkout usa preço live (`resolveFreshUnitPrice`)

#### A135 — Editar descrição inline no catálogo live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Quick edit descrição 2. Guardar 3. Comprador expande detalhe carrossel

**Se estiver bem:** Descrição persistida; visível no player sem reload app

#### A136 — Alterar fotos do artigo durante live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Quick edit fotos 2. Adicionar/remover imagem 3. Guardar 4. Ver carrossel/checkout

**Se estiver bem:** `image_url` / gallery actualizada; miniatura carrossel e checkout (A196) reflectem

#### A137 — Editar estado/condição do artigo no live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Quick edit estado 2. Seleccionar novo valor 3. Guardar

**Se estiver bem:** Estado persistido; label visível no carrossel se exposto

#### A138 — Opt-in marketplace no catálogo live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Activar toggle «Listar no marketplace» 2. Query product 3. (Opcional) checkout

**Se estiver bem:** `list_on_marketplace=true`; checkout via `product_id` marketplace; listing marketplace intacto

#### A139 — Poll stock cross-session cada ~2s

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Reservar/vender noutra sessão 2. Observar catálogo seller live A 3. Esperar poll

**Se estiver bem:** Disp/barra actualiza em ~2s sem reload manual; `blocked_qty` reflectido

#### A140 — KPI vendidos incrementa pós-pagamento

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Baseline contador vendidos catálogo 2. Completar pagamento 3. Ver catálogo seller

**Se estiver bem:** Contador **Vendidos** +1 (ou +qty); barra reflecte unidades vendidas

#### A141 — KPI reservas reflecte pending

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Comprador reserva 2. Ver contador Reservas no catálogo seller

**Se estiver bem:** Reservas incrementa; inclui `blocked_qty` cross-live se regra v6

#### A142 — Barra catálogo após aceite parcial qty multi

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Setup 2× reserva 2. Seller aceita uma 3. Ver barra Vendidos/Reservas

**Se estiver bem:** Vendidos +1; Reservas desce; barra coerente com stock bruto

#### A143 — Rollback UI se RPC vitrine falha

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Tocar Mostrar artigo C 2. Forçar falha rede/RPC 3. Observar UI

**Se estiver bem:** UI reverte para vitrine anterior; snack erro; BD `is_active` inalterado

#### A144 — `quantity` BD sync após +/- stock

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. +/- via catálogo 2. Query `live_items.quantity` 3. Comparar carrossel

**Se estiver bem:** `live_items.quantity` = valor editado; carrossel Qtd match; recompute OK


### Comprador a ver a live

#### A145 — Entrada player via card LIVE Home

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Home → grid lives 2. Tap card LIVE 3. Aguardar player

**Se estiver bem:** `FleaberLivePlayer` abre; HLS/Mux playback; saco visível; badge LIVE

#### A146 — Player VOD via perfil vendedor

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Perfil seller → tab Diretos anteriores 2. Tap gravado

**Se estiver bem:** Player VOD; badge **GRAVADO**; chat off (A162); saco/commerce on

#### A147 — Referral rifa via deep link

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir link (guest ou logged out) 2. Login/registo 3. Permanecer player ≥60s

**Se estiver bem:** `registerReferralVisit`; qualify 60s (A214); referrer +2 entradas

#### A148 — Primeira reserva — pending + chat

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Carrossel → Reservar qty 1 2. Ver snack 3. Ver chat

**Se estiver bem:** `live_reservation_requests` `status=pending`, `requested_qty=1`; chat `🛍️`; snack OK

#### A149 — Segunda reserva incrementa qty — não duplica row

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Reservar de novo mesmo artigo 2. Abrir saco 3. Query BD

**Se estiver bem:** **Mesma** linha `requested_qty=2`; **não** 2 rows pending

#### A150 — Fila de espera quando stock esgotado por aceite

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Segundo comprador reserva 2. Abrir saco 3. Ver chips

**Se estiver bem:** Waitlist; chip **Espera #N**; **sem** ESGOTADO só por pending

#### A151 — Card verde comprador ao aceite — sem dialog duplicado

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Híbrido (dados + ecrã)

**O que fazes:** 1. Seller aceita 2. Observar player comprador <5s

**Se estiver bem:** **Um** card verde acima chat; **sem** dialog overlay duplicado; foto artigo

#### A152 — Banner saco só em `status=accepted`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Aceitar reserva 2. Comprador abre saco

**Se estiver bem:** Banner + chip «Aceite · pronto a pagar»; **sem** banner em pending puro

#### A153 — CTA Pagar no saco e player quando payable

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Ver saco 2. Ver card player 3. Confirmar CTA

**Se estiver bem:** **Pagar** visível em ambos quando `buyerCanPayBagReservation`; desactivado se price 0

#### A154 — Stepper +/- qty persiste ao reabrir saco

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Abrir saco 2. +/- qty 3. Fechar e reabrir saco

**Se estiver bem:** Qty mantém valor editado; BD `requested_qty` sync

#### A155 — Chips por unidade — cores verde/âmbar

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Criar 2+ reservas/unidades 2. Abrir saco 3. Ver chips

**Se estiver bem:** Chips #1 #2 #3 por unidade; verde se unidade ≤ stock bruto; âmbar Espera

#### A156 — Contador espectadores incrementa ao entrar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Entrar player 2. Observar contador 3. (Opcional) 2º viewer

**Se estiver bem:** Contador incrementa via `batata_live_viewer_ping`; seller vê tally

#### A157 — Seguir vendedor no player

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Player → Seguir 2. Ver estado 3. (Opcional) unfollow

**Se estiver bem:** Follow gravado; rifa +1 entrada se rifa activa (regra produto)

#### A158 — Checkout directo sem passar aceite vendedor

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Carrossel → Comprar já 2. Ver checkout

**Se estiver bem:** Abre `LiveInStreamCheckout` / sheet; **sem** estado accepted prévio

#### A159 — Highlight carrossel segue vitrine seller

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Seller activa artigo D 2. Buyer poll ~2s 3. Ver highlight

**Se estiver bem:** Highlight/scroll automático para item `is_active=true`

#### A160 — Comprador remove reserva do saco (pré-pagamento)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Saco → Remover/Cancelar 2. Confirmar 3. Ver vendedor fila

**Se estiver bem:** `status=rejected`, notes `bag_removed`; stock libertado; vendedor **sem** Aceitar (A085)

#### A161 — Comprador envia mensagem chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Player → input chat 2. Enviar mensagem 3. Ver painel

**Se estiver bem:** Msg aparece no chat público; `profiles.full_name` como nome

#### A162 — Input chat desactivado em VOD/replay

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Entrar gravado (A146) 2. Tentar escrever chat

**Se estiver bem:** Input disabled ou oculto; replay chat histórico visível

#### A163 — Mensagem privada comprador para vendedor

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Player → DM/privado 2. Enviar msg 3. Seller vê tab Chat privado

**Se estiver bem:** Thread privada; seller recebe; não mistura com chat público

#### A164 — Partilhar link da live (copy)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Player → Partilhar 2. Copiar link 3. Abrir noutro device/browser

**Se estiver bem:** Link válido abre player correcto; deep link params preservados

#### A165 — Overlay spotlight no artigo activo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seller activa spotlight (se UI) 2. Buyer vê overlay

**Se estiver bem:** Destaque visual extra no item activo; não quebra carrossel

#### A166 — Portes visíveis antes de abrir Stripe

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Pagar → sheet 2. Ver breakdown **antes** confirmar

**Se estiver bem:** Linhas transportadora 3,50 € / mão 0 € visíveis; total parcial

#### A167 — Linha seguro no preview checkout comprador

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir checkout 2. Ver linha seguro 3. Calcular 0,65 + 5%

**Se estiver bem:** Seguro visível no total preview; fórmula BATATA

#### A168 — Retomar app após Stripe — reconcile pending

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Voltar à app depois de ir ao Stripe pagar — fluxo sandbox real.

**O que fazes:** 1. Pagar → browser Stripe 2. Home app 3. Resume app

**Se estiver bem:** `tryResumeOnAppResumed` reconcilia; snack sucesso ou estado saco correcto

#### A169 — Playback HLS live com latência reduzida

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Qualidade e latência do vídeo HLS ao vivo — perceptível a olho humano.

**O que fazes:** 1. Entrar player 2. Observar latência vs studio 3. Verificar HLS URL

**Se estiver bem:** Stream HLS playable; latência aceitável (<10–15s staging); sem stall prolongado

#### A170 — Rota player inválida — fallback seguro

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir rota player malformed 2. Observar comportamento

**Se estiver bem:** Fallback PDP ou erro amigável; **sem** crash

#### A171 — PDP marketplace preserva contexto live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir artigo com param origin 2. Ver PDP

**Se estiver bem:** `originLiveId` passado; CTA voltar à live se regra activa

#### A172 — KPI Reservas carrossel inclui cross-live/blocked

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Seed cross reservation 2. Ver label Reservas no carrossel buyer

**Se estiver bem:** Contador inclui unidades cross conforme regra v6

#### A173 — UI distingue indisponível de waitlist

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Esgotar stock com aceite 2. Novo buyer reserva 3. Ver badges

**Se estiver bem:** **Sem** badge ESGOTADO bloqueante; CTA reservar/waitlist; chip Espera no saco

#### A174 — Enviar gorjeta na live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Player → Gorjeta 2. Escolher valor 3. Pagar Stripe/wallet

**Se estiver bem:** Tip registada; aparece painel seller; **sem** metadata saco

#### A175 — Reentrada player — anúncio compras recentes

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Sair player 2. Reentrar mesma live 3. Ver FOMO/banner

**Se estiver bem:** Banner ou msgs «comprou» recentes; dedupe A289

#### A176 — Orientação ecrã player

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Rodar device landscape 2. Voltar portrait

**Se estiver bem:** Layout adapta ou lock conforme BATATA; sem crash; controls acessíveis

#### A177 — Cache catálogo invalida após mutação seller

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Buyer vê carrossel 2. Seller +/- stock 3. Esperar poll/realtime

**Se estiver bem:** Carrossel actualiza; prefs cache não serve stale >TTL

#### A178 — Supabase realtime actualiza carrossel

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Seller muda vitrine ou preço 2. Observar buyer <3s

**Se estiver bem:** Carrossel refresh via realtime/poll; highlight A159 sync

#### A179 — Saco actualiza realtime (aceite/reject)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Seller aceita/rejeita 2. Buyer vê update sem reload

**Se estiver bem:** Saco/card player actualiza <5s; card verde R1

#### A180 — Aceite realtime robusto — payload sem user_id

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Seller aceita 2. Buyer recebe evento 3. Ver card/banner

**Se estiver bem:** UI actualiza mesmo se msg realtime omitir `user_id`; fallback scan saco

#### A181 — Erro amigável — fila vs bloqueio total

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Tentar acção que falha (reserva duplicada inválida vs waitlist OK) 2. Ler snack

**Se estiver bem:** Mensagem clara; waitlist **não** mostra «Erro: item_reserved_full» genérico

#### A182 — Carrossel com muitos artigos — scroll e performance

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Entrar player 2. Scroll carrossel 3. Reservar item no extremo

**Se estiver bem:** Scroll fluido; item extremo reservável; highlight A159 OK

#### A183 — Feed Home coerente com BD `status`/`is_active`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Query BD 2. Comparar cards Home 3. Terminar live 4. Refresh feed

**Se estiver bem:** Só `status=live AND is_active=true` como LIVE; ended não LIVE

#### A184 — Param `forceVod` força modo replay

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir link forceVod 2. Ver player

**Se estiver bem:** Modo VOD mesmo se BD ainda live (debug/staging); guards chat A162

#### A185 — Param `sellerId` na rota player

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir rota 2. Ver header follow/perfil

**Se estiver bem:** Seller correcto no header; follow target OK

#### A186 — Multi-device — saco sync mesma conta

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Device A reserva 2. Device B abre saco 3. Device A cancela

**Se estiver bem:** Saco B actualiza; sem estado divergente permanente

#### A187 — Referral visit anónimo atribuído pós-login

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir link logged out 2. Login 3. Permanecer 60s

**Se estiver bem:** Visit atribuída ao user autenticado; qualify A214

#### A188 — Join rifa via sidebar player

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Player → sidebar rifa 2. Tocar Participar

**Se estiver bem:** +1 entrada; UI confirma inscrição; sem duplicar tap

#### A189 — Join rifa via sheet modal +1 entrada

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir sheet rifa 2. Participar 3. Ver contador

**Se estiver bem:** +1 entrada base; contador actualizado; alinhado A212


### Checkout e saco

#### A190 — Sheet «Saco da live» abre com secções

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Entrar player (`live_id`) 2. Tocar «Saco da live» (sidebar ou CTA) 3. Ver sheet

**Se estiver bem:** `LiveBagSheet` abre; secções visíveis conforme estado; sem navegar para PDP

#### A191 — Linhas pending no saco com metadata correcta

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Reservar artigo 2. Abrir saco 3. Localizar secção in-bag

**Se estiver bem:** Linha com título/ref, qty, chip posição (#1 se aplicável), estado «Pendente»; botão Pagar se `buyerCanPayBagReservation`

#### A192 — Reserva em fila quando stock cheio

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Esgotar stock com aceite 2. Segundo comprador reserva 3. Abrir saco

**Se estiver bem:** Chip «Espera #N» ou secção waitlist; **sem** badge ESGOTADO só por pending

#### A193 — Histórico converted no saco

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Completar pagamento 2. Reabrir saco

**Se estiver bem:** Secção purchased; chip «Comprado ✓»; sem botão Pagar

#### A194 — Cancelamento comprador no saco

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Comprador remove do saco 2. Reabrir saco

**Se estiver bem:** Secção cancelled; label `buyerBagRejectedLabel`; vendedor sem Aceitar (A085)

#### A195 — Seleccionar linhas a pagar no saco

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Saco → Pagar 2. `LiveBagCheckoutSheet` 3. Toggle checkboxes 3. Ver total

**Se estiver bem:** Checkboxes por linha/agregado; total recalcula; CTA pagar desactivado se nenhuma seleccionada

#### A196 — Fotos dos artigos nas linhas do checkout

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Abrir checkout sheet 2. Ver cada linha

**Se estiver bem:** `BatataCachedImage` por linha; placeholder se sem foto

#### A197 — Duas reservas mesma ref → 1 linha qty 2

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Reservar/incrementar qty 2 2. Pagar 3. Inspeccionar sheet + metadata Stripe

**Se estiver bem:** `mergePayableByLiveItem` → 1 linha `requested_qty=2`; 1 order ou metadata agregada

#### A198 — Checkout saco multi-ref — POST create-payment-intent

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Reservar ref A e B 2. Pagar ambas 3. Capturar POST edge (sem pagar UI opcional)

**Se estiver bem:** HTTP 200; `checkoutUrl`; metadata sem `bag_orders_json` >500 chars; `bag_checkout: true`

#### A199 — Linha portes Envio Transportadora no checkout

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir checkout 2. Escolher «Envio Transportadora (€3.50)» 3. Ver breakdown

**Se estiver bem:** +3,50 € no total; label exacta BATATA

#### A200 — Entrega em mão sem portes

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Checkout 2. Seleccionar «Entrega em Mão (€0.00)»

**Se estiver bem:** Portes 0; total = artigos + seguro apenas

#### A201 — Protecção Fleaber no breakdown

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir checkout 2. Ver linha seguro 3. Calcular manualmente

**Se estiver bem:** 0,65 + 5% × (artigos + portes); visível no sheet

#### A202 — Preço pendente — Pagar bloqueado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Reservar sem preço 2. Tentar Pagar

**Se estiver bem:** `LiveItemPriceGate` falha; snack/erro amigável; **sem** Stripe

#### A203 — Stepper checkout reflecte qty aceite over-stock

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Aceitar over-stock 2. Pagar 3. Ver qty no sheet

**Se estiver bem:** Qty **2** no checkout; total 2× preço + taxas

#### A204 — Comprador vê dialog; vendedor card urgente — só ao Pagar

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Reservar qty 2 stock 1 2. **Pagar** (não só reservar)

**Se estiver bem:** Dialog comprador; card urgente vendedor; **sem** abrir Stripe

#### A205 — URL checkout Stripe ao confirmar pagamento

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Abrir a página de checkout Stripe no browser ao confirmar pagamento.

**O que fazes:** 1. Pagar 2. Confirmar no sheet 3. Browser/WebView abre

**Se estiver bem:** URL `checkout.stripe.com` ou success flow; `FleaberStripeCheckoutContext` grava pending

#### A206 — Retorno success → converted + order pago

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Pagar com `4242…` 2. Fechar browser 3. App resume `tryResumeOnAppResumed`

**Se estiver bem:** `orders.status=pago`; reserva `converted`; notes `stripe_paid:`; `live_id` preenchido

#### A207 — Cancelar checkout Stripe mantém reserva

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Cancelar no ecrã Stripe e confirmar que a reserva se mantém na app.

**O que fazes:** 1. Abrir Stripe 2. Cancelar/voltar

**Se estiver bem:** Reserva `accepted` ou `pending`; **não** converted; order abortada ou `reserva_pendente`

#### A208 — Um checkout Stripe → 2 orders pago

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Multi-ref checkout 2. Success URL settle bag 3. Query orders

**Se estiver bem:** Ambas orders `pago`; cada reserva `converted`; `bag_orders_json` reconciliado

#### A209 — Reconcile manual/API order pago órfã

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seed order pago 2. RPC reconcile 3. Ver reserva

**Se estiver bem:** Reserva `converted`; stock atualiza; KPI refresh

#### A210 — Chat «comprou» após reconcile

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Pagar 2. Ver chat público 3. (Opcional) inbox mensagens vendedor-comprador

**Se estiver bem:** `batata_live_purchase_broadcast` → msg social «comprou»; thread privada/order msg se regra encomenda activa

#### A211 — Bónus rifa +2 após compra live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Completar pagamento saco/single 2. Abrir painel rifa 3. Ver contador entradas

**Se estiver bem:** +2 entradas no total do buyer; disparo único por order

#### A212 — Entrar na rifa durante directo (+1)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Player → painel rifa 2. Tocar Join / Participar

**Se estiver bem:** +1 entrada base; UI confirma inscrição

#### A213 — Partilha social +2 entradas

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Tocar Partilhar 2. Completar share intent (ou simular claim)

**Se estiver bem:** +2 entradas após claim válido; sem duplicar por re-share imediato

#### A214 — Visitante referral — qualificação 60s

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir link referral 2. Permanecer ≥60s (ou regra produto) 3. Ver entradas referrer

**Se estiver bem:** Referrer +2 entradas; visitante atribuído

#### A215 — Ranking top 5 entradas

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Abrir leaderboard rifa 2. Comparar ordem

**Se estiver bem:** Top 5 ordenado por entradas desc; buyer actual destacado

#### A216 — Countdown mm:ss até fecho

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir painel rifa 2. Observar timer 3. (Opcional) mock tempo

**Se estiver bem:** Decrementa em tempo real; UI fecha/join disabled ao zero

#### A217 — Broadcast rifa sem spam no chat

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Disparar 2+ broadcasts rifa rápidos 2. Ver chat público

**Se estiver bem:** Prefixo `🎟️ Rifa:`; dedupe R7 — sem linhas duplicadas em janela curta

#### A218 — Sorteio + notificação vencedores

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Trigger draw (timer ou admin) 2. Ver BD + chat + push

**Se estiver bem:** `winner_id`(s) persistido; notificação/chat anúncio

#### A219 — Movimento wallet vendedor após order pago

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Pagar como buyer 2. Login seller 3. Ver wallet

**Se estiver bem:** Crédito líquido (total − comissão − taxas Stripe)

#### A220 — Fee platform na libertação

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Inspeccionar order 2. Comparar com `fee_calculator`

**Se estiver bem:** Comissão % BATATA correcta; separada do líquido seller

#### A221 — Disputa em encomenda originada na live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Minhas encomendas 2. Abrir disputa

**Se estiver bem:** Disputa criada; estados order/disputa coerentes

#### A222 — Devolução pós-pago (cancelamento depois de pagar)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Iniciar devolução 2. Seller/admin processa 3. Ver stock/wallet

**Se estiver bem:** Refund separado de `bag_remove`; reserva permanece `converted`; stock revert conforme política

#### A223 — Order list com `live_id`

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Perfil → Minhas encomendas 2. Localizar order live

**Se estiver bem:** Linha com contexto live; `live_id` preenchido e navegável

#### A224 — Gorjeta independente do saco

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Player → Gorjeta 2. Pagar tip Stripe

**Se estiver bem:** `tip` row criada; **sem** misturar metadata saco (`bag_orders_json`)

#### A225 — Item shadow — `checkout_product_id` no pagamento

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Reservar shadow item 2. Pagar 3. Query `orders.product_id`

**Se estiver bem:** Resolve product shadow no checkout; marketplace listing **intacto** (Z52)

#### A226 — TYPE A — `product_id` marketplace no order

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Checkout 2. Pagar 3. Ver order + total

**Se estiver bem:** `product_id` marketplace; preço cobrado = **live** (`resolveFreshUnitPrice`)

#### A227 — Preço definido → CTA Pagar habilita (incl. aceite sem preço antes)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Reservar item price_pending 2. Seller aceita (BATATA permite) 3. Seller define preço 4. Buyer abre saco

**Se estiver bem:** Durante preço 0: Pagar bloqueado (A202); após preço: `buyerCanPayBagReservation` true; Pagar activo

#### A228 — Seller não pode alterar preço após venda/convert

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Converter reserva (A206) 2. Seller tenta mudar preço live

**Se estiver bem:** Erro/bloqueio P10; preço histórico preservado na order

#### A229 — Single vs bag vs tip — prefs não sobrescrevem

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Iniciar bag checkout 2. Cancelar Stripe 3. Iniciar single/tip 4. Completar pagamento

**Se estiver bem:** `FleaberStripeCheckoutContext` reconcile só sessão correcta; sem settle bag fantasma

#### A230 — Cancelamento comprador **antes** de pagar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Saco → Remover 2. Confirmar 3. Ver vendedor KPI

**Se estiver bem:** `status=rejected`, `notes` contém `bag_removed`; stock libertado; vendedor sem Aceitar


### Pagamentos

#### A231 — `/operacoesLive` — cards sessão com KPIs agregados

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Lista `LiveSessionSummary` com `articlesSold`, `revenueEur`, `pendingPayments`, `hasAlerts`; realtime refresh via subscriptions; navegação para `LiveSalesSessionDetailPageWidget`

#### A232 — Transição visual e BD order live checkout

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Order `reserva_pendente` → `pago`; label UI «Pago» via `normalizeOrderStatusKey`; reserva → `converted`; timeline coerente em detalhe sessão (`statusLabel`)

#### A233 — Reembolso parcial encomenda originada na live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Refund registado; saldo seller/wallet ajustado; order mantém histórico live; **sem** reverter reserva `converted` para pending

#### A234 — Reembolso integral pós-pago live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Refund 100%; wallet seller debita líquido; stock restore conforme política BATATA (pode não repor automaticamente); reserva permanece `converted`

#### A235 — `order_disputes` criada para order com `live_id`

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Row `order_disputes` `status=aberta`; order coerente; card disputa no chat se thread existir

#### A236 — Seller responde disputa; thread `order_dispute_replies`

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** Reply persistida; status disputa actualizado; notificação buyer opcional; sem expor dados internos admin

#### A237 — Estado `escalada_fleaber` + painel admin

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** `status=escalada_fleaber`; métricas admin (`activeDisputes`, `escalated`) incrementam; acção admin fecha ou mantém

#### A238 — Levantamento wallet após créditos de orders live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** `wallet_transactions` tipo `levantamento`; saldo disponível reduz; **sem** afectar orders `pago` nem comissão já contabilizada (A220)

#### A239 — Push/in-app pós-pagamento saco live

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Notificação única por order (debounce P15); deep link coerente; **sem** spam duplicado reconcile

#### A240 — Fee platform em settle 2+ orders (saco)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Comissão **por order** correcta; soma líquida seller = total pago − comissões − taxas; sem fee duplicada no settle bag

#### A241 — Painel in-stream: tips separados de `sales_value_eur`

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** —

**Se estiver bem:** KPI vendas ≠ gorjetas; contadores separados; tip não entra em `articlesSold` nem comissão venda

#### A242 — Tips incluídos no resumo `/resultadosLive` sem misturar receita artigos

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Receita artigos = orders+converted; gorjetas agregadas à parte ou excluídas de `totalRevenueEur` artigos; coerente com in-stream A241

#### A243 — Alerta `hasAlerts` — order `pago` sem reserva `converted`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** `hasAlerts=true`; `pendingPayments` ou conflitos visíveis; não esconde stale

#### A244 — Acção refresh/reconcile no pós-live converte órfãos

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Reserva → `converted`; alerta limpa; KPI receita alinhada; idempotente na 2.ª visita

#### A245 — Exportar ou copiar resumo comercial da sessão

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** —

**Se estiver bem:** Resumo legível (CSV, share intent ou clipboard); totais = BD; refs correctas

#### A246 — Minhas encomendas destaca/filtra orders com `live_id`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Orders live identificáveis; filtro não esconde marketplace; `live_id` navegável

#### A247 — Lista vendas sessão filtra por estado pago/disputa/devolução

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Filtros reduzem lista correctamente; disputas visíveis; `normalizeOrderStatusKey` labels PT

#### A248 — Procedimento operacional stale order documentado e reproduzível

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Playbook 100% reproduzível; estados finais documentados; suporte consegue repetir sem código

#### A249 — 2.ª chamada reconcile não duplica crédito/conversão

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** —

**Se estiver bem:** Reserva permanece `converted`; wallet **sem** segundo crédito; RPC idempotente (A209 pattern)


### Rifas

#### A250 — Suite H04: bot join + buyer Maestro «Participar na Rifa (+1)»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** `viewer.joined=true`; `ticketBalance` +1; BD `raffle_entries` incrementa; sem crash saco/rifa

#### A251 — Follow seller durante rifa — `follow_bonus_claimed`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Bónus entradas conforme regra produto; `follow_bonus_claimed=true`; UI «+N entradas»

#### A252 — Partilha social — `batata_claim_live_raffle_share_intent`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** `LiveRaffleShareClaimResult.ok`; entries +2; `share_bonus_claimed=true`

#### A253 — `ensureReferralLink` + `registerReferralVisit`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Link único por raffle; visita registada; referrer ainda sem bónus até qualify

#### A254 — `qualifyReferralVisits` após permanência

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Referrer +2 entradas; visita marcada qualified; sem qualify em <60s

#### A255 — Ranking comprador actualizado com entradas

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Top 5 desc por tickets; highlight self; refresh após join/share

#### A256 — Vendedor vê resumo participantes na ops bar

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Ops bar mostra métricas; toggle reflecte em buyer card; não bloqueia fila reservas

#### A257 — Ordem cronológica entradas preservada no sorteio

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** Entradas com `created_at` FIFO; draw weighted fair; sem inversão timestamps

#### A258 — Abrir live via link referral pré-preenche contexto rifa

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `registerReferralVisit` disparado; painel rifa acessível; sem crash auth

#### A259 — Seguir vendedor não dispara spam notificações (P15 overlap)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** ≤1 notificação follow; draw notif única; debounce alinhado P15

#### A260 — Re-share imediato não duplica +2

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Segundo claim rejeitado ou no-op; entries estáveis; mensagem UX clara

#### A261 — Vendedor dispara sorteio — `batata_draw_live_raffle_winners`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `status=drawn`; `winner_id`(s) persistidos; `drawn_at` preenchido; buyer card mostra resultado

#### A262 — Timer zero → close + draw automático (se política activa)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `isActive=false`; join disabled; draw executado conforme config; chat anúncio

#### A263 — Sorteio auditável — `tickets_at_draw` por winner

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Winners com tickets congelados; sem alteração entries pós-draw; log RPC ok

#### A264 — Anúncio draw no chat público humanizado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Mensagem sistema/chat com vencedor(es); humanizer activo; dedupe R7

#### A265 — Vencedor recebe push «Ganhaste a rifa»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Push única ao winner; não enviada a não-winners; deep link válido

#### A266 — Seller notificado sorteio concluído

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Notificação resumo (vencedor, entradas totais); sem duplicar A265

#### A267 — Replay gravado: countdown histórico; join/participar bloqueado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** `joined` read-only histórico; CTA join disabled; timer não decrementa em tempo real

#### A268 — Guard `_liveIsActive` bloqueia join em ended

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Join RPC não chamado; UI mostra resultado histórico ou «rifa terminada»

#### A269 — Bónus share/referral não disponíveis em replay

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** CTAs share/referral hidden ou disabled; `registerReferralVisit` não credita em ended

#### A270 — Rajada eventos rifa (join, +2, draw) sem spam chat

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Dedupe R7 — máx 1 linha por tipo em janela 5s; chat legível

#### A271 — Flow Maestro comprador rifa+saco sem falha

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ⚠️ Passou com aviso — UX+BD

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Login buyer → player → rifa optional → saco abre; exit 0

#### A272 — `v2_seller_harness_accept` + ops bar rifa visível

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** —

**Se estiver bem:** Harness não crash; ops bar presente; fila reservas funcional

#### A273 — `LiveRafflePrizeEditSheet` actualiza título/imagem

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** BD actualizada; buyer card reflecte sem restart app; entries preservadas

#### A274 — Imagem e título prémio no `LiveRaffleBuyerCard`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Prémio legível; countdown; tickets badge; layout BATATA sidebar

#### A275 — Seller cancela rifa — comprador vê estado cancelado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Card some ou mostra «cancelada»; join disabled; **sem** refund entradas (não pagas)

#### A276 — Bónus A211 não duplica em reconcile/repay

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** +2 uma vez por order_id; reconcile não re-aplica; total tickets correcto

#### A277 — 20+ bots join/share — leaderboard estável

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** —

**Se estiver bem:** Sem crash; top 5 correcto; ops bar contador ≈ BD; latência aceitável

#### A278 — `show_public_leaderboard=false` esconde ranking

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** —

**Se estiver bem:** OFF: buyer não vê top 5; ON: A255 visível; seller ops mantém contagem

#### A279 — Suite H04 completa: bot seed → Maestro → verify BD

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ⚠️ Passou com aviso — UX+BD

**Automatização:** 🤖 Híbrido (dados + ecrã)

**O que fazes:** —

**Se estiver bem:** Cadeia H04 verde; `.maestro/.env` válido; entries buyer ≥1; sem cleanup kill live (H07)


### Mensagens e chat

#### A280 — Mensagem pública de reserva no chat

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Comprador entra no player 2. Reserva 1 un. no carrossel 3. Abre painel chat público (comprador e vendedor)

**Se estiver bem:** Linha social humana «{Nome} reservou {Artigo}»; **sem** formato ERP; **sem** preço no chat público; visível para comprador e vendedor

#### A281 — Mensagem de aceite oculta no chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Comprador reserva 2. Vendedor aceita 3. Comparar chat público vs painel backoffice/notas

**Se estiver bem:** Detalhes de aceite (prazo, ERP, «aceitaste vender») **não** no chat público; comprador vê card verde/banner saco (outros testes)

#### A282 — Mensagem pública pós-compra

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Concluir pagamento 2. `batata_live_purchase_broadcast` dispara 3. Ver chat

**Se estiver bem:** «{Nome} comprou {Artigo}» no chat público; sem preço/portes; prefixo `✅` normalizado pelo humanizer

#### A283 — Mensagem «Preço definido» após seller definir preço

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Comprador tenta reservar (opcional) 2. Vendedor define preço no painel 3. Ver chat público

**Se estiver bem:** Broadcast sistema visível no chat; comprador pode passar a reservar/pagar; copy «Artigo — Preço» ou equivalente humanizado

#### A284 — Broadcast FOMO «última unidade»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Seller activa artigo com 1 un. 2. Trigger FOMO (stock threshold) 3. Ver chat comprador

**Se estiver bem:** Linha «Última unidade de {Artigo}» (humanizer aceita `Ultima`/`Última` na origem)

#### A285 — Broadcast FOMO «artigo esgotou»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Esgotar stock (aceite ou venda) 2. Ver chat

**Se estiver bem:** «{Artigo} esgotou» no chat público

#### A286 — Mensagem de gorjeta visível no chat

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Enviar gorjeta (P15) 2. Ver chat

**Se estiver bem:** Linha social com nome + valor; fallback se sem nome

#### A287 — Mensagem de cancelamento comprador

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Comprador remove do saco 2. Ver chat

**Se estiver bem:** Linha cancelamento com nome se disponível; seller **sem** Aceitar/Recusar na fila

#### A288 — Recusa vendedor só backoffice

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Vendedor rejeita 2. Ver chat público comprador

**Se estiver bem:** Recusa **não** aparece no chat público; comprador vê chip «Recusado» no saco

#### A289 — Uma linha «comprou» por par comprador+artigo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Disparar `batata_live_purchase_broadcast` 2x seguidas 2. Ver chat

**Se estiver bem:** UI mostra **uma** linha social; segunda suprimida por dedupe key `purchase\|nome\|item`

#### A290 — Prazo de pagamento não aparece no chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Aceitar reserva 2. Inspeccionar body raw vs UI

**Se estiver bem:** Chat público **sem** «5 dias» / «tem N dias»; prazo só saco/banner privado

#### A291 — Prazo aceite reflecte valor SQL

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Aceitar 2. Ver card verde player e banner saco

**Se estiver bem:** Copy mostra prazo **real**; não sempre «5 dias»

#### A292 — Normalização «ao saco» → «ao carrinho»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Trigger msg saco 2. Ver chat

**Se estiver bem:** UI «carrinho»; branding saco mantém-se noutros ecrãs

#### A293 — Mensagem social de adição ao saco

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Reserva em fila 2. Ver chat

**Se estiver bem:** Frase humana tipo «{Nome} adicionou {Artigo} ao carrinho»

#### A294 — Alerta qty>stock oculto do chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Reserva qty 2 stock 1 2. Comprador Pagar 3. Ver msgs

**Se estiver bem:** Msg ERP/qty_confirm **não** no chat público; card urgente vendedor (outro teste)

#### A295 — Mensagens aparecem no instante de playback (gravado)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Abrir gravado 2. Reproduzir do início 3. Seek para meio 4. Seek para fim

**Se estiver bem:** Msgs filtradas por `_filterMessagesForPlayback`; aparecem/desaparecem com playhead; skew Mux vs `went_live_at` compensado

#### A296 — Highlight carrossel segue timeline gravado

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Abrir gravado 2. Play 3. Seek pelos eventos

**Se estiver bem:** `_vodActiveItemId` actualiza; card correcto highlighted; sem poll activo (só eventos)

#### A297 — Reserva permitida em live terminada

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Abrir gravado 2. Reservar no carrossel

**Se estiver bem:** `pending` criada; saco actualiza; **sem** chat input; msg reserva pode emitir

#### A298 — Checkout permitido em VOD

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir gravado 2. Saco → Pagar 3. Abrir checkout sheet

**Se estiver bem:** `LiveBagCheckoutSheet` abre; portes/seguro visíveis; Stripe pode abrir (manual)

#### A299 — UX gorjeta em VOD

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Procurar CTA gorjeta 2. Tentar enviar

**Se estiver bem:** Tip **desactivado** ou snack «directo terminou»; sem crash

#### A300 — Feed Home abre gravado com HLS VOD

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Home 2. Tap card GRAVADO 3. Esperar vídeo

**Se estiver bem:** Player VOD; badge GRAVADO; vídeo reproduz (ou spinner → play)

#### A301 — Painel operações live — KPIs sessão

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Vendedor → operacoesLive 2. Abrir sessão da live

**Se estiver bem:** KPIs vendas/reservas coerentes com BD; drill-down linhas

#### A302 — Gravado sem playback_id

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir gravado do feed

**Se estiver bem:** Mensagem amigável; não spinner infinito; card Home pode mostrar sem play

#### A303 — Comprador vê lives ended no feed

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Buyer autenticado 2. Query/API feed

**Se estiver bem:** Row visível; player abre

#### A304 — Broadcast rifa no chat sem prefixo duplicado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Trigger broadcast rifa 2. Ver chat

**Se estiver bem:** Uma linha «🎟️ Rifa: …» humanizada; dedupe `raffle\|line`

#### A305 — Mensagem aceite visível no chat público (variante social)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Aceitar reserva 2. Ver chat

**Se estiver bem:** «{Nome} ficou com {Artigo}» **sem** prazo no público

#### A306 — Copy overlay «Ficaste com {Artigo}»

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Bot (simula comprador/vendedor na base de dados))*

**O que fazes:** 1. Seller aceita 2. Ver player comprador

**Se estiver bem:** Card verde/overlay com copy 2ª pessoa; coerente com saco; um único overlay (R1)

#### A307 — Preço € não aparece na linha «comprou»

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Compra 2. Ver chat

**Se estiver bem:** Só nome + artigo

#### A308 — Duas mensagens FOMO em ordem lógica

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Última unidade 2. Venda/aceite esgota

**Se estiver bem:** Primeiro «última unidade», depois «esgotou»; sem spam &gt;2

#### A309 — Mensagens com `|` ou campos ERP ocultas

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Inserir/msg com pipes 2. Render chat

**Se estiver bem:** `compactFromBody` vazio ou backoffice; não listada no público


### Directos gravados

#### A310 — Entrada directa VOD por URL

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir link

**Se estiver bem:** Modo replay; guards VOD activos

#### A311 — BD `ended` força VOD mesmo com isLive=true no link

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Abrir player

**Se estiver bem:** `_isVodReplay=true`; não trata como live activa

#### A312 — VOD aparece após complete-mux async

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Terminar 2. Abrir gravado &lt;60s 3. Esperar

**Se estiver bem:** Spinner → vídeo quando ID disponível; ou retry poll

#### A313 — Texto «Chat da gravação…» sem input

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir gravado 2. Ver área chat

**Se estiver bem:** Placeholder; `_showChatInput==false`

#### A314 — Não paginar histórico infinito em replay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Scroll chat topo

**Se estiver bem:** `enableOlderLoad=false`; só msgs do instante replay

#### A315 — Buyer não envia privado em VOD

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Tentar abrir privado

**Se estiver bem:** Oculto ou read-only; sem insert

#### A316 — Timer poll catálogo off em replay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Gravado 2 min

**Se estiver bem:** `_catalogStockPollTimer` não corre; stock actualiza só ao abrir

#### A317 — Compensação atraso início vídeo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Play t=0 2. Comparar 1ª msg visível vs timestamp real

**Se estiver bem:** 1ª msg alinhada ±skew configurado

#### A318 — Replay início limpa msgs posteriores

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seek para 0

**Se estiver bem:** Lista vazia ou só msgs t≈0

#### A319 — Mensagens acumuladas até playhead

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seek 50% duração

**Se estiver bem:** Msgs com timestamp ≤ playhead

#### A320 — Eventos «mostrar» conduzem vitrine replay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Replay 2. Cruzar event times com highlight

**Se estiver bem:** `_vodActiveItemId` = item do evento activo no instante

#### A321 — Feedback ao tentar chat live em gravado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Tap área chat/input se visível

**Se estiver bem:** Snack informa; não envia

#### A322 — Bag scope à live gravada

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Abrir gravado 2. Saco

**Se estiver bem:** Histórico completo dessa live; não mistura outras lives

#### A323 — Commerce pós-live sem studio activo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Buyer paga em gravado

**Se estiver bem:** Checkout funciona; seller vê depois em operacoesLive/pagamentos histórico

#### A324 — Rifa inactiva em gravado

**Corrida:** ❌ Falhou — O robô saltou porque já tinha feito um teste muito parecido na mesma sessão

**Tipo de falha:** 🔧 **INFRA** — Robô saltou o teste porque já tinha corrido um parecido na mesma sessão *(provavelmente não é bug da app)*

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir gravado 2. Ver rifa

**Se estiver bem:** Sem CTA participate; estado ended/cancelled

#### A325 — Contador viewers só em live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Ficar 60s no player

**Se estiver bem:** Sem `batata_live_viewer_ping` ou contador estático

#### A326 — Reserva em VOD gera linha social

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Reservar em gravado 2. Ver replay chat no instante

**Se estiver bem:** Msg existe na BD; em replay aparece no timestamp se durante sessão original — **nova** reserva pós-ended: comportamento definido (msg imediata ou n/a replay)

#### A327 — Resolver URL VOD quando live stream parou

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Resolver Mux URL

**Se estiver bem:** HLS VOD URL; não live RTMP

#### A328 — Asset Mux persistido

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. complete-mux-live 2. Query lives

**Se estiver bem:** `mux_asset_id` e `mux_vod_playback_id` preenchidos

#### A329 — Grid gravados no perfil vendedor

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Perfil vendedor 2. Tab lives

**Se estiver bem:** Só `status=ended`; tap abre VOD

#### A330 — Vendas em 2 gravados mesma linhagem

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Vendas em ambos 2. Novo live — ver pool

**Se estiver bem:** Pool Z82 agrega vendidos

#### A331 — Scrub bar altera vitrine replay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Arrastar scrub 2. Observar carrossel

**Se estiver bem:** Highlight muda sem lag &gt;1s

#### A332 — Histórico ref após venda em VOD

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Pagar 2. Query ref_histories

**Se estiver bem:** Entrada venda/gravado na linhagem

#### A333 — Comprador na live quando termina

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seller termina 2. Buyer continua

**Se estiver bem:** Modo VOD ou kick com mensagem; saco mantém

#### A334 — Mensagens com imagem no replay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Replay no instante da msg

**Se estiver bem:** Foto visível; username correcto

#### A335 — Venda VOD via marketplace product

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Comprar em gravado 2. Stock novo live

**Se estiver bem:** Conta no pool Z82 via product_id

#### A336 — Reconciliação UI sessão vs orders

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Comparar cada linha UI vs SQL

**Se estiver bem:** Totais iguais

#### A337 — Filtro ended no dashboard web

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir lives web dashboard

**Se estiver bem:** Lista ended; sem crash

#### A338 — Buyer lê msgs de live ended

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. SELECT live_messages como buyer

**Se estiver bem:** Rows visíveis

#### A339 — Produto marketplace reflecte stock pós-VOD

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir PDP produto 2. Ver stock

**Se estiver bem:** Stock alinhado pool; não oversell


### Cross-pool (várias lojas)

#### A340 — Stock partilhado RR1 — 8 disp / 2 vendidos

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Vender 1 un. na live (convert/pago) 2. Vender 1 un. no gravado (order `product_id` ou `live_item_id`) 3. Abrir novo live/catálogo

**Se estiver bem:** `available_qty=8`; `sold` ou equivalente = 2; **não** duplicar converted+order

#### A341 — Unidades bloqueadas noutro directo reflectidas na UI

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Aceitar reserva live A 2. Abrir catálogo live B e carrossel comprador

**Se estiver bem:** Catálogo B: **Disp** alinhado RPC; **Reservas** inclui blocked; sem Total errado

#### A342 — KPI Reservas inclui reservas noutras lives

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Criar reserva live A 2. Ver carrossel live B

**Se estiver bem:** `displayReservedQty` = local + cross; badge coerente

#### A343 — Branch SQL product_id-only em vendidos

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Inserir/simular order 2. RPC stock item live activo mesmo pool

**Se estiver bem:** `sold` inclui order; `available_qty` desconta

#### A344 — Reserva converted + order pago = 1 un. vendida

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Reconcile 2. Stock RPC

**Se estiver bem:** `sold` não soma 2x; distinct on order.id

#### A345 — Popup início live lista reservas gravado (linhagem)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep inherit 2. Iniciar directo

**Se estiver bem:** Sheet amarelo lista reserva; origem «Gravado»

#### A346 — Popup início live — origem Marketplace

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Iniciar live com ref ligada

**Se estiver bem:** Lista mostra origem Marketplace

#### A347 — Listar produto marketplace no catálogo live (TYPE A)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Toggle listar no catálogo 2. Sync

**Se estiver bem:** `live_items.item_kind=marketplace_product`; `list_on_marketplace=true`; checkout via product_id

#### A348 — Sincronização UI após venda noutro device

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de dados (staging) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de dados (staging))*

**O que fazes:** 1. Venda/aceite 2. Observar 10s ambos

**Se estiver bem:** Disp atualiza em ≤4s ambos; sem divergência &gt;1 un.

#### A349 — Sync prep não apaga listing marketplace

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep sync 2. Re-sync 3. Query

**Se estiver bem:** `list_on_marketplace` mantém; product_id intacto


### Marketplace

#### A350 — Navegação carrossel → PDP com contexto live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Entrar player 2. No card TYPE A, abrir PDP (tap info/título ou acção equivalente) 3. Inspeccionar params e UI

**Se estiver bem:** `ProductDetailsPageWidget` abre com `originLiveId`, `originLiveItemId`, `originSellerId`, `originIsLive=true`; produto marketplace correcto; **sem** forçar checkout live inline se acção for «ver detalhes»

#### A351 — Home feed lista produto após `list_on_marketplace=true`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller activa «Listar no marketplace» (prep ou mid-live) 2. Aguardar refresh feed 3. Abrir Home → tab Marketplace

**Se estiver bem:** Card aparece no feed (`products.list_on_marketplace=true`); thumbnail/título/preço marketplace; link PDP funcional

#### A352 — Venda live decrementa qty visível no PDP

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Registar qty inicial PDP (`products.quantity` + pool RPC) 2. Vender 1 un. na live (aceite+pagamento) 3. Reabrir/atualizar PDP

**Se estiver bem:** PDP qty/stock copy reflecte pool Z82 (`available_qty` −1); **não** oversell marketplace; alinhado A340 sem re-testar dedup

#### A353 — Superfícies mostram preço correcto por canal

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Ver card carrossel live 2. Abrir PDP marketplace 3. Comparar breakdowns

**Se estiver bem:** Carrossel/checkout **live** mostra 15€ (`resolveFreshUnitPrice`); PDP mostra 20€ (`products.price`); **sem** misturar valores na mesma superfície

#### A354 — Pool RR1 com vendas live, gravado e reserva marketplace

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Vender 1 un. live A (pago) 2. Vender 1 un. gravado B (`product_id` order) 3. Reserva marketplace pending (order `reserva_pendente`) 4. Ver carrossel, PDP, catálogo seller

**Se estiver bem:** `available_qty=7` (10−2 vendidos−1 reserva bloqueante); KPI Total·Disp·Reservas coerentes nas 3 superfícies; origem irrelevante para pool

#### A355 — PDP e live items partilham linhagem via `logical_item_id`

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Query linhagem 2. Venda/reserva noutro `live_item_id` mesma linhagem 3. Refresh PDP com `originLiveItemId`

**Se estiver bem:** Stock PDP (com contexto live) reflecte pool da linhagem, não só row local; ref history coerente

#### A356 — Prep mostra histórico vendas marketplace da ref

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Adicionar/seleccionar produto TYPE A no prep 2. Abrir sheet ref history / detalhe linhagem 3. Ver entradas

**Se estiver bem:** Lista inclui vendas marketplace (origem «Marketplace»); qty/preço/data; **sem** duplicar converted live+order

#### A357 — Toggle «Listar no marketplace» durante directo activo

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seller abre catálogo studio 2. Activa toggle marketplace mid-live 3. Comprador refresca Home + carrossel

**Se estiver bem:** `list_on_marketplace=true` imediato; item permanece no carrossel; feed marketplace actualiza (A351); checkout live continua TYPE A

#### A358 — Foto quick edit live propaga carrossel + PDP

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seller quick edit → alterar foto 2. Guardar 3. Ver carrossel comprador 4. Abrir PDP marketplace

**Se estiver bem:** `live_items.image_url` actualizado; carrossel mostra nova foto; PDP hero usa foto marketplace (`products.image`) **ou** sync policy documentada — **sem** foto quebrada/placeholder permanente

#### A359 — Shadow `live_only` ausente do feed marketplace

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Confirmar toggle marketplace indisponível ou OFF 2. Query feed Home 3. Busca directa por `product_id` shadow

**Se estiver bem:** Shadow **não** aparece Home/perfil marketplace; `list_on_marketplace=false`; checkout live usa shadow (A225); listing marketplace real intacto

#### A360 — Compra orgânica PDP — preço `products.price`, não live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Home → PDP 2. Comprar now / checkout sheet 3. Ver total Stripe metadata

**Se estiver bem:** `itemPrice = products.price` (20€); order `price_total` baseado marketplace; **≠** `resolveFreshUnitPrice` live; contraste explícito com A226

#### A361 — PDP indica sessão live activa ligada ao artigo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir PDP desde carrossel live 2. Ver hero/meta 3. Terminar live 4. Reabrir PDP

**Se estiver bem:** Com live activa: badge/chip «Em directo» ou equivalente + link voltar player; após `ended`: badge GRAVADO ou ausência «Em directo»; listing marketplace mantém-se

#### A362 — Reserva aceite noutro live reduz qty PDP

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Aceitar reserva live A 2. Abrir PDP (contexto live B ou orgânico com fetch pool) 3. Comparar qty

**Se estiver bem:** `_maxCheckoutQuantity` / stock copy usa `available_qty` RPC incluindo `blocked_qty` remoto; **≠** `products.quantity` bruto se pool menor

#### A363 — Reservas noutras lives visíveis no stock PDP

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Criar reserva live A 2. Abrir PDP live B 3. Ler copy Reservas/Disp

**Se estiver bem:** `displayReservedQty` inclui cross; copy «X reservadas» ou barra coerente; comprador não vê stock «livre» inflacionado

#### A364 — Toggle OFF remove marketplace feed; item permanece no carrossel

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Seller desactiva toggle marketplace mid-live 2. Refresh Home 3. Ver carrossel live

**Se estiver bem:** Feed marketplace **sem** card; carrossel live **com** item; `live_items` row intacta; checkout live TYPE A ainda possível

#### A365 — Marketplace listing sobrevive fim do directo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller termina live (`status=ended`) 2. Ver Home feed 3. Abrir PDP directo

**Se estiver bem:** Card marketplace permanece; PDP comprável; carrossel replay/gravado separado; pool Z82 continua (A340)

#### A366 — Total · Disp · Reservas alinhados catálogo ↔ marketplace

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Executar mix vendas/reservas (A354) 2. Ler KPI barra catálogo 3. Comparar RPC + PDP

**Se estiver bem:** «Total · Disp · Reservas» seller = RPC Z82; barra fundo carrossel comprador = Disp; **sem** puzzle 2/1 documentado A341

#### A367 — Order marketplace decrementa stock carrossel live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Completar order marketplace `pago` 2. Observar carrossel live B (poll 2s) 3. Ver catálogo seller

**Se estiver bem:** `available_qty` −qty order; carrossel actualiza; Z82 branch `product_id` conta (A343); feed qty coerente

#### A368 — Novo directo inherit marketplace item — 1 product row

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep Continuar inherit 2. Go-live 3. Query `products` + `live_items`

**Se estiver bem:** Mesmo `product_id`; **sem** duplicate `products` row; `list_on_marketplace` preservado; bridge intacto

#### A369 — Re-sync prep não quebra bridge marketplace↔live↔pool

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Prep re-sync / merge catálogo 2. Verificar flags marketplace 3. RPC stock 4. Feed + carrossel + PDP

**Se estiver bem:** Z52: `list_on_marketplace` + `product_id` intactos; Z82: pool qty correcto pós-merge; **sem** reset sold/blocked


### Ajudantes e staff

#### A370 — Seller convida colaborador por e-mail

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Perfil → Equipa / Colaboradores 2. «Adicionar colaborador» 3. Preencher e-mail + nome + permissões default 4. Confirmar

**Se estiver bem:** Row `seller_helpers` com `invitation_status=pending`, `active=false`; snack «Convite pendente»; helper vê banner convite (A371)

#### A371 — Colaborador aceita convite pendente

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Helper abre banner ou `HelperInvitationPage` 2. Tocar Aceitar 3. Ver contexto loja

**Se estiver bem:** `invitation_status=accepted`, `active=true`; `SellerStaffContext` muda para loja assistida; `StaffActionLog` `helper_invitation_accepted`

#### A372 — Painel operacional helper sobre HLS (sem câmara)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Painel operacional do ajudante sobre HLS **sem usar a câmara**.

**O que fazes:** 1. Helper → Acesso colaborador → Directo activo 2. Abrir `HelperLiveOpsPage` 3. Ver vídeo + painel studio

**Se estiver bem:** `LiveHlsViewer` reproduz stream; `LiveVendorStudioPanel` visível; **sem** botão emitir/câmara; orientação portrait

#### A373 — Helper com `can_manage_reservations` aceita reserva

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Buyer reserva artigo 2. Helper no painel operações 3. Tocar Aceitar

**Se estiver bem:** Reserva `accepted`; KPI vendedor actualiza; comprador vê estado aceite; log `live_vendor_studio_logs`

#### A374 — `can_end_live=false` — sem CTA terminar

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Helper no painel live ops 2. Procurar «Terminar directo» / encerrar 3. Tentar via menu se existir

**Se estiver bem:** CTA terminar **ausente** ou desactivado; live permanece `status=live`; seller owner ainda pode terminar

#### A375 — Helper sem permissão reservas — aceitar bloqueado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller edita helper → desliga «Gerir reservas» 2. Helper refresh/reopen painel 3. Tentar Aceitar

**Se estiver bem:** `SellerStaffGate` / RPC `batata_staff_has_permission` bloqueia; botão Aceitar oculto ou `_DeniedPanel`; **sem** mudança BD reserva

#### A376 — Alternar entre loja própria e loja assistida

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Perfil → badge contexto 2. «Modo pessoal» 3. «Loja X» 4. Ver `effectiveSellerId` em acções

**Se estiver bem:** `switchToOwnStore` / `switchToHelperSeller` actualizam permissões; prefs `batata_active_seller_staff_id_v1` persistem; KPI/encomendas filtram loja correcta

#### A377 — Colaborador recusa convite pendente

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Helper abre `HelperInvitationPage` 2. Tocar Recusar 3. Confirmar se dialog

**Se estiver bem:** `invitation_status=rejected`, `active=false`; convite some do banner; seller vê estado recusado na equipa

#### A378 — Remover/desactivar colaborador aceite

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller → Equipa 2. Editar helper → Desactivar ou Remover 3. Helper tenta reabrir painel live

**Se estiver bem:** `active=false` ou row removida; helper perde acesso imediato; `SellerStaffContext.refresh` sem link activo

#### A379 — Helper sem editar anúncios — catálogo live read-only

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante não pode editar anúncios — catálogo só leitura na live.

**O que fazes:** 1. Helper abre painel catálogo live 2. Tentar editar preço/stock/título 3. Tentar adicionar item

**Se estiver bem:** Campos desactivados ou `SellerStaffGate` bloqueia; **sem** RPC `batata_update_live_item` bem-sucedido

#### A380 — Dupla verificação terminar live (UI + servidor)

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Inspeccionar UI (A374) 2. (Opcional) forçar RPC end live com JWT helper

**Se estiver bem:** UI sem CTA; RPC servidor rejeita com erro permissão; live não `ended`

#### A381 — `can_change_current_item` — spotlight no carrossel

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Helper selecciona outro item «a mostrar» 2. Buyer observa carrossel player

**Se estiver bem:** `live_items.is_current` ou equivalente actualiza; compradores vêem novo spotlight ≤4s

#### A382 — `can_manage_chat` — resposta/moderar no studio

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Buyer envia mensagem 2. Helper abre painel chat 3. Responde ou aplica acção moderar (se existir)

**Se estiver bem:** Mensagem helper visível no chat público com identidade loja; sem leak ERP

#### A383 — Helper sem ver saldo/wallet/pagamentos

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante não deve ver saldo, wallet nem pagamentos.

**O que fazes:** 1. Helper em modo loja assistida 2. Navegar Perfil → Wallet / Pagamentos / KPI financeiro

**Se estiver bem:** Secções wallet e payouts **ocultas** ou `SellerStaffDeniedPage`; **sem** valores saldo

#### A384 — Helper não gere outros colaboradores

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Ajudante não pode gerir outros colaboradores.

**O que fazes:** 1. Helper tenta abrir `SellerHelpersPage` 2. Tentar convidar/remover membro

**Se estiver bem:** Rota bloqueada ou lista read-only; **sem** novo `seller_helpers` row

#### A385 — Convite falha se utilizador não registado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Adicionar colaborador com e-mail inexistente 2. Confirmar

**Se estiver bem:** Snack «Não encontrámos conta… deve registar-se primeiro»; **sem** insert `seller_helpers`

#### A386 — Segundo convite mesmo helper bloqueado

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller tenta convidar mesmo e-mail outra vez

**Se estiver bem:** Erro amigável ou no-op; **uma** row por par; log `staff.helper` duplicate

#### A387 — `helperLinkId` expirado ou de outro user

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir link na app 2. Ver estado página

**Se estiver bem:** Mensagem «convite não encontrado» ou redirect seguro; **sem** aceitar convite alheio

#### A388 — Seller muda perms — helper vê gate após refresh

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Dono muda permissões — ajudante vê portas bloqueadas após refrescar.

**O que fazes:** 1. Seller desliga `can_manage_reservations` 2. Helper pull-to-refresh ou reabre painel (`refresh()`) 3. Tentar aceitar

**Se estiver bem:** Gate bloqueia após `SellerStaffContext.refresh`; sem necessidade logout/login

#### A389 — Bypass UI não contorna servidor

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Chamar directamente RPC accept reserva com JWT helper (curl/app instrumentado) 2. Comparar com `serverCan()`

**Se estiver bem:** RPC servidor retorna erro/false; reserva `pending`; `SellerStaffContext.serverCan` === false


### Erros e casos limite

#### A390 — Timeout Supabase — snack retry sem crash

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Inject delay/timeout no RPC 2. Buyer reserva 3. Ver feedback UI

**Se estiver bem:** Snack/estado erro amigável; botão retry ou pull refresh; **sem** ANR; estado local não corrupto

#### A391 — Queda realtime — reconexão automática

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Toggle avião 10s 2. Restaurar rede 3. Enviar reserva/chat

**Se estiver bem:** Canal reconecta; eventos pendentes via poll fallback; UI sincroniza ≤10s

#### A392 — Edge Mux lenta — publish não fica zombie

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Novo directo 2. Simular timeout edge 3. Ver estado live + UI

**Se estiver bem:** Erro claro ao seller; live `draft` ou cleanup orphan; **sem** card LIVE fantasma na home

#### A393 — Corrida CI — dois flows mesmo seller/live

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Lançar `v2_seller_harness_accept` e buyer flow em paralelo 2. Observar aceites/stock

**Se estiver bem:** Sem double-accept inconsistente; stock ≥0; um flow não mata o outro (A063 guard)

#### A394 — Login Maestro sem Application Not Responding

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Flow `launch_fleaber_login` + `login_buyer` 2. Medir tempo até home 3. Ver logcat ANR

**Se estiver bem:** Login <30s; **sem** ANR; `dismiss_before_login` ok

#### A395 — Stress 5 compradores reservam em paralelo

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Bot dispara 5 `create_reservation` simultâneos 2. Query fila 3. Seller vê KPI

**Se estiver bem:** 5 rows `pending` com `queue_position` único 1..5; sem deadlock; seller vê 5 cards

#### A396 — Seller com 2 lives draft — só uma activa

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Criar live A draft 2. Criar live B draft 3. Publicar A 4. Ver B

**Se estiver bem:** Apenas A `live`; B permanece `draft`; `findActiveLiveForSeller` retorna A

#### A397 — Publish device A não morre com login fullSweep device B

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. A em broadcast 2. B login trigger `reconcileOnAppStart(fullSweep:true)` 3. A continua; buyer no player

**Se estiver bem:** Live A permanece `live`; `isBroadcastInProgress` / H07 protege; buyer stream OK

#### A398 — H07 pipeline — bot prepara, Maestro valida

**Corrida:** ❌ Falhou — O robô automático não chegou ao ecrã certo (login, botões ou emulador lento) — tu confirmaste que manualmente a navegação funciona

**Tipo de falha:** 🧭 **NAVEGAÇÃO** — Botão ou ecrã não encontrado pelo robô (toque Maestro não dispara navegação real) *(auditoria diz que a app está OK — falso alarme do robô)*

**Auditoria (logs/prints):** ✅ Confirmado passou — UX+BD

**Automatização:** 🤖 Híbrido (dados + ecrã)

**O que fazes:** 1. `tool/` bot seed live MAESTRO 2. Maestro seller accept 3. Script SQL assert

**Se estiver bem:** Reserva `accepted`; logs studio; Maestro verde; BD match script

#### A399 — Checkout com autenticação forte Stripe

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Pagamento com autenticação forte Stripe (3D Secure).

**O que fazes:** 1. Pagar saco/single 2. Completar challenge 3DS no browser 3. Resume app

**Se estiver bem:** `orders.status=pago`; reserva `converted`; context reconcile após 3DS

#### A400 — Overlay web studio — dialog qty (C8B)

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Buyer Pagar com qty>stock 2. Ver overlay web seller 3. Comparar com app nativo A204

**Se estiver bem:** Dialog qty urgente no overlay web; paridade copy com app; sem Stripe até resolvido

#### A401 — Token Supabase expira mid-session — auto-refresh

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Forçar refresh token (ou esperar TTL curto staging) 2. Reservar artigo 3. Ver sessão

**Se estiver bem:** `SupaFlow` refresh transparente; acção RPC sucesso; **sem** redirect login

#### A402 — Refresh falha — utilizador deslogado com mensagem

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Invalidar sessão remotamente 2. User tenta acção RPC 3. Ver navegação

**Se estiver bem:** Redirect login; snack «sessão expirada»; **sem** crash; dados locais sensíveis limpos

#### A403 — Sem rede — reserva com feedback retry

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Tocar Reservar 2. Ver erro 3. Restaurar rede 4. Retry

**Se estiver bem:** Snack offline; botão retry; 1 reserva após rede OK; **sem** ghost pending local

#### A404 — Vendedor offline — aceitar não aplica silenciosamente

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Cortar rede 2. Tocar Aceitar 3. Restaurar rede

**Se estiver bem:** Erro visível ou retry automático; estado final `accepted` **uma vez**; sem double-accept

#### A405 — Retomar app após background prolongado

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Home OS 5min 2. Reabrir app 3. Ver vídeo + chat + reservar

**Se estiver bem:** HLS reconecta; realtime/poll activo; saco actualiza; **sem** tela preta permanente

#### A406 — Duplo tap Reservar — dedupe ou increment qty

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Double-tap rápido «Reservar» 2. Query BD

**Se estiver bem:** **1** row pending OU increment `requested_qty` (R6); **não** 2 rows duplicadas mesma ref

#### A407 — 10+ reservas rápidas mesmo buyer — throttling

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Disparar 15 create_reservation em 3s 2. Ver respostas

**Se estiver bem:** Erro 429 ou rejeição após limite; BD com ≤N rows razoável; seller KPI não explode

#### A408 — Spam chat público — throttle

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Enviar 20 mensagens em 5s 2. Ver UI + BD

**Se estiver bem:** Bloqueio temporário ou drop; snack «demasiado rápido»; chat legível

#### A409 — Falha edge pagamento — UI retry sem perder saco

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Pagar 2. Edge falha 3. Retry após fix

**Se estiver bem:** Snack erro; reserva intacta `accepted`; retry abre Stripe; **sem** order fantasma

#### A410 — Pós-Stripe sem rede — context pending sobrevive

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 👤 Só manual — Depois do Stripe, cortar a rede e ver se o estado pendente sobrevive.

**O que fazes:** 1. Pagar Stripe 2. Cortar rede antes resume 3. Restaurar rede 4. `tryResumeOnAppResumed`

**Se estiver bem:** `FleaberStripeCheckoutContext` prefs intactas; reconcile corre quando online; converted

#### A411 — Colaborador não acede dados de outra loja

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Chamar accept/update com seller_id alheio 2. Ver erro

**Se estiver bem:** RLS ou RPC rejeita; **sem** leak rows loja B

#### A412 — Directo termina durante checkout — Pagar bloqueado

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir checkout sheet 2. Seller end live 3. Buyer confirma Pagar

**Se estiver bem:** Erro ou CTA desactivado; edge rejeita se `status=ended`; **sem** cobrança órfã

#### A413 — Force-close durante broadcast — cleanup no próximo start

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Publicar live 2. Force-kill app 3. Reabrir app (sem fullSweep kill MAESTRO)

**Se estiver bem:** `reconcileOnAppStart` fecha orphan **ou** retoma se `isBroadcastInProgress`; home sem card fantasma

#### A414 — Logout/login outro buyer — saco isolado

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Buyer A reserva 2. Logout 3. Login Buyer B 4. Abrir mesmo live saco

**Se estiver bem:** Saco B vazio ou só rows B; **sem** ver reservas A; Stripe context limpo

#### A415 — Seller + helper aceitam simultaneamente — idempotente

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Disparar accept RPC quase simultâneo nos 2 devices 2. Query estado

**Se estiver bem:** `accepted` uma vez; stock decrementa uma vez; segundo accept no-op ou erro seguro

#### A416 — Subscription morta — poll corrige UI

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Simular realtime off 2. Outro user reserva 3. Observar buyer UI

**Se estiver bem:** Stock/chat actualiza via poll em ≤4s; sem divergência permanente

#### A417 — Pressão memória — player não ANR/crash

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir player 2. Background/foreground repetido 3. Monitor logcat

**Se estiver bem:** **Sem** crash OOM; **sem** ANR; HLS recover ou erro gracioso

#### A418 — Navegação para live inexistente

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Maestro (robô no telemóvel)

**O que fazes:** 1. Abrir link app/universal 2. Ver ecrã

**Se estiver bem:** Erro amigável «Directo não encontrado»; redirect home; **sem** crash

#### A419 — Stock 1, N buyers — só posição #1 aceitável sem overbook

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Bot (simula comprador/vendedor na base de dados)

**O que fazes:** 1. Bot: 3 pending queue 1..3 2. Seller aceita #1 3. Tentar aceitar #2

**Se estiver bem:** #1 `accepted`; #2 waitlist ou dialog over-stock; stock 0; **sem** double-sell


### Sincronização de dados

#### A420 — Auditoria studio — eventos críticos logados

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Aceitar reserva 2. Definir preço 3. Trigger qty gate 4. Query logs

**Se estiver bem:** Rows `live_vendor_studio_logs` com `event_type` esperados (`reservation.accept`, `checkout.pay_qty_gate`, etc.)

#### A421 — Recompact fila após remove/cancel

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Remover/cancelar position #2 2. RPC `batata_recompact` ou trigger 3. Query positions

**Se estiver bem:** Positions contínuas 1..N sem buracos; ordem FIFO temporal preservada

#### A422 — Timer poll cancela ao sair do ecrã

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de código (rápido)

**O que fazes:** 1. Abrir home live grid 2. Navegar fora 3. Inspeccionar timers (debug)

**Se estiver bem:** Poll cancelado no `dispose`; **sem** leak timer; **sem** requests após sair

#### A423 — Painel pagamentos lista antes de totais agregados

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Abrir painel Pagamentos 2. Ver ordem render 3. Comparar com R5 spec

**Se estiver bem:** Lista linhas convertidas **antes** de bloco totais/KPI; totais correctos

#### A424 — Apenas buyer da order pode reconcile/convert

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Buyer B chama `batata_live_reconcile_stripe_order` ou edge settle com order alheia

**Se estiver bem:** 403/erro; order inalterada; **sem** converted cross-user

#### A425 — RLS impede leak mensagens privadas no chat público

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Seller envia privado a buyer X 2. Buyer Y query `live_messages` / UI chat

**Se estiver bem:** Y **não** vê msgs privadas; RLS filtra; público só `kind` permitidos

#### A426 — Modo chat privado seller↔buyer no studio

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Buyer envia pergunta 2. Seller responde em thread privada 3. Ver público

**Se estiver bem:** Thread privada persistida; badge unread (A101); **não** duplica no público

#### A427 — Egress órfão LiveKit — job cleanup

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Simular kill mid-egress 2. Executar cron/cleanup 3. Ver LiveKit + BD

**Se estiver bem:** Egress terminado; sem custo leak; `lives` coerente ended

#### A428 — Card gravado home — thumbnail sem autoplay

**Corrida:** 👤 Manual — Robô não corre — checkpoint manual

**Auditoria (logs/prints):** ⏳ Ainda não auditado

**Automatização:** 🤖 Teste de código (rápido) *(na corrida de 16 Jun aparecia como manual sem correr; hoje tem Teste de código (rápido))*

**O que fazes:** 1. Scroll home 2. Ver card VOD 3. Confirmar sem player inline

**Se estiver bem:** Thumbnail estática/poster; **sem** HLS autoplay no feed; tap abre replay

#### A429 — `available_qty` decrementa exactamente 1× por aceite

**Corrida:** ✅ Passou

**Auditoria (logs/prints):** — (teste de dados/código; não há ecrã para rever)

**Automatização:** 🤖 Teste de dados (staging)

**O que fazes:** 1. Aceitar 2. Query `live_items.available_qty` 3. Repetir até stock 0

**Se estiver bem:** Cada aceite qty1 decrementa 1; em stock 0 próximo pending → waitlist; **sem** negativo


---

## Bateria extra T01–T21 (comprador + vendedor em 2 telemóveis)

Ver tabela actualizada em `tool/TEST_BATTERY_LIVE.md` — resumo: a maioria dos T01–T21 **passou** (login vendedor/comprador, reservas, stock, rifa). T08e e T21 são pagamento Stripe **manual**.
