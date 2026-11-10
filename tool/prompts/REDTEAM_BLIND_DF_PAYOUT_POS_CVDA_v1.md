# FLEABER — RED TEAM CEGO DF · DEEP · PÓS-CVDA
## Payout / charset — **quota ≥10 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CZ saturado. Charset allowlist — bypass residual fino.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco do FROZEN (INVÁLIDO sem números N)
--------------------------------------------------
**Obrigatório:** `quantos` = 0,1,2… · TOTAL = P0+P1+P2+P3 · ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`

```
## CONTAGEM
P0 aberto: SIM | NÃO → quantos: N
P1 aberto: SIM | NÃO → quantos: N
P2 aberto: SIM | NÃO → quantos: N
P3 aberto: SIM | NÃO → quantos: N
P4 aberto: SIM | NÃO → quantos: N
TOTAL P0–P3 abertos: N
1. P0 dinheiro irreversível? SIM|NÃO
2. Quantos P0: N
3. P1 caminho explorável? SIM|NÃO
4. Quantos P1: N
5. P2 hygiene? SIM|NÃO
6. Quantos P2: N
7. P3 baixo risco? SIM|NÃO
8. Quantos P3: N
```

Prefixo `RTDF-<timestamp>-` · pasta `tool/redteam_blind_df_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**10** linhas.
2. Colunas: `probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD|FAIL|SKIP`.
3. **≥1** Transfer Stripe TEST real.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Non-ASCII → 400. `wd_<uuid>` OK. I/i → 1 Transfer. Bypass charset **novo**.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: Coptic · emoji 💰 · accent café exactos CZ.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥10)
--------------------------------------------------

### DF-A Charset (≥4)
A1 non-ASCII residual (1) · A2 fullwidth/accent novo · A3 ZWSP/bidi · A4 `%`/space/newline

### DF-B Legítima (≥3)
B1 I vs i → 1 tr_ · B2 `wd_<uuid>` OK · B3 retry idempotente

### DF-C Hostil (≥3)
C1 dest/overbalance · C2 buyer refund 403 · C3 release∥refund

**Total mínimo = 10.**

--------------------------------------------------
## LENTES (≥5/6)
--------------------------------------------------
DF1 charset · DF2 I/i · DF3 wd_uuid · DF4 Transfer · DF5 refund · DF6 Δwallet

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A* 400 · B* OK · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DF_PAYOUT_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
