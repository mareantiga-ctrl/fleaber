# Fleaber Bot Simulator

Ferramenta **externa** em `tool/` para simular viewers, chat, reservas, rifas e follows numa live de **staging**. Não altera a app nem os RPCs de produção.

## Requisitos

- `tool/live_ops_staging.env` (copiar de `tool/live_ops_staging_env.example` + `tool/bot_sim_staging_env.example`)
- Live activa em staging com artigos
- Conta vendedor de teste (`LIVE_OPS_TEST_SELLER_*`)

## Segurança

- Bloqueado se `BOT_SIM_ALLOWED_PROJECT_REFS` não incluir o ref do projecto
- Bots identificados como `DEMO_BOT_01` … (ou prefixo `--prefix`)
- Tag de corrida em reservas: `STRESS_TEST:<run_id>`
- **Nunca** correr em produção

## Uso

```bash
dart run tool/fleaber_bot_simulator.dart \
  --live-id <uuid-da-live> \
  --bots 50 \
  --active-chatters 5 \
  --duration 10m \
  --scenario full \
  --demo-mode \
  --cleanup
```

### Cenários (`--scenario`)

| Valor | Descrição |
|-------|-----------|
| `viewers` | Ping `batata_live_viewer_ping`, saída gradual |
| `chat` | Mensagens naturais em `live_messages` |
| `reservations` | Reservas + teste duplicado + stock |
| `price_pending` | Reserva → seller define preço → validação |
| `raffles` | Join, duplicado, close + draw |
| `follows` | Follow seller + check lifetime grants |
| `full` | Todos os acima |

### Opções

- `--demo-mode` — nomes simpáticos, ritmo mais lento
- `--cleanup` — apaga dados da run (reservas tag, mensagens bot, viewers, rifa teste)
- `--keep` — não fazer cleanup mesmo com `--cleanup`
- `--observe-ui` — abre Chrome (Windows) com URL da live
- `--i-know-this-is-staging` — ignora guard de project ref

## Relatórios

Pasta `tool/reports/bot_sim_<timestamp>/`:

- `summary.md`
- `events.jsonl` — cada acção com timestamp, bot, resultado, duration_ms
- `errors.jsonl`
- `inconsistencies.md`
- `db_snapshot_before.json` / `db_snapshot_after.json`

## Bots

Auto-provision via Admin API (`demo_bot_01@staging.fleaber.bot`, …). Cache em `tool/.bot_pool_cache.json` (gitignored).

## Limitações

- Checkout Stripe **não** é simulado (price_pending valida preço via RPC stock)
- Playwright opcional: `node tool/bot_sim/playwright_observe.mjs --url <url>`
- `--observe-ui` abre Chrome no Windows para inspecção rápida
- Lifetime grants só validados se existirem na BD

## Exit code

`0` = sem erros de validação nem eventos FAIL; `1` = falhas.
