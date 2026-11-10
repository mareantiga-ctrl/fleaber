# 09 — Estado das integrações (ZIP 190)

## DPD

| Item | Estado |
|------|--------|
| OAuth QA | PASS |
| OAuth PROD (`business.dpd.pt`) | **PASS** (2026-11-10) |
| Causa antiga `host_not_allowed` | Allowlist VPS — **corrigida** |
| Egress IP | `135.125.254.159` |
| Create / recolha / fecho / etiqueta PROD | **STOP** (flags off) |
| Expedições QA históricas | 2 guias enviadas ao Rui (ZIP 184) |

Probe sem token exposto: Edge `dpd-oauth-probe` (`expires_in_sec` ~14400, renovação por password-grant).

## BulkGate / SMS

| Item | Estado |
|------|--------|
| Função `send-sms-bulkgate` deploy PROD | Sim (ZIP 190) |
| Kill-switch `OPS_SMS_SEND_ENABLED` | **0** |
| Secrets ID/token/hook PROD | **Ausentes** |
| Phone provider PROD | **Desligado** |
| Send SMS hook PROD | **Desligado** |
| Parse +351 (mocks) | PASS |
| SMS real | **STOP** — falta autorização + secrets |

## Stripe

| Item | Estado |
|------|--------|
| TEST Connect / checkout | Usar para Red Team |
| LIVE / MONEY_GO | **Off** — não activar |
| Isolamento carteira | Revalidar no exame C3 |

## Email

| Item | Estado |
|------|--------|
| SMTP Amen Auth | Configurado (ZIPs 186–187) |
| Capacidade | Limite diário fornecedor — não spammear |
| DKIM | Verificar se ainda incompleto |

## Mensagem DPD (Rui) — rascunho

Disponível na máquina C1: `tool/reports/190-dpd-bulkgate/01-MENSAGEM-RUI-DPD.md`  
(OAuth PROD já funciona; mensagem opcional para confirmação formal do IP.)
