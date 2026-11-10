# B3 — Ambiente TEST (isolamento)

## Projectos Supabase conhecidos

| Ref | Nome | Uso |
|-----|------|-----|
| `bpmpkzwnrbmuqnhgdscf` | Fleaber Prod | **PROD — proibido como TEST** |
| `fxdknzrqjenzqcvnwqqq` | Fleaber (staging) | QA histórico; **não comprovado limpo de PII** |
| Outros (Biscateiro / biscates) | — | **fora** do produto Fleaber |

## Porquê B3 = BLOQUEADO agora

1. **PROD** não pode ser usado como TEST.
2. **Staging** não foi auditado como livre de dados pessoais reais nesta ronda; pode ter resíduos de QA e secrets históricos.
3. **Supabase local** (`supabase start`) seria o TEST ideal (sem PII, sem custos externos), mas o **Docker Engine não ficou ready** nesta máquina (Docker Desktop arrancou; API engine falhou após ~90s).
4. Criar um projecto cloud «Fleaber Red Team TEST» implica **recurso pago / billing** → precisa de autorização explícita.

## Pedido de autorização (escolhe um)

### Opção L — Local (preferida, zero cloud)

`GO TEST LOCAL` — C1 volta a subir Docker Engine + `supabase start` no worktree C3, aplica migrations/seeds TEST, documenta URLs locais (sem secrets no git).

### Opção C — Cloud dedicado

`GO TEST CLOUD` — C1 cria projecto novo «Fleaber Red Team TEST», aplica schema mínimo + seeds, kill-switches OFF para SMS/DPD/Stripe LIVE, entrega refs + contas (passwords só fora do git).

### Opção S — Staging limpo (só com auditoria)

`GO TEST STAGING CLEAN` — C1 audita `fxdknzr…` (contagens PII), propõe purge só de dados TEST, ou aborta se houver risco.

## Kill-switches obrigatórios em qualquer TEST

- `OPS_SMS_SEND_ENABLED=0`
- `OPS_DPD_COMMERCIAL_GO=0` / `DPD_LIVE_CREATE_ENABLED=0`
- `OPS_STRIPE_LIVE_GO=0` / `OPS_STRIPE_LIVE_PILOT_MONEY_GO=0`
- Stripe: chaves **TEST** apenas
- BulkGate: mock ou send disabled
- Mux/LiveKit: contas TEST / lives encerradas após uso
