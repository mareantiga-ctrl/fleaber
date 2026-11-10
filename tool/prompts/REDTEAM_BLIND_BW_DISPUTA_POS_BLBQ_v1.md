# FLEABER — RED TEAM CEGO BW
## Auditor independente · PÓS-FECHO BLBQ · DISPUTA / ENVIO / DEVOLUÇÃO · v1

> Fechámos BLBQ disputa: replies proof **path-only** + host storage + sem `../` + sem `fleaber.pt`; disputa `proof_photos` sem `../`. Seller já não `pedido_devolucao`. Hostile BLBQ PASS.  
> **Poço:** ainda hostage PI, refund sem item, prova alheia, stock?  
> Staging · Stripe TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`. Sem números = INVÁLIDO.

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
**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBW-<timestamp>-` · `tool/redteam_blind_bw_<timestamp>/`.

> Depois do FSM BLBQ, ainda desvio devolução / disputa / dinheiro?

**Exactos BQ/BK (não contar):** reply signed URL com needle em `?`/`#` · `../` em `proof_photos` · `https://fleaber.pt/…` · seller `pago`→`pedido_devolucao`.  
**Novas:** slash unicode `／` no path · 2.ª disputa · refund parcial · `devolvida` cedo · buyer `concluido` mid-return · stock restore dup · B2 INSERT disputa · Edge `amount` no body · `return_label_url` wrap · storage list prefixo alheio.

--------------------------------------------------
LENTES BW (8/8)
--------------------------------------------------
BW1 pedido_devolucao · BW2 hops FSM · BW3 provas · BW4 refund · BW5 stock · BW6 release · BW7 2.º actor · BW8 caixa.

Não ler BQ/BK/BE/AY.

```
AUDITOR: REDTEAM_BLIND_BW_DISPUTA_POS_BLBQ_v1
production_touched: false · fase4: false · corrections_applied: false
```
Checklist 28. **NÃO CORRIGIR.**
