# FLEABER — RED TEAM CEGO BQ
## Auditor independente · PÓS-FECHO BFBK · DISPUTA / ENVIO / DEVOLUÇÃO · v1

> Fechámos BFBK: seller **não** `pedido_devolucao`; proof/label needle **só no path**. Hostile BFBK PASS.  
> **Poço:** ainda hostage PI, refund sem item, prova alheia, stock?  
> Staging · Stripe TEST · **não corrigir**.

## CONTAGEM (obrigatório — ANTES de findings)
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = relatório INVÁLIDO.

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N

1. P0? SIM|NÃO   2. Quantos P0: N
3. P1? SIM|NÃO   4. Quantos P1: N
5. P2? SIM|NÃO   6. Quantos P2: N
7. P3? SIM|NÃO   8. Quantos P3: N
```
**Sem TOTAL → INVÁLIDO.** O fecho começa sempre por colar esta CONTAGEM no chat.

Prefixo `RTBQ-<timestamp>-` · `tool/redteam_blind_bq_<timestamp>/`.

## MISSÃO
> Depois do FSM BFBK, ainda desvio devolução / disputa / dinheiro?

**Exactos BK/AY (não contar):** seller `pago`→`pedido_devolucao` · proof query-string wrap.  
**Novas:** disputa 2.ª · partial · fragment `#` no URL · replies proof · `devolvida` cedo · buyer `concluido` mid-return · stock restore dup · B2 disputa · Edge amount · `../` path.

## LENTES BQ (8/8)
BQ1 pedido_devolucao · BQ2 hops FSM · BQ3 provas · BQ4 refund · BQ5 stock · BQ6 release · BQ7 2.º actor · BQ8 caixa.

Não ler BK/BE/AY.

```
AUDITOR: REDTEAM_BLIND_BQ_DISPUTA_POS_BFBK_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
