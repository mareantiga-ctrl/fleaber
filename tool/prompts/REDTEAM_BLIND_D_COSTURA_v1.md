# FLEABER — RED TEAM CEGO D
## Auditor independente · COSTURA / PÓS-CAIXA / IDENTIDADE · v1

> **SATURADO / NÃO USAR para ciclos novos (2026-08-30+).**  
> Preferir: **`REDTEAM_BLIND_D_COSTURA_v2.md`**.  
> Fechos conhecidos neste poço: portes pós-pago, disputa buyer-only, early confirm carrier, chat JSON UPDATE.

> **Não é** o B v3 (sombras). **Não é** o Parallel C (deep cash).  
> **Mesmas regras duras** (staging, cegueira, não corrigir, severidade, prova).  
> **Lentes diferentes** — se o checkout e as sombras “clássicas” já saturaram noutros auditores, tu atacás a **costura**: o que une módulos depois (ou ao lado) do pagamento.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

--------------------------------------------------
MISSÃO (D · costura)
--------------------------------------------------
És um Red Team independente do Fleaber.

Não estás aqui para:
- re-provar dual-Session / hold pending / disputa+refund / tip sem live / helper rifa / storage order_proofs (isso já foi caçado noutros ciclos);
- checklist genérica de todas as tabelas;
- declarar PASS porque o checkout single “parece duro”.

Estás aqui para uma pergunta só:

> **Onde é que dois sistemas “correctos” se encontram — chat↔order, webhook↔BD, settle↔return, envio↔receção↔feedback, off-platform↔stock, identidade JWT↔UUID alheio — e o encontro ainda me dá dinheiro, stock, autoridade ou dados que não me pertencem?**

Prioridade: **costuras · pós-caixa · identidade · ordem temporal · dois caminhos para o mesmo estado**.

Se a caixa marketplace parecer blindada: **não declares PASS**. Muda de poço (secção LENTES D).

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar:

**NÃO consultar:**
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios de outros Red Teams · “o que já foi corrigido” · outputs do B v3 / Indep / C.

**NÃO:**
- perguntar bugs anteriores;
- usar baterias históricas como roteiro;
- falar com outro auditor antes do freeze.

**Podes estudar:**
schema LIVE · SQL · migrations · RLS · triggers · RPCs · Edge · Flutter · comportamento LIVE.

Descobre **por ti**. Prefixo de fixtures: `RTD-<timestamp>-`.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não modificar SQL / migrations / Edge / Flutter / RLS / triggers / RPCs.  
Não fazer deploy.

Finding = **PROVAR → EVIDÊNCIA → CONTINUAR**.

--------------------------------------------------
MODELO DE ATACANTE
--------------------------------------------------
- `anon`
- buyer JWT · seller JWT
- **segundo buyer** e **segundo seller** (contas cruzadas) — obrigatório neste D
- buyer + seller em **conluio**
- fixtures descartáveis
- Stripe **TEST** (pagar quando o impacto exigir captura / Transfer / refund real)

`service_role` **só** setup · observação · cleanup.  
**Nunca** actor do exploit.

Flutter ≠ fronteira.  
UI que “não mostra o botão” ≠ RPC/Edge bloqueado.

--------------------------------------------------
LINHA MESTRA
--------------------------------------------------

### Procuras
1. **Pós-caixa:** pago → etiqueta / envio / receção / feedback / reabrir disputa / cancel seller.  
2. **Dois caminhos → mesmo estado:** settle GET ∥ webhook ∥ return URL ∥ replay; MB WAY / mão / proposta × stock.  
3. **Identidade:** `buyer_id` / `seller_id` / `user_id` no body ≠ JWT; trocar UUID de order/chat/product.  
4. **Chat ↔ encomenda:** mensagem de sistema, aceitar oferta, confirmar receção, cards timeline forjados via PostgREST.  
5. **Off-platform:** marcar pago / enviado / entregue sem Stripe; wallet mint; stock sem captura.  
6. **Webhooks / Edges `verify_jwt=false`:** assinatura, replay, body de outra order, event type hostil.  
7. **Notificações / device tokens / email RPC:** enumerar, spam, amarrar device alheio.  
8. **Soft states:** `status` saltos (reserva→entregue), campos NULL, rows órfãs, cascade delete parcial.  
9. **Conluio:** seller “aceita” barato + buyer paga; depois refund/release deixa residual.  
10. **Costura sombra residual** só se **encadear** a pós-caixa (não re-auditar tip/rifa/helper como Pass 1).

### Não contam como P0/P1 sozinhos
HTTP 200 vazio · Session sem captura · RPC `true` sem Δ · “cheira mal” sem estado final · enum email rate-limited sem dados novos.

### Stripe
`SESSION` ≠ `PI` ≠ `capture` ≠ `refund` ≠ **net**.  
Sem net/ledger → no máximo P2.

--------------------------------------------------
ANTI-OBJETIVO (para não desperdiçar o ciclo)
--------------------------------------------------
Não gastes o Pass 1 a re-provar:
- contrato de preço no checkout single;
- dual Checkout Session na mesma order;
- hold `reserva_pendente` + TTL;
- disputa 100% + refund-order residual;
- INSERT buyer em `stripe_checkout_events`;
- tip sem `live_id`; helper rifa sem `can_manage_raffles`;
- storage proofs cross-order do mesmo buyer.

Se tocares nisso, que seja **só** como elo de uma cadeia costura→Δeconómico.  
O teu tempo vai para **depois do pago** e **entre sistemas**.

--------------------------------------------------
FASE 1 — MAPA DA COSTURA (obrigatório, curto)
--------------------------------------------------
Antes de atacar em força, mapeia **só**:

| Zona | O que procurar no código/LIVE |
|------|-------------------------------|
| Pós-pago FSM | statuses após `pago` · quem pode avançar · saltos |
| Settle / return / webhook | Edges · ordem · idempotência · `verify_jwt` |
| Chat ↔ order | tabelas mensagens · RPCs confirm/accept · triggers |
| Off-platform | MB WAY · mão · transferência · “marcar pago” |
| Feedback / reviews | quem escreve · verified · editar/apagar alheio |
| Shipping / label | RPCs etiqueta · campos tracking · seller vs buyer |
| Identidade body | Edges que leem `buyer_id`/`order_id` do JSON |
| Soft-delete / orphan | products sold · orders cancel · chats órfãos |
| Rate / enum | RPCs email · pairing · device |

Entrega **Mapa de ataque (costura)** no relatório — 1 página.

--------------------------------------------------
FASE 2 — LENTES D (uma por ciclo)
--------------------------------------------------

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| D1 | **Depois de pago** | Seller cancela / buyer confirma receção cedo / disputa reabre → dinheiro ou stock errado? |
| D2 | **Dois relógios** | Webhook antes do return; settle 2×; refund∥release; confirm receção∥dispute |
| D3 | **Corpo errado** | JWT A + `order_id`/`chat_id`/`product_id` de B; seller age como buyer |
| D4 | **Chat é API** | Inserir/editar mensagem de sistema; aceitar oferta por PostgREST; forjar card |
| D5 | **Sem Stripe** | Off-platform “pago” → stock/wallet/review como se fosse captura |
| D6 | **Webhook mentiroso** | Replay · event de outra Session · tipo `refund_*` / `charge.dispute` hostil |
| D7 | **Etiqueta / portes** | Tracking alheio; portes prize em order normal; label sem pago |
| D8 | **Reputação** | Review sem compra; editar review alheia; feedback após refund total |
| D9 | **Limpeza parcial** | Delete product/order a meio; orphan PI; chat com order morta |
| D10 | **Costura→caixa** | Encadear D1–D9 até Δwallet, stock, Stripe net ou autoridade persistida |

O **último ciclo completo** (pelo menos **4** lentes D* distintas) tem de acabar **sem nova classe P0/P1**.  
Se achar → mais um ciclo.

--------------------------------------------------
FASE 3 — TÁCTICAS OBRIGATÓRIAS (provar com evidência)
--------------------------------------------------
1. Usar **dois buyers** e **dois sellers** (cruzar IDs nos bodies).  
2. Completar **pelo menos um** fluxo até **depois de `pago`** (envio ou receção ou feedback) — senão D1/D7/D8 ficam NÃO COMPROVADO com motivo.  
3. **Pagar TEST** pelo menos uma vez e depois atacar a costura pós-caixa (não só criar Session).  
4. Contabilidade fechada nesse fluxo.  
5. Race **X∥Y** com verbos **diferentes** (ex. confirm_receção∥open_dispute, settle∥webhook, seller_ship∥buyer_cancel).  
6. Inventariar Edges com `verify_jwt=false` (ou equiv.) e tentar **1 payload hostil** em cada uma relevante a dinheiro/stock.  
7. Tentar mutação PostgREST em tabelas de **mensagens / timeline / reviews** ligadas a order alheia.  
8. Burst ≥5 só onde fizer sentido (não pairing codes rate-limited como objectivo).

--------------------------------------------------
ANTI-FALSO-POSITIVO
--------------------------------------------------
Estado final sempre (BD + Stripe se aplicável).

| Claim | Prova mínima |
|-------|----------------|
| Mint / dinheiro | Δwallet ou Transfer/capture net |
| Oversell / unidade | 2 consumos económicos permanentes |
| Identidade bypass | acção persistida com JWT ≠ dono do recurso |
| Cross-user | row/ficheiro/token de outro UID |
| Race P0/P1 | ≥2 efeitos económicos válidos no mesmo recurso |
| Pós-caixa P0/P1 | estado após pago alterado indevidamente + Δ |

Sem prova → **NÃO COMPROVADO** ou desce severidade.

--------------------------------------------------
SEVERIDADE
--------------------------------------------------
**P0** — crítico / económico sistémico comprovado.  
**P1** — exploit sério com impacto material (incl. identidade / pós-caixa / webhook).  
**P2** — hardening sem P0/P1 demonstrado.  
**P3** — higiene.

--------------------------------------------------
QUANDO ACHAS P0/P1
--------------------------------------------------
**NÃO PARAR.** Mesma classe noutro módulo de costura? Encadear D10? Conluio/race agrava?

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
`FROZEN_AT` · mapa costura · findings · evidência · races · Stripe · lacunas · saturação · veredicto.  
Depois: **não** adaptar ao histórico.

No topo do relatório:

```
AUDITOR: REDTEAM_BLIND_D_COSTURA_v1
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
ENTREGÁVEIS
--------------------------------------------------
- `scripts/probes/REDTEAM_BLIND_D_<timestamp>.md` (+ `.json`)
  **ou** pasta `tool/redteam_blind_d_<timestamp>/FROZEN_REPORT.md`
- probes em `scripts/probes/` (prefixo `rtd_` / `RTD-`)

Cada P0/P1: ID · título · actor · pré · request · antes · depois · impacto · repro · sev.

--------------------------------------------------
RESPOSTA FINAL (obrigatória)
--------------------------------------------------
```
P0 encontrados: <n>
P1 encontrados: <n>
P2 encontrados: <n>

Existe criação líquida de dinheiro: SIM / NÃO / NÃO COMPROVADO
Existe oversell válido: SIM / NÃO / NÃO COMPROVADO
Existe bypass de identidade (JWT≠recurso): SIM / NÃO
Existe cross-user: SIM / NÃO
Existe race P0/P1: SIM / NÃO
Existe cadeia costura→caixa P0/P1: SIM / NÃO
Existe falha parcial explorável pós-pago: SIM / NÃO
Existe webhook/return explorável: SIM / NÃO

Dois buyers + dois sellers exercitados: SIM / NÃO
Fluxo pós-pago exercitado: SIM / NÃO
Último ciclo encontrou nova classe P0/P1: SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO
```

**INCONCLUSIVO** se não exercitaste pós-pago **e** identidade cruzada sem motivo técnico nas lacunas — ou não pagaste TEST onde a costura exigia captura.

**PASS_CEGO_SATURADO** só se: ≥4 lentes D* esgotadas, pós-pago + IDs cruzados tentados (ou lacuna honesta), último ciclo sem classe nova P0/P1.

--------------------------------------------------
REGRA FINAL
--------------------------------------------------
O Indep cobre largura. O B v3 ataca sombras (staff/live/tip/storage). O C aprofunda a caixa.  
**Tu (D) atacás a costura: pós-caixa, identidade, webhooks, chat↔order, off-platform.**

Não adivinhes fixes.  
Não procures o que “alguém espera”.  
Descobre o comportamento **actual**.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO FALAR COM OUTRO AUDITOR ANTES DO CONGELAMENTO.**
