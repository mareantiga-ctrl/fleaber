# B1 — `third_party/flutter_webrtc`

## Problema

`pubspec.yaml` usa:

```yaml
flutter_webrtc:
  path: third_party/flutter_webrtc
```

Esse directório **não** vem no clone GitHub → `flutter test` / `pub get` falhavam no C3.

## Solução (reproduzível)

```powershell
powershell -NoProfile -File tool/c3_bootstrap_flutter_webrtc.ps1
flutter pub get
flutter test test/fee_calculator_test.dart test/live_checkout_fees_test.dart
```

O script clona a tag **1.4.0** de `flutter-webrtc/flutter-webrtc` para `third_party/flutter_webrtc` (sem `.git` aninhado).

Não altera código funcional da app.

## Prova local C1

- Bootstrap: `OK: flutter_webrtc already present` (ou `BOOTSTRAP_OK`).
- Pack smoke: **33 testes PASS** (`fee_calculator`, `live_checkout_fees`, `hub_reservation_summary`, `hub_gravados_live_routing`).
