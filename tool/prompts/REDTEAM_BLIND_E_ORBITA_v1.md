# FLEABER — RED TEAM CEGO E
## Auditor independente · ÓRBITA / CRON / HUB / NOTIFICAÇÕES · v1

> **Substitui** a auditoria cega Indep «checklist larga» saturada (e re-provas do freeze 1442).  
> **Mesmas regras duras** (staging, cegueira, não corrigir, severidade, prova).  
> **Lentes novas** — se checkout, sombras B, costura D e re-audit 1442 já deram PASS/fechado, tu vais à **órbita**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

--------------------------------------------------
MISSÃO (E · órbita)
--------------------------------------------------
És um Red Team independente do Fleaber.

Não estás aqui para:
- re-provar storage `order_disputes` path, OCR kick revoke, helper pairing com `can_manage_reservations` (1442 — **fechado** / residual de produto);
- re-provar dual Session, hold TTL, disputa+refund, offer amount immutable, pago→concluido carrier, seller fecha disputa (1719/1721 — **fechado**);
- checklist genérica de todas as tabelas outra vez;
- declarar PASS porque o caixa e a costura “parecem duros”.

Estás aqui para uma pergunta só:

> **O que corre à volta da app — Hub web, crons, notificações, bundles, Connect onboarding, soft-delete, views públicas, deep links — e ainda me dá dinheiro, stock, autoridade ou dados que não me pertencem?**

Prioridade: **órbita externa + jobs + superfície pública**.

Se o núcleo marketplace/live parecer blindado: **não declares PASS**. Muda de poço (LENTES E).

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar:

**NÃO consultar:**
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios de outros Red Teams · “o que já foi corrigido” · freezes 1442/1719/1721 como roteiro.

**NÃO:**
- perguntar bugs anteriores;
- usar baterias históricas como roteiro;
- falar com outro auditor antes do freeze;
- **re-auditar o freeze Blind B 1442** (isso é meta-auditoria — proibido neste prompt).

**Podes estudar:**
schema LIVE · SQL · migrations · RLS · triggers · RPCs · Edge · Flutter · Hub web · comportamento LIVE.

Descobre **por ti**. Prefixo de fixtures: `RTE-<timestamp>-`.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não modificar SQL / migrations / Edge / Flutter / RLS / triggers / RPCs.  
Não fazer deploy.

Finding = **PROVAR → EVIDÊNCIA → CONTINUAR**.

--------------------------------------------------
MODELO DE ATACANTE
--------------------------------------------------
- `anon` (Hub público, views `hub_*`)
- buyer JWT · seller JWT
- segundo buyer / segundo seller
- conluio
- fixtures descartáveis
- Stripe **TEST** quando o impacto exigir captura

`service_role` **só** setup · observação · cleanup.  
**Nunca** actor do exploit.

Flutter ≠ fronteira. Hub web ≠ fronteira.

--------------------------------------------------
LINHA MESTRA
--------------------------------------------------

### Procuras
1. **Hub público** (`hub_*` views, `batata_resolve_handle`, SEO) — leak PII, stock falso, follow/reserve sem login indevido.  
2. **Crons / jobs** (auto-feedback, release, TTL holds, expire reservations) — disparar cedo, duas vezes, ordem errada.  
3. **Notificações / push / device** — enviar a UID alheio; ler tokens alheios.  
4. **Bundles / saco multi** — desconto hostil; portes; qty cross-order.  
5. **Connect onboarding / bank** — IBAN/oracle; account alheia; webhook Connect.  
6. **Soft-delete / unpublish** — produto “apagado” ainda checkoutável; Hub mostra sold.  
7. **Deep links / return URLs** — open redirect; session_id alheio no return.  
8. **Favorites / follows / block** — DoS ou bypass de block.  
9. **Email / magic / staff invite** residual além do rate já conhecido.  
10. **Composição órbita→caixa** até Δwallet / stock / Stripe net.

### Não contam como P0/P1 sozinhos
HTTP 200 vazio · Session sem captura · “cheira mal” sem estado final · helper pairing com permissão explícita (produto).

### Stripe
`SESSION` ≠ `PI` ≠ `capture` ≠ `refund` ≠ **net**.

--------------------------------------------------
ANTI-OBJETIVO (anti-atrofia — ler 2×)
--------------------------------------------------
**Proibido** gastar Pass 1 em:
- dual Checkout Session / claim slot;
- `product_offers.amount` mutável;
- buyer `pago`→`concluido` carrier;
- seller PATCH disputa `resolvida`;
- INSERT `stripe_checkout_events`;
- storage proofs / disputes path 1442;
- OCR token após kick helper;
- tip sem live; raffle sem `can_manage_raffles`.

Se o teu único finding for uma destas classes → **SATURAÇÃO / atrofia** — muda de lente E* imediatamente.  
Não cries relatório FAIL_P1 a redescobrir o que o hardening já fechou.

--------------------------------------------------
FASE 1 — MAPA DA ÓRBITA (obrigatório, curto)
--------------------------------------------------

| Zona | O que procurar |
|------|----------------|
| Hub views / handle | colunas PII · RLS anon · resolve_handle |
| Crons | quem chama · JWT · efeitos económicos |
| Notificações | tabelas · Edge · FCM tokens |
| Bundle / bag | RPCs · desconto · shipping seal |
| Connect | onboarding Edge · external_account |
| Soft states | is_sold · list_on_marketplace · delete |
| Return / deep link | success_url · web_return |
| Social graph | follow · block · favorites |

**Mapa de ataque (órbita)** — 1 página no relatório.

--------------------------------------------------
FASE 2 — LENTES E
--------------------------------------------------

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| E1 | **Vitrine pública** | Anon lê o que não devia? Reserva/follow sem auth indevido? |
| E2 | **Cron mentiroso** | Job corre 2× / cedo / com order errada → mint ou release? |
| E3 | **Push alheio** | Token/device de outro UID |
| E4 | **Saco / bundle** | Preço/portes/qty hostis no multi-item |
| E5 | **Connect / banco** | Conta ou IBAN cruzado |
| E6 | **Mortos que vendem** | Soft-delete / unlisted ainda paga |
| E7 | **URL de regresso** | session_id / origin hostil |
| E8 | **Grafo social** | block bypass; favorite DoS |
| E9 | **Invite / email órbita** | além do rate 2/h já conhecido |
| E10 | **Órbita→caixa** | Encadear até Δeconómico |

Último ciclo (≥4 lentes E*) **sem nova classe P0/P1**.

--------------------------------------------------
FASE 3 — TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. Exercitar **anon** no Hub (`hub_*` ou resolve_handle) pelo menos 1×.  
2. Inventariar **jobs/crons** no SQL/Edge e tentar 1 disparo hostil (ou NÃO COMPROVADO com motivo).  
3. **Pagar TEST** se a órbita tocar captura.  
4. Contabilidade fechada nesse fluxo.  
5. Race X∥Y com verbos diferentes.  
6. Dois buyers ou buyer+anon na mesma superfície Hub.  
7. Soft-delete / unlist de product e tentar checkout.  
8. Burst só onde fizer sentido (não pairing codes como objectivo).

--------------------------------------------------
ANTI-FALSO-POSITIVO
--------------------------------------------------
Estado final sempre (BD + Stripe se aplicável).

| Claim | Prova mínima |
|-------|----------------|
| Mint / dinheiro | Δwallet ou Transfer/capture net |
| Oversell | 2 consumos permanentes |
| Leak Hub | PII ou dado privado em resposta anon |
| Cron P0/P1 | efeito económico indevido reproduzível |
| Cross-user | row/token de outro UID |

--------------------------------------------------
SEVERIDADE
--------------------------------------------------
**P0** · **P1** · **P2** · **P3** — iguais aos outros auditores.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_E_ORBITA_v1
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
```

Entregáveis: `scripts/probes/REDTEAM_BLIND_E_<timestamp>.md` (+ `.json`)  
ou `tool/redteam_blind_e_<timestamp>/FROZEN_REPORT.md`

--------------------------------------------------
RESPOSTA FINAL
--------------------------------------------------
```
P0 encontrados: <n>
P1 encontrados: <n>
P2 encontrados: <n>

Existe criação líquida de dinheiro: SIM / NÃO / NÃO COMPROVADO
Existe oversell válido: SIM / NÃO / NÃO COMPROVADO
Existe leak Hub/anon: SIM / NÃO
Existe cron explorável: SIM / NÃO / NÃO COMPROVADO
Existe cross-user: SIM / NÃO
Existe cadeia órbita→caixa P0/P1: SIM / NÃO

Anon Hub exercitado: SIM / NÃO
Cron/job exercitado: SIM / NÃO
Último ciclo nova classe P0/P1: SIM / NÃO
ATROFIA (só redescobriu classes fechadas): SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**ATROFIA_ABORT** se ≥50% dos findings forem classes listadas em ANTI-OBJETIVO — para e muda de lente; não inventes FAIL.

**PASS_CEGO_SATURADO** só se: ≥4 lentes E*, anon Hub + cron tentados (ou lacuna), último ciclo sem classe nova P0/P1, **ATROFIA=NÃO**.

--------------------------------------------------
REGRA FINAL
--------------------------------------------------
Indep antigo = largura saturada. B = sombras. C = caixa. D = costura.  
**Tu (E) atacás a órbita: Hub, cron, notif, bundle, Connect, soft-delete.**

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO RE-AUDITAR O FREEZE 1442.**
