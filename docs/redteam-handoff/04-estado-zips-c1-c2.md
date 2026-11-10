# 04 — Estado dos ZIPs (C1 / C2)

Resumo orientado a decisão. Detalhe operacional em `00-fleahub-zips/README.md` (quando disponível na cópia).

## C1 — concluído / recente

| ZIP | Tema | Estado útil ao C3 |
|-----|------|-------------------|
| 190 | DPD OAuth PROD + BulkGate prep | DPD auth PROD **PASS**; create OFF; BulkGate secrets/hook **FAIL**; SMS **STOP** |
| 189 | Pré-Red Team | Hub férias alinhado; docs matriz; Stripe MONEY_GO=0 |
| 188 / 188.1 | App Links, gravados, carteira, Connect | APK **1881** PROD; SMS ainda off |
| 187 | Auth rate limit / anti-abuso signup | Capacidade Amen |
| 186–185 | SMTP Amen, registo público | Email Auth OK com avisos DKIM |
| 184 | 2 expedições DPD **QA** ao Rui | Create QA histórico; PROD create nunca nestes ZIPs |
| 182–174 | Stripe Connect onboarding / LIVE prep | TEST OK; LIVE dinheiro STOP |
| 172–171 | Dual env Stripe/DPD | Sticky mode por encomenda |
| 160–159.x | DPD portes, PUDO, etiquetas QA | Base integração DPD |

## C2 — em curso / não tocar

| Tema | Nota |
|------|------|
| Importador Amazon | Lotes, aprovação, worker autónomo |
| Overlay / montra directos | UI live C2 |
| Moloni | Multi-empresa / simulação |
| Scanner / câmara EAN-LPN | ZIPs 163–164.x |

O C3 **não** deve corrigir código C2 nem «melhorar» o importador durante a auditoria inicial.

## Problemas conhecidos (abertos)

1. **BulkGate PROD:** faltam Application ID/token + `SEND_SMS_HOOK_SECRET`; Phone provider e Send SMS hook desligados; `OPS_SMS_SEND_ENABLED=0`.
2. **DPD create PROD:** intencionalmente off até GO humano.
3. **DKIM email:** historicamente ausente / incompleto (SPF/DMARC OK em rondas anteriores).
4. **App Links Gmail clique real:** validação ADB ≠ prova de clique Gmail (ZIP 188).
5. **Git `origin/master`:** pode estar **atrás** dos artefactos deployados (APK 1881, Hub stamp 189, Edges ZIP 190). Ver `05-versoes-deploys.md`.
6. **Teste legado** `dpd_qa_create_zip_test` carrier 3,50 vs tarifas live — aviso conhecido, não regressão ZIP 190.

## Trabalho C1 ainda pendente (não bloqueia leitura C3)

- Activação SMS real (GO + secrets humanos)
- Primeira expedição DPD PROD (GO)
- Bateria funcional completa pré-lançamento
- Red Team ofensivo = **missão C3**, não C1
