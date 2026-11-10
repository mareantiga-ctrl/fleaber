# 07 — Matriz inicial de cobertura (C3 completa)

Modelo para o C3 transformar num **exame numerado** (ex.: RT-001, RT-002…) em português simples.

Colunas sugeridas no exame final:

`ID | Área | O que testar | Como (passos) | Esperado | Risco se falhar | Ambiente | Pré-requisitos | Critério PASS | Estado`

## Matriz semente

| ID rascunho | Área | Funcionalidade | Esperado | Riscos | Pré-requisitos | Critério aprovação | Bloqueio |
|-------------|------|----------------|----------|--------|----------------|--------------------|----------|
| RT-A01 | Auth | Login / logout | Sessão válida; logout limpa | Session fixation | Conta teste | Fluxo OK | — |
| RT-A02 | Auth | Recuperação password | Link abre app ou web correcta | Open redirect | Email teste | Deep link seguro | App Links |
| RT-A03 | Auth | OTP telemóvel | Só com código legítimo | Brute force / custo SMS | BulkGate GO | Rate limit + verify | Secrets PROD |
| RT-R01 | RLS | Ler encomenda alheia | Negado | IDOR financeiro | 2 contas | 401/empty | — |
| RT-R02 | RLS | Ler chat alheio | Negado | PII leak | 2 contas | Sem mensagens | — |
| RT-R03 | RLS | Wallet alheia | Negado | Roubo saldo | 2 vendedores | Sem saldo | — |
| RT-R04 | RLS | Live / VOD privado | Negado a estranhos | Conteúdo privado | Conta dono | 404/empty | — |
| RT-R05 | Storage | URL foto / etiqueta | Só parties autorizadas | Path traversal | Seller/buyer | Sem dump | — |
| RT-C01 | Checkout | Tamper preço no cliente | Servidor rejeita / corrige | Pagamento a menos | Stripe TEST | Amount server-side | — |
| RT-C02 | Checkout | Portes inventados | Rejeitado | Fraude portes | Stripe TEST | Fail-closed | — |
| RT-C03 | Checkout | Protecção omitida | Regra negócio clara | Bypass fee | Stripe TEST | Documentar | — |
| RT-S01 | Stock | Oversell paralelo | ≤ stock | Race | 2 buyers | Sem oversell | — |
| RT-S02 | Reservas | Reservar sem stock | Negado | Oversell live | Live teste | Erro claro | Encerrar live |
| RT-P01 | Stripe | Connect cross-account | Isolado | Wallet hijack | TEST | Sem dados alheios | MONEY_GO=0 |
| RT-P02 | Stripe | Forçar LIVE com flags off | Bloqueado | Dinheiro real | Flags off | Erro GO | — |
| RT-D01 | DPD | Create com GO=0 | Bloqueado | Etiqueta real | Edge | `create_enabled=false` | — |
| RT-D02 | DPD | PUDO só com auth | Sem dump público | Enumeração | JWT user | Auth required | — |
| RT-M01 | Admin | Endpoint staff sem role | Negado | PrivEsc | User normal | 403 | — |
| RT-H01 | Hub | Perfil férias | Sem montra/gravados a visitantes | Leak conteúdo | Conta férias | Mensagem férias | — |
| RT-N01 | Notify | Webhook Stripe assinatura | Rejeita sem sig | Forjar pago | Endpoint | 400 | — |
| RT-N02 | SMS hook | Sem signature | Rejeita | SMS abuse | Função | 401 | Hook off |

## Instruções ao C3

1. Renumerar de forma estável (`RT-001`…).  
2. Acrescentar passos «vai / toca / espera» em português simples.  
3. Marcar cada ID: PENDENTE → EM CURSO → PASS/FAIL.  
4. Não marcar PASS sem prova.  
5. Separar **TEST** de **PROD read-only**.
