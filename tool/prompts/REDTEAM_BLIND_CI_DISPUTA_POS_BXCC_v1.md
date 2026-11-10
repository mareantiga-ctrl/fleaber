# FLEABER — RED TEAM CEGO CI · DEEP
## Auditor independente · PÓS-FECHO BXCC · DISPUTA / ENVIO / DEVOLUÇÃO · v1-deep

> Fechámos BXCC: path canonical multi-pass (bidi / `%252e` / unicode slash). Hostile PASS.  
> **DENSO:** matriz path + 2.ª disputa + partial + stock restore + Edge amount na mesma corrida.  
> Staging · TEST · **NÃO CORRIGIR** · Fase 4 **não**.

--------------------------------------------------
## CONTAGEM (obrigatório — ANTES de findings)
--------------------------------------------------
```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```
**Sem TOTAL → INVÁLIDO.**

Prefixo `RTCI-<timestamp>-` · `tool/redteam_blind_ci_<timestamp>/`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Ainda desvio **devolução/refund**, **prova alheia**, **stock restore duplo**, ou **fecho seller cedo** — além do path bidi/`%252e` exacto?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar exactos: bidi path · `%252e%252f` · `／` unicode slash já HOLD residual.  
Conta: 2.ª disputa · partial refund · `devolvida` cedo · B2B/B2 conluio · Edge amount · stock restore×2 · carrier early confirm novo vector.

--------------------------------------------------
## POÇOS OBRIGATÓRIOS (≥4)
--------------------------------------------------

### POÇO CI-A — PATH / PROVAS (matriz ≥8)
Esgotar na corrida (não 1 string):
- `%c0%ae` / overlong UTF-8  
- `%25252e` (triple)  
- `\u2215` division slash · `\u29F8` big solidus · backslash mix  
- null byte `%00` · `\n` no path  
- path absoluto vs relativo; bucket swap  
- prova de order B no dispute A  
- overwrite prova seller/buyer  
Documentar: upload aceite? URL servida? RLS list?

### POÇO CI-B — FSM DISPUTA / DEVOLUÇÃO
1. 2.ª `pedido_devolucao` na mesma order  
2. partial qty / partial amount  
3. estado `devolvida` / fechada cedo pelo seller JWT  
4. buyer confirma receção ∥ abre disputa race  
5. carrier “delivered” early → auto-close indevido

### POÇO CI-C — REFUND / STOCK / RELEASE
1. refund Edge amount > captura / < parcial mentiroso  
2. stock restore duplo (dispute win ×2 / cancel×dispute)  
3. release wallet ∥ dispute open  
4. Seguro Fleaber: buyer pede refund seller-only path

### POÇO CI-D — 2.º ACTOR / COMPOSIÇÃO
1. B2 (outro buyer) mete-se na disputa A  
2. conluio buyer+seller mint  
3. Cadeia: path/FSM → refund Stripe TEST → stock → Δwallet  
Obrigatório ≥1 cadeia com dinheiro ou stock final medido.

--------------------------------------------------
## LENTES CI (≥6/8)
--------------------------------------------------
CI1 pedido_devolucao · CI2 FSM · CI3 provas · CI4 refund · CI5 stock · CI6 release · CI7 2.º actor · CI8 caixa

--------------------------------------------------
## TÁCTICAS MÍNIMAS
--------------------------------------------------
1. Matriz path ≥8.  
2. ≥1 2.ª disputa ou partial.  
3. ≥1 stock restore ou refund amount.  
4. ≥1 race ou 2.º actor.  
5. Evidência BD + Stripe se refund.

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Poços A–D · lentes ≥6 · tácticas 1–4 · senão `INCONCLUSIVO`.

```
AUDITOR: REDTEAM_BLIND_CI_DISPUTA_POS_BXCC_v1
production_touched: false · fase4: false · corrections_applied: false
VEREDICTO: FAIL_P0|FAIL_P1|FAIL_P2|FAIL_P3|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```

**NÃO CORRIGIR.**
