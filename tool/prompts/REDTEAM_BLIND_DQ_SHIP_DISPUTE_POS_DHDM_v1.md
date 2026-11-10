# FLEABER — RED TEAM CEGO DQ · DEEP · PÓS-DHDM
## Envio / disputa / storage / label — **quota ≥14 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Provas, paths, janela de disputa, selo de portes. Não chase FOMO.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM + `RESUMO_NUMERICO`.

Prefixo `RTDQ-<timestamp>-` · pasta `tool/redteam_blind_dq_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**14**.
2. **≥1** order paga (ou fixture paid) + tentativa disputa/refund.
3. **≥3 classe_nova** path/storage/janela (não só `%252f` clássico).
4. Oráculo: storage URL + RPC + order status + (se refund) stock.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Proof URL: path canónico, sem traversal, sem concat, sem `//` hostil após host mal usado.  
> Disputa só na janela e pelo buyer certo.  
> Shipping seal: buyer não muda portes após Session/pago.

--------------------------------------------------
## ANTI-ATROFIA (HOLD)
--------------------------------------------------
label `%252f` deny · `//` após host já tratado · dispute window 403 residual

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥14)
--------------------------------------------------

### DQ-A Storage / proof (≥5)
A1 path `../` / encoded dots  
A2 URL outro buyer / outra order  
A3 content-type / extension mismatch  
A4 signed URL reuse após revoke  
A5 **classe nova**: unicode slash / overlong UTF-8 / null omit (sem chr(0) se Postgres rebenta — documentar)

### DQ-B Disputa FSM (≥4)
B1 disputa order alheia  
B2 disputa fora de janela  
B3 disputa∥refund race  
B4 open disputa + PATCH status hostil

### DQ-C Shipping (≥3)
C1 PATCH shipping após `cs_` open  
C2 PATCH shipping após pago  
C3 bag lines com shipping misturado

### DQ-D Caixa (≥2)
D1 pago + label feliz OK  
D2 seller marca enviado sem prova (documentar regra)

**Total = 14.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DQ1 path · DQ2 actor · DQ3 janela · DQ4 race · DQ5 shipping seal · DQ6 storage · DQ7 stock pós-refund

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
≥14 · ≥3 classe_nova · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DQ_SHIP_DISPUTE_POS_DHDM_v1
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
