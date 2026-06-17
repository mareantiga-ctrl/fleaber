# Camada de auditoria Cursor (pós-Maestro)

## Pipeline

```
Maestro executa teste
    → screenshots + commands JSON + logs
    → snapshot BD (rpc batata_live_item_stock + tabelas live)
    → contexto (testId, stamp, live_id, layer)
    → AuditEngine (UI extract + stock alignment + visual heuristics + deep link detect)
    → PASS | PASS_COM_AVISO | PASS_COM_AVISO_DEEPLINK | FAIL
    → audit_results.json + audit_summary.md + audit_warnings.md + audit_failures.md
```

## CLI

```powershell
# Um teste
dart run tool/audit/audit_runner.dart --test-id T07c --stamp 20260616_142156 `
  --evidence-dir tool/logs/screenshots_20260616_142156/01_maestro_automation `
  --maestro-exit 0 --layer UX

# Batch por stamp
dart run tool/audit/audit_runner.dart --batch-stamp 20260616_142156

# Reclassificar registry (PASS UX → PASS_COM_AVISO_DEEPLINK se aplicável)
dart run tool/audit/audit_runner.dart --reclassify-registry
```

## Integração

- `tool/run_post_test_audit.ps1` — wrapper PowerShell
- `tool/audit_battery_hooks.ps1` — hooks para baterias
- `run_full_automated_battery.ps1` — auditoria após archive de screenshots
- `run_cross_surface_ux_battery.ps1` — auditoria após cada CS##

## Campos stock comparados

`total_qty`, `available_qty`, `reserved_qty`, `sold_qty`, `blocked_qty`, `cross_reserved_qty`, `sold_converted_qty`

Fontes: BD RPC vs textos extraídos da hierarquia Maestro (seller_ui / buyer_ui).

## Deep links

Flows com `openLink` ou adb URI são marcados `PASS_COM_AVISO_DEEPLINK` se o resto passar.
Subflows UX: `.maestro/subflows/nav_buyer_to_live_player.yaml`, `nav_seller_to_studio.yaml`.
