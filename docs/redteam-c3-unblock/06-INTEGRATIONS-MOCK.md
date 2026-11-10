# B6 — Integrações: real vs simulado

| Integração | Em TEST | Risco se mal configurado |
|------------|---------|---------------------------|
| Stripe | **TEST keys** + Connect teste | LIVE keys → dinheiro real |
| DPD | OAuth probe OK; **create OFF** | Create comercial → etiquetas reais |
| BulkGate | `OPS_SMS_SEND_ENABLED=0` | SMS pagos |
| Email (Resend) | Preferir sink / domínio teste | Spam a reais |
| Moloni | Modo mock / company TEST | Docs fiscais reais |
| Mux / LiveKit | Contas TEST; encerrar lives | Custo streaming |
| Meta | Webhooks lab | Posts reais |

## E2E possível vs só simulado

| Fluxo | E2E TEST | Notas |
|-------|----------|-------|
| Registo / login / RLS | Sim (com Auth TEST) | |
| Reservas / stock / chat | Sim (seed) | |
| Checkout Stripe TEST | Sim | |
| SMS OTP | Simulado até GO SMS controlado | |
| Etiqueta DPD comercial | **Não** (create OFF) | |
| Stripe LIVE / tips LIVE | **Não** | |
| Directo Mux | Limitado; custo | Encerrar sempre |
