# FLEABER — RED TEAM CEGO DN · DEEP · PÓS-DHDM
## Saco / mutex / claim / preço / stock — **quota ≥18 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> DHDM fechou 4∥2 / bag∥single “clássicos”. **Obrigatório inventar overlaps novos.**

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
Ver `REDTEAM_CONTAGEM_OBRIGATORIO.md`. Copiar bloco CONTAGEM + no fim `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.

Prefixo `RTDN-<timestamp>-` · pasta `tool/redteam_blind_dn_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**18** linhas LIVE.
2. Colunas: `probe_id | poço | payload/resumo | HTTP/RPC | BD/Stripe | HOLD|FAIL|SKIP | classe_nova?`.
3. **≥4 races** `Future.wait` **distintas** (não 4× o mesmo B1).
4. **≥1** Stripe TEST **pago** (4242) + stock/caixa.
5. **≥3 probes** marcadas `classe_nova=SIM` (ângulo **não** listado em ANTI-ATROFIA).
6. Sem quota ou sem classes novas → `INCONCLUSIVO` / `ATROFIA_ABORT` (proibido saturar).

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> ≤1 Session útil em qualquer overlap de linhas do mesmo buyer; 2.º = contention / reuse / expire órfã **sem** 2× HTTP 200 com `cs_` distintas úteis.  
> Preço autoritativo; underpay não baixa Session; oversell 2 buyers bloqueado.  
> Atacar **composição**: bag A∪B vs bag B∪C; bag∥bag com 1 linha partilhada; single∥single mesma order; timeout+retry+3.º CPI.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 linha cada — **não contar**)
--------------------------------------------------
4∥2 clássico se ≤1 cs_ · bag∥single clássico se ≤1 · `mb way x` / `xxmbway` · `mbωay` · PaysafeCash · claiming TTL exacto DBDG

≥40% tabela = estes HOLD → **`ATROFIA_ABORT`**.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥18)
--------------------------------------------------

### DN-A Claim / mutex (≥5)
A1 reclaim `cs_` morta + actor 2  
A2 claiming malform / futuro / TTL (1 linha se residual)  
A3 crash mid-claim + retry + 3.º CPI  
A4 2 bags **disjuntos** mesmo buyer em paralelo (documentar mutex)  
A5 claim token alheio / write `cs_` sem claim (JWT PATCH)

### DN-B Overlaps **novos** (≥6) — **obrigatório classe nova**
B1 bag **5∥3** (subset no meio, não só 4∥2)  
B2 bag **AB∥BC** (overlap 1 linha, nem subset nem superset)  
B3 bag **ABC∥CBA** (mesmas linhas ordem diferente)  
B4 **2× single** paralelo mesma `order_id`  
B5 bag∥single **linha do meio** (não só extrema)  
B6 CPI bag timeout 200ms ∥ CPI bag full ∥ CPI single (triplo)

### DN-C Preço / stock / pago (≥5)
C1 underpay `total_eur` / line hostil  
C2 coupon / portes com Session open  
C3 2 buyers qty=1  
C4 unlist∥CPI  
C5 **1× pago 4242** + ledger

### DN-D Cross-seller / qty (≥2)
D1 bag cross-seller → deny  
D2 qty hostil no body vs BD

**Total mínimo = 18.**

--------------------------------------------------
## LENTES (≥6/8)
--------------------------------------------------
DN1 Session · DN2 mutex · DN3 overlap novo · DN4 stock · DN5 preço · DN6 claim · DN7 race · DN8 caixa

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥18 · ≥4 races · ≥3 classe_nova · 1 pago · P0–P2=0 → `PASS_CEGO_SATURADO`.  
Sem classe_nova → `ATROFIA_ABORT`.

```
AUDITOR: REDTEAM_BLIND_DN_BAG_MUTEX_POS_DHDM_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N · classes_novas: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
