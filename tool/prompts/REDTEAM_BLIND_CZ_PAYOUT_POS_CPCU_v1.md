# FLEABER — RED TEAM CEGO CZ · DEEP · PÓS-CPCU
## Payout / idempotency charset — **quota ≥10 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Charset allowlist na key. Não chase Coptic sinónimos.

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
1. P0? SIM|NÃO  2. Quantos P0: N
3. P1? SIM|NÃO  4. Quantos P1: N
5. P2? SIM|NÃO  6. Quantos P2: N
7. P3? SIM|NÃO  8. Quantos P3: N
```

Prefixo `RTCZ-<timestamp>-` · pasta `tool/redteam_blind_cz_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**10** linhas.
2. Colunas: `probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD|FAIL|SKIP`.
3. **≥1** Transfer Stripe TEST real. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Non-ASCII key → 400. `wd_<uuid>` OK. I/i → 1 Transfer.  
> Bypass charset **novo** (não só Coptic exacto).

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: Coptic · Cherokee · emoji 💰 exactos CT.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥10)
--------------------------------------------------

### CZ-A Charset (≥4)
A1 non-ASCII (1 residual Coptic se quiseres) → 400  
A2 Latin accent / fullwidth digit  
A3 ZWSP / bidi / tag  
A4 `%` / space / newline / `+`

### CZ-B Legítima (≥3)
B1 I vs i → **1** tr_  
B2 `wd_<uuid>` → Transfer OK  
B3 retry mesma key → idempotente

### CZ-C Hostil (≥3)
C1 dest alheio / overbalance  
C2 buyer refund → 403  
C3 release∥refund

**Total mínimo = 10.**

--------------------------------------------------
## LENTES (≥5/6)
--------------------------------------------------
CZ1 charset · CZ2 I/i · CZ3 wd_uuid · CZ4 Transfer · CZ5 refund · CZ6 Δwallet

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A* 400 · B* OK · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CZ_PAYOUT_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
