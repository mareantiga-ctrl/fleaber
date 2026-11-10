# FLEABER — RED TEAM CEGO DM · DEEP · PÓS-DBDG
## Cross-surface composição — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Um fio: **marketplace + live + hub + chat + money**. Procurar inconsistência entre sítios.

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

Prefixo `RTDM-<timestamp>-` · pasta `tool/redteam_blind_dm_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | superfícies tocadas | acção | HTTP | oráculos multi-sítio | HOLD|FAIL|SKIP`.
3. Cada finding tem de mostrar **≥2 sítios** (ex.: app order + hub + stock).
4. **≥1** pago Stripe TEST no fio.
5. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> O mesmo facto (pago / stock / published / reserva) é **coerente** em Início, Hub, encomendas, chat, live.  
> Compor ataques: unpublish + tip + follow; bag + live hitch; disputa + refund + stock.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD exactos DBDG/CVDA já fechados (1 linha cada máx.).

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### DM-A Published / Hub ↔ app (≥3)
A1 unpublish mid-checkout / mid-tip  
A2 follow+favorite vs vitrine hub_products_public  
A3 produto sold no Hub vs CPI

### DM-B Stock multi-sítio (≥3)
B1 hitch live + bag marketplace mesmo SKU  
B2 qty 0 live vs list_on_marketplace  
B3 refund restaura: order + product + live_item

### DM-C Dinheiro composição (≥3)
C1 pago Stripe → chat card + order status + wallet Δ  
C2 off-platform MB WAY → sem Session + seller confirma  
C3 disputa+refund sem double stock

### DM-D Race composição (≥3)
D1 bag∥live accept mesmo stock  
D2 end_live∥CPI  
D3 refund∥nova compra mesma unidade

**Total mínimo = 12.** Oráculo = **dois ou mais** sítios por linha crítica.

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DM1 hub↔ app · DM2 stock cross · DM3 money cross · DM4 race compose · DM5 chat ledger · DM6 published · DM7 refund stock

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · 1 pago · multi-sítio coerente · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DM_CROSS_SURFACE_POS_DBDG_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
