# FLEABER — RED TEAM CEGO CT · DEEP · PÓS-ALLOWLIST
## Payout / idempotency charset — **quota ≥10 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Allowlist de **charset** na key — não chase Coptic/Cherokee sinónimos.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL + checklist 1–8)
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

Prefixo `RTCT-<timestamp>-` · pasta `tool/redteam_blind_ct_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**10** linhas.
2. Colunas: `probe_id | key/resumo | HTTP | Stripe tr_ count | BD wallet | HOLD|FAIL|SKIP`.
3. **≥1** Transfer Stripe TEST real (não só 400). Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Key **non-ASCII** → **400** (allowlist charset).  
> **I vs i** (ASCII case) → ainda **1** Transfer.  
> Key legítima `wd_<uuid>` → funciona. Bypass da allowlist charset?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: PaysafeCash · PicPay · esaurito · **Coptic** · follow unpublished.  
≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥10)
--------------------------------------------------

### CT-A Charset allowlist (≥4)
A1 key com Coptic/Cyrillic/emoji → **esperar 400** (1 linha; se HOLD exacto Coptic, 1 só)  
A2 key com acento Latin (`wd_café…`) → 400  
A3 key com ZWSP / bidi no meio → 400  
A4 key com `%` / espaço / newline → 400

### CT-B Case / legítima (≥3)
B1 par **I** vs **i** mesma key base → **1** Transfer (não 2)  
B2 key canónica **`wd_<uuid>`** ASCII → Transfer OK  
B3 retry mesma `wd_<uuid>` → idempotente (1 tr_)

### CT-C Hostil residual (≥3)
C1 destination alheio / amount hostil  
C2 buyer refund seller-only → 403  
C3 release∥refund race (1)

**Total mínimo = 10.** Documentar nº de `tr_` por probe.

--------------------------------------------------
## LENTES (≥5/6)
--------------------------------------------------
CT1 charset 400 · CT2 I/i · CT3 wd_uuid · CT4 Transfer · CT5 refund actor · CT6 Δwallet

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥10 · A* → 400 · B1=1 tr_ · B2 OK · P0–P2 = **0** → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CT_PAYOUT_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.** Seller-only refund: reportar só se abriu.
