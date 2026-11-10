# Relatório 191 — BulkGate GO + C3 unblock prep

## Quadro de bloqueios

| Bloqueio | Estado | Prova |
|----------|--------|-------|
| BulkGate token/hook/Phone Auth | **RESOLVIDO** (send ainda OFF) | Auth config + secrets names + CredMan |
| SMS Cláudia …5912 | **PENDENTE GO SMS** | Auth 503 + Edge `OPS_SMS_SEND_ENABLED!=1` |
| APK 1881 update | **RESOLVIDO** (não necessário) | Falha só kill-switch servidor |
| `flutter_webrtc` | **RESOLVIDO** | `tool/c3_bootstrap_flutter_webrtc.ps1` + flutter test |
| Testes portes 3,50 | **RESOLVIDO** | BEFORE fail / AFTER pass; regra Célia |
| Supabase TEST isolado | **BLOQUEADO** | Docker engine não ready; staging não limpo comprovado |
| Contas/dados TEST | **PENDENTE** | templates seed; não aplicados |
| Integrações mock matriz | **RESOLVIDO** | `06-INTEGRATIONS-MOCK.md` |
| Guia C3 | **RESOLVIDO** | `09-C3-START-GUIDE.md` |
| F-001 residual `price_total` | **RESOLVIDO** (doc) | `08-F001.md` — sem deploy LIVE |
| C3 auditoria funcional completa | **BLOQUEADO** | depende B3 |

## Flutter

- Pack smoke: **33 PASS**
- Fee BEFORE: 4 FAIL (legado 3,50)
- Fee AFTER: PASS

## GO pedidos ao dono

1. `GO SMS …5912`
2. `GO TEST LOCAL` **ou** `GO TEST CLOUD` **ou** `GO TEST STAGING CLEAN`
