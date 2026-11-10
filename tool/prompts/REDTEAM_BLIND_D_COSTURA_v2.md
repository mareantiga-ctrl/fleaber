# FLEABER — RED TEAM CEGO D
## Auditor independente · COSTURA v2 · LOGÍSTICA / DEVOLUÇÃO / MULTI-PEDIDO · v2

> **Substitui** `REDTEAM_BLIND_D_COSTURA_v1.md` (saturado após 1858 + fechos portes/disputa/chat).  
> **Mesmas regras duras:** staging, cegueira, não corrigir, severidade, prova, dois buyers+sellers, Stripe TEST.  
> **Poço novo:** logística fina, devolução, conjunto/bundle pós-aceite, auto-feedback, etiqueta — **não** re-provar v1.

--------------------------------------------------
AMBIENTE AUTORIZADO
--------------------------------------------------
Staging Supabase: `fxdknzrqjenzqcvnwqqq`  
Stripe: **TEST** exclusivamente.  
PRODUÇÃO: **PROIBIDO TOCAR.**  
FASE 4: **NÃO INICIAR.**

Prefixo fixtures: `RTD2-<timestamp>-`.

--------------------------------------------------
MISSÃO (D v2)
--------------------------------------------------
És Red Team cego independente.

Pergunta:

> **Depois do pago (e depois dos fechos de portes/disputa/receção), o que ainda une envio, devolução, conjunto, feedback automático e etiqueta — e me dá dinheiro, stock ou autoridade indevida?**

Prioridade: **logística · devolução · multi-encomenda · auto-estados**.

--------------------------------------------------
CEGUEIRA · NÃO CORRIGIR · ATACANTE
--------------------------------------------------
Iguais ao v1:
- Não ler HARDENING / outros freezes como roteiro.
- Não alterar código / deploy.
- anon · buyer · seller · 2.º buyer · 2.º seller · conluio.
- `service_role` só fixture / observação / cleanup.
- Flutter ≠ fronteira.

--------------------------------------------------
ANTI-ATROFIA (proibido Pass 1)
--------------------------------------------------
Não re-provar:
- dual Session / hold pending / tip sem live / helper rifa / storage 1442  
- `pago`→`concluido` carrier sem enviado  
- null/garbage shipping → mão pós-pago  
- seller PATCH disputa `resolvida`  
- chat UPDATE de card `FLEABER_JSON_V1`  
- offer amount / bundle self-accept / bag unlist (E)

Se ≥50% findings = lista acima → **ATROFIA_ABORT**.

--------------------------------------------------
LENTES D2 (nova onda)
--------------------------------------------------

| # | Lente | Pergunta-guia |
|---|--------|----------------|
| D2-1 | **Etiqueta / tracking** | Tracking alheio; marcar enviado sem captura; label sem pago |
| D2-2 | **Devolução** | `pedido_devolucao` / portes de volta / stock restore errado |
| D2-3 | **Partial refund disputa** | Oferta parcial + release + Stripe residual |
| D2-4 | **Conjunto / bundle** | Aceite seller → N orders; confirmar receção 1 de N; release cedo |
| D2-5 | **Auto-feedback / cron** | Feedback automático 48h; disparo JWT; review dupla |
| D2-6 | **MB WAY / mão timeline** | Cards chat vs FSM; marcar pago off-platform × wallet |
| D2-7 | **Settle vs envio** | Session paga com portes A; order logistics B |
| D2-8 | **Multi-PI / refund parcial** | Refund item do saco; stock das outras linhas |
| D2-9 | **Identidade fina** | `bundle_id` / chat_id cruzados pós-pago |
| D2-10 | **Costura→caixa** | Encadear até Δwallet / stock / Stripe net |

≥4 lentes D2-*; último ciclo sem nova classe P0/P1.

--------------------------------------------------
TÁCTICAS OBRIGATÓRIAS
--------------------------------------------------
1. Dois buyers + dois sellers.  
2. Pelo menos um fluxo **pago TEST** até envio **ou** disputa/devolução.  
3. Contabilidade fechada.  
4. Race X∥Y com verbos diferentes (ex. enviado∥pedido_devolucao).  
5. Bundle **ou** saco multi se existir superfície.  
6. Tentar auto-feedback / cron sem ser o job legítimo.  
7. Não partir: confirmação mão legítima; seller `enviado` carrier.

--------------------------------------------------
ANTI-FALSO-POSITIVO · SEVERIDADE
--------------------------------------------------
Iguais ao v1 (prova de estado final; P0/P1/P2/P3).  
SESSION ≠ captura ≠ net.

--------------------------------------------------
CONGELAMENTO
--------------------------------------------------
```
AUDITOR: REDTEAM_BLIND_D_COSTURA_v2
FROZEN_AT: ...
production_touched: false
fase4: false
corrections_applied: false
```

Entrega: `tool/redteam_blind_d_<timestamp>/FROZEN_REPORT.md`  
ou `scripts/probes/REDTEAM_BLIND_D_<timestamp>.md`

--------------------------------------------------
RESPOSTA FINAL
--------------------------------------------------
```
P0 encontrados: <n>
P1 encontrados: <n>
P2 encontrados: <n>

Existe criação líquida de dinheiro: SIM / NÃO / NÃO COMPROVADO
Existe oversell válido: SIM / NÃO / NÃO COMPROVADO
Existe bypass de identidade: SIM / NÃO
Existe cross-user: SIM / NÃO
Existe race P0/P1: SIM / NÃO
Existe cadeia costura→caixa P0/P1: SIM / NÃO
Existe falha logística/devolução explorável: SIM / NÃO
Existe bundle/multi-pedido P0/P1: SIM / NÃO / NÃO COMPROVADO

Dois buyers + dois sellers: SIM / NÃO
Fluxo pós-pago (envio ou devolução): SIM / NÃO
Último ciclo nova classe P0/P1: SIM / NÃO
ATROFIA: SIM / NÃO
SATURAÇÃO: SIM / NÃO
PRODUÇÃO TOCADA: NÃO
FASE 4: NÃO

VEREDICTO: FAIL_P0 | FAIL_P1 | INCONCLUSIVO | PASS_CEGO_SATURADO | ATROFIA_ABORT
```

**PASS_CEGO_SATURADO** só se: ≥4 lentes D2-*, pós-pago exercitado, ATROFIA=NÃO, último ciclo sem classe nova P0/P1.

--------------------------------------------------
REGRA FINAL
--------------------------------------------------
v1 = portes / disputa / early confirm (fechado).  
**Tu (v2) = logística, devolução, bundle, auto-feedback.**

**NÃO CORRIGIR. NÃO TOCAR PRODUÇÃO. NÃO REPETIR O POÇO v1.**
