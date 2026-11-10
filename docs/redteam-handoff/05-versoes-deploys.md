# 05 — Versões Git e deploys

## Git

| Item | Valor (no momento do handoff) |
|------|-------------------------------|
| Remoto | `https://github.com/mareantiga-ctrl/fleaber.git` (privado) |
| Branch handoff | `c1/190-redteam-handoff` |
| Base | `origin/master` @ `3489865` («Stabilize Maestro prep chain…») |
| Nota | A máquina C1 tem WIP local noutras branches (incl. C2). **Não** uses WIP C2 como base de auditoria sem instrução. |

O SHA exacto do commit que contém estes docs será o do push — o relatório C1 no chat confirma-o.

## Android

| Item | Estado |
|------|--------|
| `pubspec` / versionCode local C1 | **1.0.0+1881** |
| APK instalado Redmi (ronda 188) | **1881 PROD** com dart-defines produção |
| Comprovado | Build flags PROD; smoke App Links parcial |
| Não comprovado neste handoff | Reinstalação limpa em todos os devices; clique Gmail real |

## Hub web

| Item | Estado |
|------|--------|
| Stamp conhecido | `189-pre-redteam-20261109-2000` |
| Path | `fleaber.pt/fleahub/` |
| Comprovado | Fix férias Diretos no JS publicado |
| Não comprovado | Cache SW de todos os browsers utilizador |

## Supabase

| Project | Ref | Comprovado |
|---------|-----|------------|
| Produção | `bpmpkzwnrbmuqnhgdscf` | Edges DPD probe OAuth PROD PASS (190); SMS flags off |
| Staging | `fxdknzrqjenzqcvnwqqq` | Secrets BulkGate presentes (valores não exportáveis) |

## Flags operacionais (nomes — valores esperados seguros)

| Flag | Esperado até GO |
|------|-----------------|
| `OPS_DPD_COMMERCIAL_GO` | off (`0`) |
| `DPD_LIVE_CREATE_ENABLED` | off |
| `DPD_QA_CREATE_ENABLED` | off (salvo testes QA autorizados) |
| `OPS_SMS_SEND_ENABLED` | off |
| `OPS_STRIPE_LIVE_PILOT_MONEY_GO` | off |
| `OPS_STRIPE_LIVE_GO` | off |

## O que está comprovado vs não

| Afirmação | Comprovado? |
|-----------|-------------|
| OAuth DPD PROD via proxy | **Sim** (2026-11-10) |
| Create expedição PROD | **Não** (STOP) |
| SMS OTP end-to-end PROD | **Não** |
| RLS completo sem IDOR | **Não** — missão C3 |
| Stripe TEST Connect isolamento | Parcial (ZIPs 182/188) — C3 revalidar |
| Código Git = 100% igual ao APK 1881 | **Não garantido** — tratar deploys e Git como evidências separadas |
