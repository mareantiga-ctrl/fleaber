# Maestro — smoke UI live ops (V1)

[Fleaber automação](./live-ops-automacao-batata.md) · [Testes manuais](./live-ops-testes-batata.md)

## Pré-requisitos

1. **Android:** telemóvel USB com depuração USB **ou** emulador API 30+.
2. **APK debug** instalada (`flutter build apk --debug` ou `flutter run`).
3. `tool/live_ops_staging.env` configurado (mesmas contas que V0).
4. **Maestro CLI** instalado ([instruções](https://maestro.mobile.dev/getting-started/installing-maestro)).

### Windows (PowerShell) — instalação nativa

1. **Java 17+** — no Fleaber já tens o JBR do Android Studio (`C:\Program Files\Android\Android Studio\jbr`). O script `tool/run_maestro.ps1` usa-o automaticamente.

2. **Descarregar Maestro** (release oficial):

   - Abre: https://github.com/mobile-dev-inc/Maestro/releases/latest  
   - Ficheiro: **`maestro.zip`**

3. **Extrair** para `C:\maestro` (ou deixa o projeto usar `.tools\maestro\` — o agente pode descarregar aí).

4. **PATH** (PowerShell, uma vez; fecha e reabre o terminal):

```powershell
setx PATH "$env:PATH;C:\maestro\bin"
setx JAVA_HOME "C:\Program Files\Android\Android Studio\jbr"
```

5. **Verificar:**

```powershell
maestro --version
```

**Alternativa:** WSL2 + `curl -fsSL "https://get.maestro.mobile.dev" | bash` (não recomendado se já usas emulador Windows).

**Nota:** `iwr https://get.maestro.mobile.dev | iex` no PowerShell **não funciona** (script é bash).

## Preparar dados (1× por sessão de teste)

```bash
dart run tool/maestro_prepare_live.dart
```

Gera `.maestro/.env` com `MAESTRO_LIVE_ID`, logins buyer/seller, etc.

## Correr flows (Windows — recomendado)

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
dart run tool/maestro_prepare_live.dart
powershell -ExecutionPolicy Bypass -File tool\run_maestro.ps1
```

Um fluxo só:

```powershell
powershell -File tool\run_maestro.ps1 -Flow v1_01_login_buyer_home.yaml
```

O script `run_maestro.ps1` lê `.maestro/.env`, instala o APK debug e invoca o CLI em `.tools/maestro/`.

## Mapa flows ↔ doc manual

| Flow | Doc manual | O que valida |
|------|------------|--------------|
| `v1_01_login_buyer_home` | — | Login comprador → Home |
| `v1_02_buyer_live_player` | entrada live | Deep link player + «Saco da live» |
| `v1_03_buyer_bag_sheet` | **#1** parcial / saco | Abre saco + botão «Pagar» (sem Stripe) |
| `v1_04_seller_preparar_directo` | — | FAB criar → Novo Direto |
| `v1_05_seller_live_studio_smoke` | **#3/#4/#7** UI parcial | Operação / Pagamentos se painel studio visível |

**V2 (futuro):** pagamento Stripe test card (#6, #7 completo), cancelar saco (#4 UI).

## Ordem recomendada antes do APK manual

```bash
flutter test
dart run tool/live_ops_staging_check.dart
dart run tool/maestro_prepare_live.dart
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
maestro test .maestro/flows/
```

## Falhas comuns

| Sintoma | Acção |
|---------|--------|
| `maestro` não encontrado | Instalar CLI (acima) |
| Login timeout | Credenciais em `.maestro/.env`; conta existe em Auth |
| «Saco da live» não aparece | `MAESTRO_LIVE_ID` errado; voltar a correr `maestro_prepare_live.dart` |
| Permissões câmara | Flow `dismiss_permissions`; no seller usar `v1_04` em vez de `v1_05` |
| Deep link não abre | Confirmar `AndroidManifest` scheme `fleaber://fleaber.com` |

## V1.5 — Estado actual (honesto)

O script `run_maestro_v15_reserve.ps1` **ainda nao e fiavel de ponta a ponta** no teu ambiente. Motivos observados:

| Bloqueio | Efeito |
|----------|--------|
| **Mux / `create-mux-live`** | Timeout ou live presa em «A preparar a câmara…» → painel «Operação» nao aparece ou BD sem `status=live` |
| **Dois processos Maestro** | Buyer demora ~2 min → seller perde studio; passo 3 com `launchApp` piora |
| **Emulador 5554** | Pouco storage; login flaky |
| **5556 flutter_emulator** | Evitar (login/UI) |

**O que ja corre bem**

- **V0** (`flutter test` + `live_ops_staging_check.dart`) — logica #3/#4/#6/#7 na BD.
- **Seller studio** no **Pixel 10 (`emulator-5558`)** — quando Mux responde.
- **Buyer reserva** no **5554** — quando `MAESTRO_LIVE_ID` esta certo.

### Plano B (recomendado ate Mux estar estavel)

1. **Tu** no **5558**: login seller → Criar directo → «Iniciar Direto» → «Operação» → «A tratar» (fica aberto).
2. Noutro terminal:

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
dart run tool/maestro_sync_seller_live.dart --wait-seconds=90
powershell -File tool\run_maestro_flow.ps1 -FlowPath .maestro/multidevice/buyer_login_and_reserve.yaml -Device emulator-5554 -DriverHostPort 7002 -SkipInstall
dart run tool/maestro_v15_verify_queue.dart
```

3. **Tu** no **5558** (sem fechar o directo): confirmas visualmente **Aceitar** em «A tratar».

`maestro_v15_verify_queue.dart` = **PASS/FAIL na BD** (reserva pending do buyer). Isto prova a fila mesmo se o passo 3 Maestro falhar.

Pairing por defeito no script: **seller=5558**, **buyer=5554**.

**Com 2× Pixel 10 Pro XL** (2026-06-04): passos 1–2 do orquestrador **PASS**; passo 3 falha se o seller perder foreground — o YAML `seller_sees_reservation` reabre `criarDirecto` e assert **Aceitar** (PASS). `dart run tool/maestro_v15_verify_queue.dart` confirma a BD.

---

## V1.5 — Multi-dispositivo (buyer ↔ seller)

### Maestro suporta 2 devices no nosso setup?

**Sim**, localmente: dois processos Maestro em paralelo **ou** (recomendado no Windows) **sequencial** com:

- `--device <udid>` (ex. `emulator-5554`)
- `--driver-host-port <porta>` diferente por dispositivo (`7001` seller, `7002` buyer) para evitar conflito do driver

**Não** existe um único YAML que orquestre os dois telemóveis com handoff; o orquestrador é `tool/run_maestro_v15_reserve.ps1`.

### Estratégia mais simples (Windows)

1. Dois dispositivos visíveis em `adb devices` (2 emuladores **ou** 1 emulador + 1 telemóvel USB).
2. Credenciais e devices em `tool/live_ops_staging.env` (opcional `MAESTRO_DEVICE_SELLER` / `MAESTRO_DEVICE_BUYER`).
3. Um comando orquestrado — **sem alternar cliques manualmente** entre A e B.

### Segundo dispositivo: emulador ou telemóvel?

| Opção | Como |
|--------|------|
| **2º emulador** | Android Studio → Device Manager → Start outro AVD (ex. `emulator-5556`). |
| **Telemóvel físico** | Depuração USB ON → `adb devices` deve listar o serial (ex. `R58N…`). |

Não é obrigatório telemóvel físico; dois emuladores são suficientes.

### Comandos exatos (cenário 1)

```powershell
cd c:\Users\Casa\Desktop\Fleaber\fleaber
flutter build apk --debug
adb devices

# Opcional em tool/live_ops_staging.env:
# MAESTRO_DEVICE_SELLER=emulator-5554
# MAESTRO_DEVICE_BUYER=emulator-5558

dart run tool/maestro_prepare_live.dart --multi
powershell -ExecutionPolicy Bypass -File tool\run_maestro_v15_reserve.ps1
```

O script:

1. **Seller (A)** — login, `criarDirecto`, «Iniciar Direto», abre «Operação» → «A tratar».
2. **Sync** — `maestro_sync_seller_live.dart` lê a live `status=live` do seller, grava `MAESTRO_LIVE_ID` e semeia `Maestro smoke item`.
3. **Buyer (B)** — deep link player, toca «Reservar».
4. **Seller (A)** — `clearState: false`, assert «Aceitar» + título do artigo.

Flows: `.maestro/multidevice/`.

### Emuladores recomendados (Windows)

| Papel | UDID típico | AVD |
|--------|-------------|-----|
| Seller | `emulator-5554` | Pixel 8 (ou similar) |
| Buyer | `emulator-5558` | **Pixel 10** |

**Não usar** `emulator-5556` se o AVD for `flutter_emulator` — o Maestro reporta esse nome e o login UI falha (teclado / «Entrar»). Não é bug da app; troca para Pixel 10 (`5558`) ou define `MAESTRO_DEVICE_BUYER` em `tool/live_ops_staging.env`.

Podes desligar o AVD `flutter_emulator` no Device Manager para não confundir portas ADB.

### Falhas V1.5

| Sintoma | Acção |
|---------|--------|
| «precisa de 2 dispositivos» | Ligar 2º emulador ou telemóvel; `adb devices` |
| Maestro «Running on flutter_emulator» | Buyer em `5556` — mudar para `emulator-5558` |
| Timeout sync live | Seller não chegou a «Iniciar Direto» / Mux falhou — ver snackbar no A |
| Buyer sem «Reservar» | Repetir sync; confirmar `MAESTRO_LIVE_ID` em `.maestro/.env` |
| Porta driver em uso | Mudar `MAESTRO_DRIVER_PORT_*` no `.env` |

Cenários 2–4 (aceitar, vendido, chat privado) — flows futuros no mesmo padrão.

## CI (opcional)

Job manual `workflow_dispatch` em `.github/workflows/maestro-smoke.yml` — não bloqueia `main` no início.
