# Fleaber — Backlog produto & crescimento (pós-PMF operacional)

> Documento vivo. Ideias validadas estrategicamente para **adicionar quando o loop live → pagamento → envio estiver provado** (Stripe + transportadoras + APIs Face/PS mínimo).
> **Não** substituir prioridade actual: integrações + lives reais + GMV.

**Origem:** análise estratégica 2026-07-12 · pedido João (founder).

---

## Quando activar este backlog

Activar item quando **todas** forem verdade:

- [ ] Stripe checkout live/marketplace PASS em produção/staging real
- [ ] Pelo menos 1 transportadora (ex. InPost) end-to-end PASS
- [ ] ≥1 live completa: reserva ou compra → pagamento → envio (ou MB WAY) → comprador satisfeito
- [ ] João + Cláudia a operar lives sem bloqueio técnico crítico

---

## P0 — Alto impacto / baixo atrito (fazer primeiro desta lista)

| ID | Ideia | Porquê | Notas |
|----|--------|--------|-------|
| G-01 | **Dashboard seller:** GMV, conversão live, repeat buyers, stock parado | Sellers precisam ver valor para trazer clientes | Pode começar read-only RPC |
| G-02 | **Link checkout 1-click pós-reserva** (WhatsApp/FB DM) | Reduz drop-off fora da live | Deep link + short URL |
| G-03 | **Push notifications:** vez na fila, pagamento pendente, enviado | Live = urgência | Firebase já comum em Flutter |
| G-04 | **Onboarding seller ~15 min:** handle + 1º produto + 1ª live | Escala convites pós-prova João | Hub publish + checklist |
| G-05 | **Prova social Hub:** «X vendidos nesta live», «Y na fila» (agregado) | FOMO; já parcialmente desenhado em RPC FOMO | Sem PII |

---

## P1 — Crescimento viral / aquisição

| ID | Ideia | Porquê | Notas |
|----|--------|--------|-------|
| G-06 | **Programa «traz N compradores → desbloqueia rifa»** | Alinha com estratégia €50/rifa + sellers trazem audiência | Regras por etapas (views, check-ins Hub/app) |
| G-07 | **Rifas escalonadas por seller** (€30 / €10 / €10 live 1–3) | Orçamento ~€1000 / ~20 sellers | Parametrizar em admin ou config |
| G-08 | **Referral buyer:** convida amiga → entrada extra rifa | Custo baixo vs ads | Depende motor rifas estável |
| G-09 | **Banner pós-auth Hub:** «Tens N reservas neste directo» | Project H / PS — compradora FB não perdida | `hub_actions` + intent |

---

## P2 — Project H / PS (após motor OCR/LLM estável)

| ID | Ideia | Porquê | Notas |
|----|--------|--------|-------|
| G-10 | **PS MVP comentário FB → fila** (auto + fila ambiguidades) | Motor da wedge; **não atalhar** — documentado | Human-in-the-loop só ambiguidade |
| G-11 | **Reconciliação reserva FB → buyer_id** pós-login | Mesma pessoa, mesma fila | `facebook_manual` + identity |
| G-12 | **Modo demo PS** (staging) → produção gradual | Já existe demo flag Hub | |

---

## P3 — Retenção & marketplace pós-live

| ID | Ideia | Porquê | Notas |
|----|--------|--------|-------|
| G-13 | **Notificação «ainda disponível»** stock marketplace pós-live | Flywheel live → catálogo | Push + email |
| G-14 | **«Seguir seller» pós-compra** one-tap | Repeat sem ads | Hub + app |
| G-15 | **Histórico unificado** reservas Hub + app + FB (mesma conta) | Confiança compradora | Depende login FB |

---

## Explicitamente FORA deste backlog (congelado)

- White Label (até procura real)
- B2B liquidações / fabricantes / feiras oficiais
- Trust Score 0–1000 automatizado (regras + suporte humano bastam no início)
- Internacionalização FR/ES **antes** PT estável — ver nota founder abaixo

### Nota founder (i18n)

João pretende FR/ES cedo após prova PT + sellers reais. Quando activar: criar issue `I18N-01` — strings Hub/app + pagamentos + emails; **não** bloquear launch PT.

---

## KPI scorecard (GMV semanal — usar quando Stripe live)

| KPI | Meta inicial (sugerida) | Fonte |
|-----|-------------------------|-------|
| GMV semanal (€) | Definir após 1ª live paga | Stripe + orders |
| Compradores únicos / semana | | auth.users + orders |
| Repeat 30d (%) | ≥20% antes de escalar sellers | |
| Sellers activas / semana | João → +convidados | |
| Conversão live → pagamento (%) | | funil eventos |
| Custo incentivo rifa / GMV (%) | <15% na fase tração | planilha manual |

---

## Lembrete para agente / João

Quando **Stripe + InPost + 1ª live paga** estiver PASS, reler este ficheiro e priorizar **G-01, G-02, G-03** antes de features Hub cosméticas.
