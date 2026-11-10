# FLEABER — RED TEAM CEGO B
## Auditor independente adversarial · descoberta livre · v3 (sombras)

> **SATURADO / NÃO USAR para ciclos novos (2026-08-30+).**  
> Preferir: **`REDTEAM_BLIND_E_ORBITA_v1.md`** (órbita) ou **`REDTEAM_BLIND_D_COSTURA_v1.md`** (pós-caixa).  
> Este v3 fica só como histórico de lentes staff/live/tip/storage.

> **Substitui** `REDTEAM_BLIND_B_SURPRESA_v2.md`.  
> Mesmas regras duras. **Lentes novas** — o caixa marketplace/checkout clássico está saturado; tu vais às **sombras**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

--------------------------------------------------
MISSÃO (v3)
--------------------------------------------------
És um Red Team independente do Fleaber.

Não estás aqui para:
- confirmar que o checkout “já está duro”;
- repetir dual-Session / hold / disputa wallet (isso é trabalho do Indep/C se quiserem);
- checklist genérica de todas as tabelas.

Estás aqui para uma pergunta só:

> **O que ainda se move em paralelo ao fluxo óbvio de compra — live, staff, storage, tips, payout, device, reputação, tokens — e como transformo isso em dinheiro, stock, autoridade ou dados que não me pertencem?**

Prioridade: **superfícies secundárias + composição entre sombra e caixa**.  
Uma feature “de apoio” correcta sozinha pode abrir a caixa quando encadeada.

Se o marketplace single-checkout parecer blindado: **não declares PASS**. Muda de poço (secção LENTES v3).

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar:

**NÃO consultar:**
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios de outros Red Teams · “o que já foi corrigido”.

**NÃO:**
- perguntar bugs anteriores;
- usar baterias históricas como roteiro;
- falar com Indep/C antes do freeze.

**Podes estudar:**
schema LIVE · SQL · migrations · RLS · triggers · RPCs · Edge · Flutter · comportamento LIVE.

Descobre **por ti**. Prefixo de fixtures: `RTB3-<timestamp>-`.

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
- **helper / staff** JWT (convite seller → helper) — obrigatório neste v3
- buyer + seller em **conluio**
- fixtures descartáveis
- Stripe **TEST** (pagar quando o impacto exigir captura/Transfer)

`service_role` **só** setup · observação · cleanup.  
**Nunca** actor do exploit.

Flutter ≠ fronteira.

--------------------------------------------------
LINHA MESTRA
--------------------------------------------------

### Procuras
1. Autoridade de **helper/staff** além do que o owner concedeu.  
2. **Live** (reserva, accept, convert, waitlist, live_item stock) × marketplace.  
3. **Rifa / prémio** (join, draw, prize order, portes prize).  
4. **Tip** (wallet tip, Checkout tip, settle tip).  
5. **Payout / Connect** (keys, crash, amount, conta alheia).  
6. **Storage** (provas, chat_media, order_proofs, prefixos).  
7. **Device / OCR / pairing** (token, seller bind, live alheia).  
8. **Mux / LiveKit** (stream key, token de sala alheia).  
9. **Reputação / dispute** (caminhos que ainda contam sem captura).  
10. Composição **sombra → caixa** (ex.: reserva live → order → checkout; tip → wallet; helper → refund).

### Não contam como P0/P1 sozinhos
HTTP 200 vazio · Session sem captura · RPC `true` sem Δ · “cheira mal” sem estado final.

### Stripe
`SESSION` ≠ `PI` ≠ `capture` ≠ `refund` ≠ **net**.  
Sem net/ledger → no máximo P2.

--------------------------------------------------
ANTI-OBJETIVO (para não desperdiçar o ciclo)
--------------------------------------------------
Não gastes o Pass 1 a re-provar:
- contrato de preço no checkout single;
- hold `reserva_pendente` stock=1;
- disputa 100% + refund-order residual;
- reuse de Checkout Session na mesma order.

Se tocares nisso, que seja **só** como elo de uma cadeia sombra→caixa.  
O teu tempo vai para módulos que o v2 pouco esgotou.

--------------------------------------------------
FASE 1 — MAPA DAS SOMBRAS (obrigatório, curto)
--------------------------------------------------
Antes de atacar em força, mapeia **só**:

| Zona | O que procurar no código/LIVE |
|------|-------------------------------|
| Staff/helpers | RPCs invite/accept · permissions JSON · `effectiveSellerId` |
| Live | reservation FSM · accept · convert · bag live · stock live_item |
| Raffle | join · draw · prize order · shipping prize |
| Tips | pending tip · Checkout tip · settle · wallet tip |
| Payout | Connect ready · debit · Transfer · idempotency · crash |
| Storage | buckets · policies · path traversal por UUID |
| Device/OCR/PS | device token · pairing · ingest bind |
| Realtime media | Mux create/complete · LiveKit token |
| Edges `verify_jwt=false` | quais e o que fazem sem JWT |

Entrega **Mapa de ataque (sombras)** no relatório — 1 página.

--------------------------------------------------
FASE 2 — LENTES v3 (uma por ciclo)
--------------------------------------------------

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| S1 | **Crachá emprestado** | Helper com permissão X consegue Y? Escalada? Agir como owner noutro seller? |
| S2 | **Directo vs loja** | Mesma unidade em live + marketplace; accept + checkout; waitlist + sold |
| S3 | **Rifa / prémio** | Ganhar sem elegibilidade; prize order barata; portes prize em order normal |
| S4 | **Gorjeta** | tip_id cliente; auto-tip; settle tip ≠ order; wallet tip mint |
| S5 | **Levantamento** | amount hostil; user_id cruzado; 2 keys; debit sem Transfer; Transfer órfã |
| S6 | **Ficheiros** | Ler/escrever prova ou media de outro; listar prefixo alheio |
| S7 | **Dispositivo** | Token de comprador em live de outro; OCR amarra seller errado; pairing brute |
| S8 | **Sala / stream** | Token LiveKit / stream key Mux de live alheia |
| S9 | **Tempo** | Expirar hold/reservation/tip/session; TTL; relógio entre Edge e BD |
| S10 | **Sombra→caixa** | Encadear S1–S9 até Δwallet, stock, Stripe net ou autoridade persistida |

O **último ciclo completo** (pelo menos 4 lentes S* distintas) tem de acabar **sem nova classe P0/P1**.  
Se achar → mais um ciclo.

--------------------------------------------------
FASE 3 — TÁCTICAS OBRIGATÓRIAS (provar com evidência)
--------------------------------------------------
1. Criar **pelo menos um** helper real (convite + accept) e atacar **com o JWT do helper**.  
2. Abrir ou reutilizar **live** (Mux TEST ok) — sem live, S2/S3/S7/S8 ficam NÃO COMPROVADO com motivo.  
3. **Pagar TEST** num fluxo sombra duvidoso (tip **ou** prize shipping **ou** payout Transfer se saldo permitir).  
4. Contabilidade fechada nesse fluxo.  
5. Race **X∥Y** (não só o mesmo verbo): ex. accept∥cancel, tip settle∥refund, helper refund∥owner payout.  
6. Payload mutation nas Edges sombra: tip, connect, livekit, mux, OCR, pairing.  
7. Storage: tentar path de outro `buyer_id` / `order_id` / `seller_id`.  
8. Burst ≥5 onde fizer sentido (pairing codes **não** — rate-limit; sim reservation accept, tip create, payout keys).

--------------------------------------------------
ANTI-FALSO-POSITIVO
--------------------------------------------------
Estado final sempre (BD + Stripe se aplicável).

| Claim | Prova mínima |
|-------|----------------|
| Mint / dinheiro | Δwallet ou Transfer/capture net |
| Oversell / unidade | 2 consumos económicos permanentes |
| Staff bypass | acção persistida que a permission negava |
| Cross-user | row/ficheiro/token de outro UID |
| Race P0/P1 | ≥2 efeitos económicos válidos no mesmo recurso |

Sem prova → **NÃO COMPROVADO** ou desce severidade.

--------------------------------------------------
SEVERIDADE
--------------------------------------------------
**P0** — crítico / económico sistémico comprovado.  
**P1** — exploit sério com impacto material (incl. staff/live/storage sensível).  
**P2** — hardening sem P0/P1 demonstrado.  
**P3** — higiene.

--------------------------------------------------
QUANDO ACHAS P0/P1
--------------------------------------------------
**NÃO PARAR.** Mesma classe noutro módulo sombra? Encadear S10? Conluio/race agrava?

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
`FROZEN_AT` · mapa sombras · findings · evidência · races · Stripe · lacunas · saturação · veredicto.  
Depois: **não** adaptar ao histórico.

No topo do relatório:

```
AUDITOR: REDTEAM_BLIND_B_SURPRESA_v3
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
```

--------------------------------------------------
ENTREGÁVEIS
--------------------------------------------------
- `scripts/probes/REDTEAM_BLIND_B_<timestamp>.md` (+ `.json`)
- probes em `scripts/probes/`

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
Existe bypass de autoridade (incl. staff): SIM / NÃO
Existe cross-user: SIM / NÃO
Existe race P0/P1: SIM / NÃO
Existe cadeia sombra→caixa P0/P1: SIM / NÃO
Existe falha parcial explorável: SIM / NÃO
Existe exposição sensível (storage/token/stream): SIM / NÃO

Helper JWT exercitado: SIM / NÃO
Live exercitada: SIM / NÃO
Último ciclo encontrou nova classe P0/P1: SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO
```

**INCONCLUSIVO** se não exercitaste helper **e** live sem motivo técnico nas lacunas — ou não pagaste TEST onde a sombra exigia captura.

**PASS_CEGO_SATURADO** só se: ≥4 lentes S* esgotadas, helper+live tentados (ou lacuna honesta), último ciclo sem classe nova P0/P1.

--------------------------------------------------
REGRA FINAL
--------------------------------------------------
O Indep cobre largura. O Parallel C aprofunda a caixa.  
**Tu (B v3) atacas as sombras e as pontes sombra→caixa.**

Não adivinhes fixes.  
Não procures o que “alguém espera”.  
Descobre o comportamento **actual**.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO FALAR COM OUTRO AUDITOR ANTES DO CONGELAMENTO.**
