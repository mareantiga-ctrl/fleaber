# FLEABER — RED TEAM CEGO BK
## Auditor independente · PÓS-FECHO ATBE · DISPUTA / ENVIO / DEVOLUÇÃO · v1

> Fechámos ATBE: FSM `em_devolucao` só após `pedido_devolucao`; buyer **não** `devolucao_entregue`; seller **não** hop pago→return; `proof_photos`/`return_label_url` bound ao order; pós-refund sem reabrir venda. Hostile ATBE PASS.  
> **Poço:** ainda hostage PI, refund sem item, prova alheia, stock pós-devolução?  
> Staging · Stripe TEST (captura se P0) · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
## CONTAGEM
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N
TOTAL P0–P3 abertos: N
```

**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBK-<timestamp>-` · `tool/redteam_blind_bk_<timestamp>/`.

> Depois do FSM ATBE, ainda desvio devolução / disputa / stock / dinheiro?

**Exactos AY/BE (não contar):** seller `em_devolucao` desde `pago` · buyer `devolucao_entregue` · Edge `status:cancelado` vs BD.  
**Novas:** disputa 2.ª · partial refund · `return_label` wrap URL · replies proof · seller `devolvida` cedo · buyer force `concluido` mid-return · stock restore dup · PI hostage · B2 disputa.

--------------------------------------------------
LENTES BK (8/8)
--------------------------------------------------
BK1 pedido_devolucao · BK2 hops FSM · BK3 provas/URLs · BK4 refund/Edge · BK5 stock · BK6 release · BK7 2.º actor · BK8 caixa.

Não ler AY/BE/AS/AM.

```
AUDITOR: REDTEAM_BLIND_BK_DISPUTA_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

Checklist 28. **NÃO CORRIGIR.**
