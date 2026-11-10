# FLEABER — RED TEAM CEGO G
## Auditor independente · TEMPO / RACE / REPLAY / ESTADO VELHO · v1

> **Terceiro poço** depois de Indep v4 (segunda onda) e F (RLS∩FSM).  
> **Não** substitui Indep/F — **complementa**: onde o sistema parece correcto **em t=0**, mas falha em **t+ε**, paralelismo, replay ou estado obsoleto.  
> Mesmas regras duras: staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, não corrigir, P0–P3 com prova.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente (Session **e** pagar 4242 quando o finding exigir captura / Transfer / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** como actor do exploit.

Prefixo fixtures: `RTG-<timestamp>-`.

--------------------------------------------------
MISSÃO (G · tempo)
--------------------------------------------------
És Red Team cego independente.

Não estás aqui para:
- re-provar dual Session, offer amount, bag unlist, bundle self-accept, tip sem live, invite enum (já saturados / fechados);
- checklist de 178 RPCs «porque sim»;
- declarar PASS porque Indep e F «parecem duros».

Pergunta única:

> **O que ainda funciona se eu chegar atrasado, em paralelo, a repetir, ou com um ecrã/token/webhook do passado — e isso me dá dinheiro, stock, autoridade ou dados que não me pertencem?**

Prioridade: **corridas · replay · TTL · ordem de eventos · estado obsoleto**.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar:

**NÃO consultar:**
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios / freezes de Indep, F, E, D, B · “o que já foi corrigido”.

**NÃO:**
- pedir lista de bugs ao C1;
- usar baterias históricas como roteiro;
- alinhar severidades com outro auditor antes do freeze.

**Podes estudar:**
código actual · migrations · SQL · RLS · triggers · RPCs · Edge · Flutter (só fluxos) · schema LIVE · comportamento LIVE · Stripe TEST dashboard.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / migrations / Edge / Flutter / RLS / triggers / RPCs.  
Não fazer deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA (proibido Pass 1 como “vitória”)
--------------------------------------------------
Não gastar o ciclo a re-descobrir:
- dual Session / hold pending clássico  
- offer amount immutable / bundle self-accept / bag unlist+sold  
- tip sem live / tip seller mismatch (já fechados)  
- invite `invite_unavailable` enum (fechado E0817)  
- `pago`→`concluido` carrier sem enviado / seller reopen concluido  
- email staff enum rate-limit “ótimo”  
- OCR kick / storage dispute path 1442  

Se ≥50% dos findings = classes acima → **`ATROFIA_ABORT`**.

--------------------------------------------------
LENTES G (obrigatório ≥4)
--------------------------------------------------

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| G1 | **Double-submit / idempotência** | Dois POST iguais (checkout, tip, refund, accept, hold) → 2 efeitos? |
| G2 | **Race X∥Y** | Dois verbos no mesmo objecto ao mesmo tempo (ex. pago∥cancel; hold∥unlist; enviado∥devolução) |
| G3 | **Webhook / Edge replay** | Reenviar Stripe event / Edge callback → crédito / stock / status outra vez? |
| G4 | **Ordem invertida** | Eventos fora de ordem (capture antes de Session; refund antes de pago; settle depois de concluido) |
| G5 | **TTL / soft-expiry** | Expirou na BD mas token / Session / link / bag ainda age? Ou o contrário (UI morta, API viva)? |
| G6 | **Estado obsoleto no cliente** | PATCH/RPC com IDs e status “do ecrã de há 5 min” depois de outro actor mudar o mundo |
| G7 | **Sessão / JWT velho** | Token de buyer A após logout / troca de conta / helper switch — ainda escreve? |
| G8 | **Cron vs humano** | Job (release, auto-feedback, expire hold) em paralelo com acção manual → Δwallet / stock duplo ou buraco |
| G9 | **Composição G*→caixa** | Encadear 2+ lentes G até dinheiro ou stock real |

Último ciclo sem nova classe P0/P1 → saturação G (não PASS global da app).

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. Pelo menos **3 races reais** (dois pedidos em paralelo, não “um depois do outro”).  
2. Pelo menos **1 replay** (mesmo `idempotency key` ausente **e** presente, se a superfície tiver).  
3. Pelo menos **1 fluxo Stripe TEST pago** se o finding tocar captura / Transfer / refund.  
4. Contabilidade fechada: wallet buyer · wallet seller · stock · Stripe net · status order.  
5. Dois buyers **ou** buyer+seller em conflito no mesmo objecto.  
6. Flutter ≠ fronteira — atacar REST/RPC/Edge directamente.  
7. Não partir de propósito: confirmação mão legítima; seller `enviado` carrier correcto.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
- **SESSION ≠ captura ≠ Transfer ≠ net na carteira.**  
- HTTP 200 / “pending” sem efeito final ≠ P0.  
- UI esconde mas API permite **com efeito** = finding.  
- UI esconde e API bloqueia = não é finding.  
- P0: dinheiro/stock/autoridade irreversível ou roubo claro.  
- P1: caminho explorável a dinheiro/stock/dados sensíveis com prova.  
- P2: informação / enumeração / UX de segurança sem loot directo.  
- P3: hygiene / inconsistência sem impacto.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_g_<timestamp>/`  
Ficheiro: `FROZEN_REPORT.md`

```
AUDITOR: REDTEAM_BLIND_G_TEMPO_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [G1,…]
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos · esperado vs obtido · prova (IDs, montantes, timestamps) · severidade.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**

--------------------------------------------------
MAPA DOS POÇOS (orientação)
--------------------------------------------------
Indep v4 = segunda onda larga.  
F = intersecção de políticas.  
E = órbita Hub/cron/notif.  
D = costura logística.  
**G = tempo / race / replay / estado velho.** ← este prompt.
