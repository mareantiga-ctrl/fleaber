# Guia de arranque C3

## 1. Ambiente

```text
git clone https://github.com/mareantiga-ctrl/fleaber
git checkout c1/191-c3-unblock
powershell -File tool/c3_bootstrap_flutter_webrtc.ps1
flutter pub get
```

Flutter estável ≥ 3.41 (a usada na prova C1).

## 2. Testes locais (já desbloqueados)

```powershell
flutter test test/fee_calculator_test.dart test/live_checkout_fees_test.dart `
  test/hub_reservation_summary_test.dart test/hub_gravados_live_routing_test.dart
```

Esperado: PASS (prova C1: 33 testes).

## 3. TEST Supabase (local)

**Bloqueado nesta máquina até Docker Engine** — ver `11-DOCKER-BLOCKER.md`.

Pré-requisito Admin (uma vez):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/c3_fix_docker_admin.ps1
```

Depois (C1 / C3):

```powershell
npx supabase start
npx supabase db reset   # aplica migrations locais
# seed: tool/c3_test_seed/ (após GO concluído pelo C1)
```

1. Apontar dart-defines / `.env` local (fora do git) para URL local (`http://127.0.0.1:54321`).
2. Login Buyer A / Seller A (credenciais locais).
3. Cleanup só com `90_cleanup_c3_test.sql`.

## 4. Limites de segurança

- Sem PROD writes.
- Sem SMS / DPD create / Stripe LIVE sem GO.
- Sem `service_role` no relatório C3.
- Encerrar lives após testes.
- Não modificar a branch de produto; PoCs em branch C3 própria.

## 5. Disponível vs bloqueado

| Disponível já | Bloqueado até GO |
|---------------|------------------|
| Leitura código snapshot | TEST funcional cloud/local |
| `flutter test` unitários | SMS real |
| Matriz portes Célia | DPD create / Stripe LIVE |
| Docs F-001 residual | Contas seed aplicadas |

## 6. Evidências desta preparação

Ver `tool/reports/191-c3-unblock/` e `00-STATUS.md`.
