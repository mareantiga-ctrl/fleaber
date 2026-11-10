# FLEABER — RED TEAM CEGO EF · DEEP · POS_OPEN_MVP
## Saco / mutex / claim write / overlaps — **quota ≥22** · **GATE abertura**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Fix OPEN: `bagClaimToken` **sem shadow** no write (eq claim). Orphan expire. **Partir** se ainda houver 2 `cs_` open/payable no overlap.

--------------------------------------------------
## ⚠️ CONTAGEM — 1.º bloco (INVÁLIDO sem números)
--------------------------------------------------
CONTAGEM completo + `RESUMO_NUMERICO: P0=N P1=N P2=N P3=N TOTAL=N`.  
`tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

Prefixo `RTEF-<timestamp>-` · pasta `tool/redteam_blind_ef_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. Tabela ≥**22** LIVE.
2. **≥6 races** `Future.wait` distintas.
3. **≥1** Stripe TEST pago 4242.
4. **≥5 classe_nova**.
5. Oráculo: `cs_` **open** + `reused` + settle.  
   - FAIL/P1 se 2× HTTP 200 com **2 `cs_` distintas ainda open/payable** no overlap.  
   - OK se 2.º = `reused=true` mesmo `cs_` **ou** 400 contention **ou** 1 open + outra expired (provar expire/settle).
6. Sem quota / sem 5 classes → `ATROFIA_ABORT`.

--------------------------------------------------
## MISSÃO (gate)
--------------------------------------------------
> Overlap do mesmo buyer → **≤1** Session útil.  
> 6∥4, expand, bag∥single, triângulo, stagger 0/50/200 ms.  
> Ledger: lines do saco apontam para o `cs_` vencedor; órfã expired ou nunca criada.

--------------------------------------------------
## ANTI-ATROFIA (HOLD ≤1 — não contar)
--------------------------------------------------
4∥2 clássico · 5∥3 · `mb way x` · claiming TTL exacto · multibanco exact 400 (1 linha)

≥40% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ (≥22)
--------------------------------------------------

### EF-A Claim / write (≥6)
A1 reclaim `cs_` morta  
A2 claiming futuro / malform  
A3 timeout 100ms ∥ complete ∥ retry  
A4 2 bags **disjuntos** (2 cs_ OK)  
A5 JWT PATCH `cs_` + claim alheio  
A6 **provar** write respeita claim: overlap 2× idêntico → 1 `cs_` (classe_nova shadow-fix)

### EF-B Overlaps hard (≥8) — classe_nova
B1 **6∥4** t=0 **e** t=50  
B2 **AB∥BC∥CA**  
B3 **ABCDE∥C**  
B4 2× bag UUID invertido  
B5 bag∥single∥bag  
B6 full→50ms→subset  
B7 subset→50ms→superset (expand)  
B8 **3×** mesmo bag paralelo

### EF-C Preço / stock (≥5)
C1 underpay  
C2 PATCH shipping/coupon c/ Session open  
C3 2 buyers qty=1  
C4 unlist∥CPI  
C5 off residual 1 linha máx (não multibanco matrix — ver EH)

### EF-D Caixa (≥3)
D1 pago 4242 + stock  
D2 cross-seller deny  
D3 qty hostil

**Total ≥22.**

--------------------------------------------------
## SATURAÇÃO / GATE
--------------------------------------------------
≥22 · ≥6 races · ≥5 classe_nova · 1 pago · **P0–P2=0** → `PASS_CEGO_SATURADO`.  
Qualquer dual open/payable → `FAIL_P1` (**bloqueia abertura**).

```
AUDITOR: REDTEAM_BLIND_EF_BAG_MUTEX_POS_OPEN_v1
probes_na_tabela: N · classes_novas: N · races: N
VEREDICTO: FAIL_P*|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
