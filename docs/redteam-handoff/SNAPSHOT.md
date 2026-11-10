# Snapshot C3 — código completo (ZIP 190.1)

**Branch:** `c1/190-c3-full-snapshot`  
**Propósito:** substituir o handoff docs-only (`c1/190-redteam-handoff` @ `ff34a44`, baseado em `master` antigo) por um **tree completo** alinhado ao working tree C1 usado para APK 1881 / Hub 189 / Edges actuais.

## Inventário deste snapshot

| Camada | Contagem / stamp |
|--------|------------------|
| Dart em `lib/` | **438** ficheiros |
| Edge Functions (slugs) | **40** |
| Migrations SQL | **221** |
| FleaHub artefacto | `deploy/fleaber_pt/fleahub/` stamp **`189-pre-redteam-20261109-2000`** |
| App version | `pubspec` / `local.properties` → **1.0.0+1881** |

## O que corresponde a quê

| Artefacto | Origem neste snapshot | Produção comprovada? |
|-----------|----------------------|----------------------|
| Android código `lib/` + `android/` | Working tree C1 no momento do snapshot (mesma base do APK **1881**) | Código **provável** fonte do APK 1881; **binário APK não incluído** — não há prova criptográfica APK↔tree neste commit |
| FleaHub `deploy/fleaber_pt/fleahub/` | Cópia do artefacto FTP local com stamp 189 | Stamp igual ao publicado 2026-11-09; cache CDN/SW do browser **não** revalidado aqui |
| Edge Functions `supabase/functions/` | Working tree actual (inclui fix F-001 piloto LIVE) | **Nem todas** as Edges PROD foram redeployadas neste instante — ver nota deploy |
| SQL / RLS `supabase/migrations/` + `docs/SCHEMA_SOURCE_OF_TRUTH.md` | Repo local | Schema PROD histórico; **não** dump live completo |
| Docs `docs/redteam-handoff/` | Handoff + este SNAPSHOT | Documentação |

## Produção vs desenvolvimento vs não comprovado

### Produção (operacional)

- Projecto Supabase **`bpmpkzwnrbmuqnhgdscf`**
- Hub em `fleaber.pt/fleahub/` (stamp 189)
- APK **1881** em devices de teste
- Flags dinheiro/DPD create/SMS send: **off** (até GO)

### Desenvolvimento / WIP neste tree

- Working tree C1 misturava histórico com branch de trabalho C2 no disco; este snapshot **copia o código** sem a branch Git C2.
- Importador Amazon / Moloni / overlay (área C2) **incluídos para auditoria** — C3 não deve «corrigir C2» sem GO.
- Correção F-001 (gate piloto LIVE) está no ficheiro local; **deploy Edge PROD pendente de GO**.

### Não comprovado

- Equivalência byte-a-byte APK 1881 ↔ este commit  
- Que **todas** as 40 Edges no disco = versão exacta a correr em PROD  
- RLS live vs migrations (drift possível)  
- BulkGate `APPLICATION_TOKEN` PROD (ainda pendente ficheiro local)

## F-001 (create-payment-intent)

Ver `tool/reports/190-dpd-bulkgate/06-F001-create-payment-intent.md` (se presente) ou resumo:

- Cobro Stripe: total **servidor** (`resolveServerCheckoutQuote`) — **não** é F-001 clássico.
- Gate piloto LIVE: deixou de usar `body.amount` (fix no tree).

## Branch antiga de handoff

`c1/190-redteam-handoff` permanece como **docs iniciais**; para auditoria de código usar **esta** branch.

## Segredos

Sem `.env`, tokens, APKs, ZIPs de evidência pesados, ou dumps PII. Scrub aplicado no packaging.
