# Handoff técnico — Red Team (C3)

**Destinatário:** auditor Red Team independente (conta Cursor separada).  
**Autor:** C1 (ZIP 190 + preparação handoff).  
**Data:** 2026-11-10  
**Idioma:** português de Portugal (PT-PT).

## Como começar (obrigatório)

1. Clonar este repositório **privado** noutra conta / máquina.
2. Fazer checkout desta branch de handoff (ver relatório C1 para SHA exacto).
3. Ler **só** esta pasta em modo leitura na primeira sessão.
4. **Não** modificar o projecto, **não** fazer push, **não** executar operações reais (pagamentos, SMS pagos, expedições DPD PROD, Stripe LIVE, lives comerciais) até receber GO explícito do dono do produto.
5. Ambiente de trabalho preferido para testes: **TEST / staging** — ver `06-testes-seguros-test.md`.

## Índice

| Ficheiro | Conteúdo |
|----------|----------|
| [01-arquitetura.md](01-arquitetura.md) | Android, FleaHub, Supabase, vídeo, integrações |
| [02-inventario-superficies.md](02-inventario-superficies.md) | Ecrãs, fluxos, tabelas, RLS, APIs, Edge Functions |
| [03-regras-negocio.md](03-regras-negocio.md) | Preços, descontos, reservas, protecção, portes, pagamentos, devoluções |
| [04-estado-zips-c1-c2.md](04-estado-zips-c1-c2.md) | ZIPs, concluído, problemas, trabalho em curso |
| [05-versoes-deploys.md](05-versoes-deploys.md) | Git, APK, Hub, Supabase — comprovado vs não |
| [06-testes-seguros-test.md](06-testes-seguros-test.md) | Limites TEST; o que nunca fazer em PROD |
| [07-matriz-cobertura-inicial.md](07-matriz-cobertura-inicial.md) | Matriz para o C3 numerar e expandir |
| [08-regras-entrega-c3.md](08-regras-entrega-c3.md) | ZIP final, provas, testes reproduzíveis |
| [09-integracoes-estado.md](09-integracoes-estado.md) | DPD / BulkGate / Stripe / email — estado ZIP 190 |
| [STOP-GO.md](STOP-GO.md) | Lista curta GO vs STOP |

## Segredos

Este pacote **não** contém passwords, tokens, chaves API, OTP, dados pessoais nem credenciais de produção.  
Se encontrares um ficheiro local com secrets (`.env`, CredMan, Downloads), **não** o copies para o ZIP C3 nem para o chat.

## Papéis

| Agente | Âmbito |
|--------|--------|
| **C1** | Marketplace, checkout, DPD, Stripe Connect, Auth/SMS, Hub UX crítico, pré-Red Team |
| **C2** | Importador Amazon, worker autónomo, overlay/montra de diretos, Moloni — **não alterar** |
| **C3** | Auditoria Red Team independente; começa em cópia read-only |

## Contacto de contexto

Relatórios operacionais recentes (máquina C1, podem não estar todos no Git):  
`tool/reports/189-pre-redteam/`, `tool/reports/190-dpd-bulkgate/`, pasta `00-fleahub-zips/`.
