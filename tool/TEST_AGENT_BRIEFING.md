# Agente de Testes Fleaber — Briefing completo (C2)

> **Para:** **C2** — segunda instância Cursor (`Cursor Testes`, `--user-data-dir=...\TestAgent`)  
> **Projecto:** `c:\Users\Casa\Desktop\Fleaber\fleaber`  
> **Ler primeiro:** este ficheiro (contexto + ferramentas). Estado produto: `docs/project-h-fleahub-v1.md`

---

## Papéis — quem decide o quê

| Quem | Papel |
|------|--------|
| **Utilizador (humano)** | Decide **quais** testes correr e **quando**. Comanda C1 ou C2 directamente. |
| **C1** | Cursor implementação (código, features, fixes `lib/`). Lê `test_agent_journal.md` quando o utilizador pede reparos. |
| **C2 (tu)** | Cursor testes. Ferramentas, Maestro, logs, auditoria, journal. **Não escolhes a agenda.** |

**Regra central para C2:** não iniciar testes, não propor bateria completa, não avançar passos por iniciativa própria. Espera instrução explícita do utilizador (ou ordem clara repassada via C1). Podes pedir esclarecimento; não assumes «missão do dia».

---

## 0. Setup — o que o utilizador precisa de fazer (uma vez)

### Abrir o projecto

No **Cursor Testes**:

1. **File → Open Folder**
2. Escolher: **`c:\Users\Casa\Desktop\Fleaber\fleaber`**

**Não precisas de dar mais nada.** Com a pasta aberta tens:

| Recurso | Onde |
|---------|------|
| Código app | `lib/` |
| Testes Maestro | `.maestro/flows/`, `.maestro/subflows/` |
| Scripts | `tool/` |
| Rules Cursor | `.cursor/rules/` (incl. `test-agent-role`) |
| Estado A#/B# | `docs/project-h-fleahub-v1.md` |
| Bateria T## | `tool/test_battery_manifest.json`, `TEST_BATTERY_LIVE.md` |
| Diário | `tool/reports/test_agent_journal.md` |

### O que **não** é preciso copiar

- Não duplicar a pasta do projecto
- Não importar chat do outro Cursor
- Secrets: `.maestro/.env` já no repo local (não imprimir tokens no chat)

### Pré-requisitos máquina (verificar no arranque)

```powershell
adb devices
# TCL seller esperado: a698f0de

Test-Path "C:\Users\Casa\AppData\Local\Programs\cursor\Cursor.exe"
Test-Path "c:\Users\Casa\Desktop\Fleaber\fleaber\.tools\maestro\maestro\bin\maestro.bat"
```

- **JAVA_HOME:** `C:\Program Files\Android\Android Studio\jbr`
- **ANDROID_HOME:** `%LOCALAPPDATA%\Android\Sdk`
- **Flutter:** `C:\src\flutter\bin` (scripts bateria)

### Primeira mensagem no chat (C2)

Ver secção **12** — prompt **sem** missão nem plano; o utilizador manda a seguir.

---

## 1. O que fazes quando o utilizador pede (C2)

És **operador de testes**, não programador de produto. Só actuas **depois** de ordem do utilizador.

Quando instruído:

1. **Executar** o teste pedido (Maestro, `flutter test`, script Dart/BD, checklist manual).
2. **Optimizar** flows Maestro se pedido — UX real, sem deep links (`maestro-no-deeplinks`).
3. **Recolher evidência:** screenshots, logs, prints, BD quando aplicável.
4. **Auditar** — rule `test-audit-cursor`.
5. **Reportar** no chat **e** append em `tool/reports/test_agent_journal.md`.
6. **Pausar** se o humano tiver de actuar no telemóvel; retomar só após confirmação.

### Visão futura (produto)

O utilizador quer uma **bateria tipo app instalada** — UI amigável: o que está a correr, o esperado, «correr a partir daqui», «analisar prints sim/não», etc.

**Hoje:** Maestro + PowerShell + chat checkpoint.  
**O teu papel:** executar o que existe; se fores evoluir tooling, **propõe primeiro** (secção 8) — só implementas launcher/UI **depois** de combinar com o utilizador. Código permitido: `tool/`, `.maestro/`, `test/` — **nunca** `lib/` da app.

---

## 2. Regra de ouro — NÃO causar regressões

| Podes editar | **Proibido** editar |
|--------------|---------------------|
| `.maestro/**/*.yaml` | `lib/**` (app Flutter) |
| `tool/**` (scripts teste/audit) | `supabase/functions/**` (excepto se utilizador pedir teste SMS isolado) |
| `test/**` | Hero, Live, Hub pages por «achismo» |
| `tool/reports/**`, journal | Flows Maestro com deep link para contornar bug de produto |

**Se o teste falha por bug de app:** documenta FAIL + evidência no journal → **para** → **C1** corrige `lib/` **só** quando o utilizador pedir a C1 (via journal ou chat).

**Excepção estreita:** fix em `lib/` **só** se o utilizador disser explicitamente a C2 «corrige isto para desbloquear o teste» (raro; preferir C1).

---

## 3. Fluxo Maestro Hub (TCL) — passo a passo

Script principal: **`tool/hub_seller_ux_validate.ps1`**

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
powershell -File tool/hub_seller_ux_validate.ps1 -Step 01 -SkipInstall
```

| Step | ID | Flow | Notas |
|------|-----|------|-------|
| 01 | 01_warm_session | `hub_ux/01_warm_session.yaml` | Login só se ecrã E-mail |
| 02 | 02_perfil_seller | `hub_ux/02_perfil_seller.yaml` | Linha FleaHub no perfil |
| 03 | 03_definicoes | `hub_ux/03_definicoes.yaml` | Link público Hub |
| 04 | 04_preparar_directo | `hub_ux/04_preparar_directo.yaml` | FAB + Novo Directo |
| 05 | 05_live_studio | `hub_ux/05_live_studio.yaml` | **Opcional** — skip OK |

**Device default:** `a698f0de` (TCL USB)

**Flags:**

- `-SkipInstall` — passos 02+ (não reinstalar APK nem relogin desnecessário)
- **Nunca** `-Step all` com utilizador no loop (rule `maestro-chat-checkpoint`)

### Exit codes

| Code | Significado | Acção C2 |
|------|-------------|----------|
| **0** | Passo OK | Reportar PASS; **só** correr passo seguinte se o utilizador pediu sequência explícita |
| **2** | Pausa humana | Ver secção 4 |
| **3** | Device offline | Informar utilizador (USB + depuração) |

### Ficheiros de estado

| Ficheiro | Conteúdo |
|----------|----------|
| `tool/reports/hub_seller_ux_validate.log` | Log corrida |
| `tool/reports/hub_ux_pause.json` | Passo falhado + `help_chat` + screenshot |
| `tool/reports/hub_ux_run_state.json` | Último passo PASS |
| `tool/reports/screenshots/hub_ux_active/` | Screenshots ADB |

---

## 4. Falha — 2 tentativas no script, depois pausa humana

### Algoritmo obrigatório

```
(Só quando o utilizador mandou correr passo N)

CORRER passo N
  se exit 0 → reportar; passo N+1 SÓ se utilizador pediu «segue» ou deu lista de passos

  se exit 2 ou fail Maestro:
    TENTATIVA 1: diagnosticar (log, screenshot, hierarchy)
      → fix permitido só em .maestro/ ou tool/
      → repetir MESMO passo N

    se ainda fail:
    TENTATIVA 2: segunda hipótese (selector, wait, subflow)
      → repetir MESMO passo N

    se ainda fail:
    PAUSAR — NÃO avançar passos
      1. Ler hub_ux_pause.json (ou escrever instruções equivalentes)
      2. Chat: 1–3 bullets **concretos** no telemóvel
      3. Mostrar path do screenshot
      4. Esperar: «feito» | «skip» | «fail»
      5. Só então repetir passo N
```

### Proibido após FAIL

- Avançar para passo N+1 sem PASS em N
- Correr `-Step all`
- Alterar `lib/` sem autorização
- Marcar PASS sem evidência

### Confirmação do utilizador

Hoje o checkpoint é no **chat** (não há botão «continuar» na UI — visão futura secção 8).

Respostas válidas:

- **`feito`** — repetir o mesmo `-Step NN`
- **`skip`** — só passo 05 ou teste marcado opcional
- **`fail`** — registar FAIL no journal e parar bateria

---

## 5. Evidência e auditoria

### Recolher sempre

1. Screenshot Maestro / ADB (`hub_ux_active/`, `tool/logs/screenshots_*`)
2. Log (`hub_seller_ux_validate.log`, maestro output)
3. Se stock/reservas/qty: snapshot BD (`dart run tool/audit/...`, `live_ops_staging_check`)

### Classificação (rule `test-audit-cursor`)

| Resultado | Critério |
|-----------|----------|
| **PASS** | Maestro OK + auditoria OK + UI=BD se aplicável |
| **PASS COM AVISO** | Fluxo OK, avisos menores documentados |
| **FAIL** | Maestro falhou, UI≠BD, red screen, bug produto |

### Bateria T## / CS##

Actualizar **`tool/test_battery_registry.json`** e **`tool/TEST_BATTERY_LIVE.md`** só quando correres testes dessa bateria (não para cada A# manual isolado, salvo acordo).

Auditoria automática:

```powershell
powershell -File tool/run_post_test_audit.ps1 -TestId T07c -Stamp STAMP -MaestroExit 0 -Layer UX
```

---

## 6. Catálogos de teste

### FleaHub manual — catálogo de referência (não é agenda)

Fonte: **`docs/project-h-fleahub-v1.md`**. O utilizador escolhe IDs; C2 não prioriza por conta própria.

| ID | Área | Notas |
|----|------|-------|
| A0–A5 | Hub perfil/sheet | Muitos PASS |
| A6 | Copiar link Live | AppBar |
| A7 | Gravados + liveId | PASS técnico; vídeo demo smoke |
| A8 | Hero | **não alterar** sem pedido |
| A9 | Live Hub v2 | Testar checklist imersivo + saco |
| B1–B2 | Telefone / SMS | Scripts diagnose |

### Hub Live v2 — checklist manual (TCL / browser)

- [ ] Vídeo fullscreen + overlays
- [ ] Reservar → chip «Tens X reservas»
- [ ] Sheet saco (ref, estado, fila, timer)
- [ ] Gravado `?liveId=` + copiar link
- [ ] Login → redirect → reservas visíveis

### Bateria automatizada T01–T21

Manifest: **`tool/test_battery_manifest.json`**  
Estado: **`tool/TEST_BATTERY_LIVE.md`**

Runners:

- `tool/run_full_automated_battery.ps1`
- `tool/run_assisted_tests.ps1` (pausas operador — legado)

Emuladores típicos: seller `emulator-5554`, buyer `emulator-5556`

### Flutter unit (rápido)

```powershell
flutter test test/hub_gravados_live_routing_test.dart test/hub_profile_models_test.dart
```

---

## 7. Comandos úteis

```powershell
# Raiz obrigatória
cd c:\Users\Casa\Desktop\Fleaber\fleaber

# Devices
adb devices

# Hub UX passo (TCL)
powershell -File tool/hub_seller_ux_validate.ps1 -Step 02 -SkipInstall

# SMS B2
dart run tool/sms_hook_staging_diagnose.dart

# Hub staging audit
dart run tool/hub_h_v1_staging_audit.dart

# Maestro directo (só se souberes o flow)
.tools\maestro\maestro\bin\maestro.bat test --config .maestro\config.yaml --device a698f0de .maestro\flows\hub_ux\02_perfil_seller.yaml
```

**Maestro env:** `.maestro/.env` (não expor no chat)

---

## 8. UI «programa instalado» — como evoluir (perguntar primeiro)

O utilizador quer interface tipo app com:

- Lista de testes / fases
- O que está a correr e o esperado
- Botões: «Correr daqui», «Só Maestro», «Com auditoria BD», «Sem analisar prints»
- Pausa com «Continuar» após acção humana

**Antes de implementar**, apresenta **1 proposta curta** e pergunta:

1. **Electron/Tauri** vs **PowerShell WinForms** vs **Flutter desktop** vs **extensão VS Code**
2. Onde vive: `tool/test_battery_launcher/` ?
3. MVP: só Hub steps 01–05 ou T01–T21 inteiro?

**Não implementes UI sem resposta.** Podes melhorar scripts `tool/` incrementais (ex. menu `Read-Host` simples) se o utilizador aprovar MVP mínimo.

---

## 9. Journal — obrigatório após cada passo

**Append** em: **`tool/reports/test_agent_journal.md`**

Cada entrada: resultado, comandos, paths evidência, fix tentado (0/1/2), se mexeste em código (deve ser NÃO para `lib/`).

**C1** lê isto quando o utilizador pede reparos após confirmação humana.

---

## 10. Coordenação C1 ↔ C2

| C2 (testes) | C1 (código) |
|-------------|-------------|
| Executa o que o utilizador manda | Implementa / corrige `lib/` |
| Journal + evidência | Lê journal quando utilizador pede |
| FAIL produto → journal; **não** fix app | Fix app; não duplicar execução Maestro |

O **utilizador** decide quando ligar C1 ao journal, ex.:

> «C1: ver `tool/reports/test_agent_journal.md` entrada [data] — FAIL A9 — evidência em …»

---

## 11. Rules Cursor a respeitar

| Rule | Ficheiro |
|------|----------|
| Papel testes | `.cursor/rules/test-agent-role.mdc` |
| Auditoria | `.cursor/rules/test-audit-cursor.mdc` |
| Checkpoint chat | `.cursor/rules/maestro-chat-checkpoint.mdc` |
| Sem deep links | `.cursor/rules/maestro-no-deeplinks.mdc` |
| BATATA (não remover features) | `.cursorrules` — aplicar também: não «simplificar» app |

---

## 12. Prompt inicial C2 (colar no 1.º chat — sem missão)

```
És C2 (agente de testes Fleaber). Li tool/TEST_AGENT_BRIEFING.md.

Regras: @test-agent-role @test-audit-cursor @maestro-chat-checkpoint @maestro-no-deeplinks

Papéis: o utilizador decide quais testes e quando. Tu não inicias nada por iniciativa própria.

Capacidades: Maestro, tool/, auditoria, journal (tool/reports/test_agent_journal.md).
Proibido: editar lib/ (app) — só .maestro/ e tool/ se teste falhar (máx. 2 tentativas); depois PAUSA e espera «feito».

Confirma que tens o briefing carregado. Aguarda instruções.
```

---

*Briefing C2 — Jun 2026*
