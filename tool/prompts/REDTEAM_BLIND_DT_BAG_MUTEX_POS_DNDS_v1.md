# FLEABER — RED TEAM CEGO DT · DEEP · PÓS-DNDS
## Saco / mutex / claim / preço / stock — **quota ≥20 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DNDS: pré-create guard + reuse fail-closed. **Partir o cadeado com overlaps e timings novos.**

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
Copiar bloco CONTAGEM completo + no fim `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTDT-<timestamp>-` · pasta `tool/redteam_blind_dt_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**20** linhas LIVE.
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP | classe_nova?`.
3. **≥5 races** `Future.wait` **distintas** (shapes/timings diferentes).
4. **≥1** Stripe TEST **pago** (4242) + stock/caixa.
5. **≥4 probes** `classe_nova=SIM` (ângulo **fora** de ANTI-ATROFIA).
6. Sem quota / sem 4 classes novas → `INCONCLUSIVO` ou `ATROFIA_ABORT` (proibido saturar).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> ≤1 Session útil (`cs_`) em qualquer overlap do mesmo buyer; 2.º = contention / reuse / 400 — **nunca** 2× HTTP 200 com `cs_` distintas úteis.  
> Preço/qty autoritativos; underpay não baixa Session; 2 buyers qty=1 → 2.º deny.  
> Inventar: delays 0/50/200/800ms; 6∥4; 3 bags em leque; single∥bag∥single; claim steal após timeout cliente.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 linha cada — **não contar**)
--------------------------------------------------
4∥2 ≤1 cs_ · 5∥3 ≤1 cs_ · bag∥single meio ≤1 · `mb way x` · `mbωay` · PaysafeCash · claiming TTL exacto

≥40% tabela = estes HOLD → **`ATROFIA_ABORT`**.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥20)
--------------------------------------------------

### DT-A Claim / mutex (≥5)
A1 reclaim `cs_` morta + buyer2 CPI  
A2 claiming futuro / malform / TTL (máx 1 residual)  
A3 timeout cliente 100ms ∥ server completa ∥ retry (documentar órfãs)  
A4 2 bags **disjuntos** paralelo (mutex / 2 cs_ OK se sem overlap)  
A5 JWT PATCH `cs_` + RPC claim token alheio

### DT-B Overlaps **novos** (≥7) — classe_nova obrigatória
B1 bag **6∥4** (subset grande, não 5∥3)  
B2 bag **AB∥BC∥CA** (triângulo — 3 CPI)  
B3 bag **ABCDE∥C** (single extremo vs meio já testado: usa **índice 2 de 5**)  
B4 **2× bag idêntico** (mesmo set, ordem UUID invertida) paralelo  
B5 bag∥single∥bag (3 corrotinas)  
B6 staggered: bag full → sleep 50ms → subset  
B7 staggered: subset first → sleep 50ms → superset (expand)

### DT-C Preço / stock / off (≥5)
C1 underpay body vs catálogo  
C2 coupon / portes PATCH com Session open  
C3 2 buyers última unidade  
C4 unlist∥CPI  
C5 off-platform **novo** (não wrap `x`/`via` — ex. método array, notes+method mismatch)

### DT-D Caixa / cross (≥3)
D1 **1× pago 4242** + ledger stock  
D2 bag cross-seller deny  
D3 qty hostil JWT + CPI body

**Total mínimo = 20.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DT1 Session · DT2 mutex · DT3 overlap novo · DT4 timing · DT5 stock · DT6 preço · DT7 claim · DT8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥20 · ≥5 races · ≥4 classe_nova · 1 pago · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Sem 4 classe_nova → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_DT_BAG_MUTEX_POS_DNDS_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
