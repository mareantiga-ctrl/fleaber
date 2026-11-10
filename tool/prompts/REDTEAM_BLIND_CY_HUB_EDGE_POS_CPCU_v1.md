# FLEABER — RED TEAM CEGO CY · DEEP · PÓS-CPCU
## Hub / follow / favorite / tip / Mux — **quota ≥12 probes**
## (= CS que faltou na ronda POS_ALLOWLIST)

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Só **published** em follow/favorite. Tip/Mux residual. Não chase discovery exacto.

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

Prefixo `RTCY-<timestamp>-` · pasta `tool/redteam_blind_cy_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | alvo published? | HTTP/RPC | BD | HOLD|FAIL|SKIP`.
3. Controlo «follow unpublished clássico» ≤2 se HOLD — **não** contar.
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Follow/favorite **somente** published. Tip mid-unpublish. Mux/Edge residual.  
> Atacar política published — não repetir lista hub_lives exacta CDCI.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: follow unpublished · favorite unpublished clássicos · PaysafeCash · PicPay · Coptic.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### CY-A Follow / favorite (≥6)
A1 follow live/hub **published** → OK  
A2 follow **unpublished** → deny (1 linha controlo)  
A3 favorite published → OK  
A4 favorite unpublished → deny  
A5 follow UUID inválido / outro seller  
A6 race: follow ∥ unpublish

### CY-B Tip residual (≥3)
B1 tip Session published → unpublish → pay/return  
B2 tip_id / amount hostil  
B3 settle unpaid GET tip

### CY-C Edge / Mux (≥3)
C1 create-mux body hostil (buyer / ≠owner)  
C2 CORS Origin `null` / evil  
C3 resolve-mux unpublished dono vs buyer

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CY1 follow published · CY2 favorite · CY3 tip · CY4 Mux · CY5 Edge · CY6 race · CY7 composição

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · A1+A3 OK · deny unpublished · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CY_HUB_EDGE_POS_CPCU_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
