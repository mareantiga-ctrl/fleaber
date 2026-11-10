# FLEABER — RED TEAM CEGO CS · DEEP · PÓS-ALLOWLIST
## Hub / follow / favorite / tip / Mux — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> Foco: **só published** em follow/favorite; tip/Mux residual. Não chase discovery exacto CDCI.

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

Prefixo `RTCS-<timestamp>-` · pasta `tool/redteam_blind_cs_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | alvo published? | HTTP/RPC | BD | HOLD|FAIL|SKIP`.
3. Controlo residual «follow unpublished clássico» ≤2 se HOLD. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Follow/favorite **apenas** em conteúdo **published**; tip mid-unpublish e Mux/Edge residual ainda abertos?  
> Atacar política allowlist published — não repetir lista hub_lives exacta.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: PaysafeCash · PicPay · esaurito · Coptic · **follow unpublished** (já fechado).  
≥50% residual → `ATROFIA_ABORT`.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### CS-A Follow / favorite published (≥6)
A1 follow live/hub **published** → OK  
A2 follow **unpublished** → deny (controlo; se HOLD exacto, 1 linha só)  
A3 favorite published → OK  
A4 favorite unpublished → deny  
A5 follow UUID inválido / de outro seller  
A6 timing: follow enquanto unpublish a meio (race)

### CS-B Tip residual (≥3)
B1 tip Session published → unpublish → pay/return  
B2 tip_id / amount hostil  
B3 settle unpaid GET tip

### CS-C Edge / Mux residual (≥3)
C1 create-mux body hostil (buyer / ≠owner)  
C2 CORS Origin `null` / evil  
C3 resolve-mux unpublished dono vs buyer

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
CS1 follow published · CS2 favorite · CS3 tip · CS4 Mux · CS5 Edge · CS6 race · CS7 composição

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
Tabela ≥12 · A1+A3 OK · deny unpublished coerente · P0–P2 = **0** → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_CS_HUB_EDGE_POS_ALLOW_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
