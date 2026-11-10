# FLEABER — RED TEAM CEGO DZ · DEEP · PÓS-DTDY
## Saco / mutex / expand re-claim / preço / stock — **quota ≥20 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DTDY: wait 40×200ms + expand→expire **+ re-claim create** (sem create órfão). **Partir o cadeado** com overlaps/timings que DT ainda abriu dual-`cs_`.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
Copiar bloco CONTAGEM completo + no fim `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.  
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTDZ-<timestamp>-` · pasta `tool/redteam_blind_dz_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**20** linhas LIVE.
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP | classe_nova?`.
3. **≥5 races** `Future.wait` **distintas** (shapes/timings diferentes).
4. **≥1** Stripe TEST **pago** (4242) + stock/caixa.
5. **≥4 probes** `classe_nova=SIM`.
6. Oráculo Session: contar `cs_` **open** + `payment_status` — 2× HTTP 200 com 2 `cs_` **ainda open/payable** = FAIL.
7. Sem quota / sem 4 classes novas → `INCONCLUSIVO` ou `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> ≤1 Session **útil/open** em qualquer overlap do mesmo buyer; 2.º = contention / reuse / 400 — **nunca** 2× `cs_` open pagáveis no overlap.  
> Expand (subset→superset): 1ª pode 200; após 2ª, a menor tem de estar **expired** (não payable).  
> Preço/qty autoritativos; 2 buyers qty=1 → 2.º deny.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 linha cada — **não contar**)
--------------------------------------------------
4∥2 ≤1 cs_ open · 5∥3 ≤1 · bag∥single meio ≤1 · `mb way x` · claiming TTL exacto · expand clássico se 1 open + menor expired

≥40% tabela = estes HOLD → **`ATROFIA_ABORT`**.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥20)
--------------------------------------------------

### DZ-A Claim / mutex (≥5)
A1 reclaim `cs_` morta + buyer2 CPI  
A2 claiming futuro / malform / TTL (máx 1 residual)  
A3 timeout cliente 100ms ∥ server completa ∥ retry (órfãs vs open)  
A4 2 bags **disjuntos** paralelo (2 cs_ OK se sem overlap)  
A5 JWT PATCH `cs_` + RPC claim token alheio

### DZ-B Overlaps **novos** (≥7) — classe_nova
B1 bag **6∥4** stagger 0ms e 50ms (reteste DT — oráculo open/payable)  
B2 bag **AB∥BC∥CA** (triângulo — 3 CPI)  
B3 bag **ABCDE∥C** (índice do meio)  
B4 **2× bag idêntico** ordem UUID invertida paralelo  
B5 bag∥single∥bag (3 corrotinas)  
B6 staggered: bag full → sleep 50ms → subset  
B7 staggered: **subset first → 50ms → superset** (expand + re-claim) — documentar quantas `cs_` ainda **open**

### DZ-C Preço / stock / off (≥5)
C1 underpay body vs catálogo  
C2 coupon / portes PATCH com Session open  
C3 2 buyers última unidade  
C4 unlist∥CPI  
C5 off-platform **novo** (não wrap `x`/`via`)

### DZ-D Caixa / cross (≥3)
D1 **1× pago 4242** + ledger stock  
D2 bag cross-seller deny  
D3 qty hostil JWT + CPI body

**Total mínimo = 20.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DZ1 Session open · DZ2 mutex · DZ3 expand re-claim · DZ4 timing · DZ5 stock · DZ6 preço · DZ7 claim · DZ8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥20 · ≥5 races · ≥4 classe_nova · 1 pago · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Sem 4 classe_nova → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_DZ_BAG_MUTEX_POS_DTDY_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
