# FLEABER — RED TEAM CEGO P
## Auditor independente · COMPOSIÇÃO → CAIXA · v1

> **Não** é Indep / F / G / K / L / M de um poço só.  
> N e O atacam directo e disputa/envio. **Tu encadeias 2–3 buracos** até dinheiro, stock ou autoridade persistida.  
> Staging `fxdknzrqjenzqcvnwqqq`, Stripe TEST, cegueira, **não corrigir**.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente (Session **e** pagar 4242 / `pm_card_visa` quando o finding exigir captura / Transfer / refund).  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Actors: `anon` · buyer JWT · seller JWT · 2.º buyer · 2.º seller · conluio.  
`service_role` **só** fixture / observação / cleanup — **nunca** actor do exploit.

Prefixo fixtures: `RTP-<timestamp>-`.

--------------------------------------------------
MISSÃO
--------------------------------------------------
> **Dois ou três furos que sozinhos “HOLD” — encadeados, abrem a caixa?**

Um P2 de chat, um PATCH de catálogo, um GET settle, um body de Edge: **sozinhos** podem ser higiene.  
**Juntos** podem ser Δwallet, oversell, captura a menos, refund a mais.

Prioridade: **cadeia até efeito económico** (Stripe net, stock permanente, wallet, autoridade de pago).

Não re-provar um poço isolado já saturado. Encadeia.

--------------------------------------------------
CEGUEIRA ABSOLUTA
--------------------------------------------------
Antes de congelar **NÃO** ler:
`AUDITORIA*` · `HARDENING*` · `RETESTE*` · `REAUDITORIA*` · `PRODUCTION_GATE*`  
relatórios K/L/M/H/I/J/N/O · “o que já foi corrigido”.

**Podes estudar:** código actual · SQL · RLS · Edge · schema LIVE · comportamento LIVE.

Descobre **por ti**. Congela. Só depois (opcional) comparar.

--------------------------------------------------
NÃO CORRIGIR
--------------------------------------------------
Não alterar SQL / Edge / Flutter / RLS. Não fazer deploy.  
Finding = **PROVAR → DOCUMENTAR → CONTINUAR**.

--------------------------------------------------
ANTI-ATROFIA
--------------------------------------------------
Proibido Pass 1 a “redescobrir” e parar em:
dual Session · bag unlist · seguro plain · list `chat_media` · resolve handle unpublished ·  
DELETE review→5★ · TTL resurrect · CORS `*.fleaber.pt` · mux draft.

Se o único “finding” for uma destas classes **sem** o segundo elo até caixa → **não conta**.  
≥50% findings = lista acima → **`ATROFIA_ABORT`**.

Encadear um P2 conhecido **até** refund / captura / stock **é** a missão (não é atrofia).

--------------------------------------------------
LENTES P (obrigatório ≥4)
--------------------------------------------------
| # | Lente | Pergunta |
|---|--------|----------|
| P1 | Mentira → caixa | Card/chat/UI «pago» → refund, release ou captura? |
| P2 | Dois caminhos, uma unidade | Live+marketplace · bag+single · offer+list · 2 buyers |
| P3 | Catálogo depois do contrato | Preço / qty / unlist / portes **depois** do hold → Session/captura |
| P4 | Identidade cruzada | Order A + Session B · buyer A + product B · settle alheio |
| P5 | Dois verbos pós-pago | Refund ∥ release ∥ disputa ∥ enviado ∥ concluido |
| P6 | Dois carris | Off-platform `pago` + Stripe na mesma order |
| P7 | Saco / conjunto | Refund 1 linha vs PI / stock das outras |
| P8 | Sombra → caixa | Tip / rifa / helper / reserva live → order / wallet |
| P9 | Body Edge × RLS | `amount`, `buyer_id`, `prize_shipping` até quote Stripe |
| P10 | Cadeia 2–3 elos | Qualquer combinação até Δwallet / stock / Stripe net |

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. ≥3 composições **distintas** (não 3× o mesmo par).  
2. ≥1 fluxo Stripe TEST **pago** + contabilidade (buyer wallet · seller wallet · PI · refund).  
3. Distinguir sempre: SESSION ≠ PI ≠ captura ≠ captura líquida.  
4. ≥1 race `Future.wait` com verbos diferentes no mesmo recurso.  
5. Dois buyers + dois sellers.  
6. Flutter ≠ fronteira. Hub ≠ fronteira.  
7. HTTP 200 sem Δ ≠ P0.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
SESSION criada ≠ dinheiro. Campo ecoado ≠ persistência.  
**P0** — fundos / oversell permanente / captura ou payout duplicado líquido.  
**P1** — caminho explorável com prova (incl. Session amount errado + via de pagar).  
**P2/P3** — hygiene / impacto limitado.

--------------------------------------------------
CONGELAMENTO · ENTREGA
--------------------------------------------------
Pasta: `tool/redteam_blind_p_<timestamp>/`  
Ficheiro obrigatório: **`FROZEN_REPORT.md`**

```
AUDITOR: REDTEAM_BLIND_P_COMPOSICAO_CAIXA_v1
FROZEN_AT: <ISO8601>
production_touched: false
fase4: false
corrections_applied: false
lentes_cobertas: [P1,…]
composicoes_distintas: <n>
VEREDICTO: FAIL_P0 | FAIL_P1 | FAIL_P2 | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

Por finding: ID · lente · actor · passos (cadeia) · esperado vs obtido · prova (IDs, montantes, Δ) · severidade.

```
P0 encontrados: <n>
P1 encontrados: <n>
P2 encontrados: <n>

Existe criação líquida de dinheiro: SIM / NÃO / NÃO COMPROVADO
Existe oversell válido: SIM / NÃO / NÃO COMPROVADO
Existe cadeia 2–3 elos → caixa P0/P1: SIM / NÃO
SESSION underpay (amount Stripe ≠ contrato): SIM / NÃO
Dois carris na mesma order: SIM / NÃO
Race dois verbos P0/P1: SIM / NÃO

Dois buyers + dois sellers: SIM / NÃO
Fluxo Stripe TEST pago: SIM / NÃO
Último ciclo nova classe P0/P1: SIM / NÃO
ATROFIA: SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO
```

**PASS_CEGO_SATURADO** só se: ≥4 lentes, ≥3 composições, Stripe TEST pago, ATROFIA=NÃO, último ciclo sem classe nova P0/P1.

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO.**
