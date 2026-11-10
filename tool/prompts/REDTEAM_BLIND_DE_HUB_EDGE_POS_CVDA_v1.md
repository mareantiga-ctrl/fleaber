# FLEABER — RED TEAM CEGO DE · DEEP · PÓS-CVDA
## Hub follow / favorite / tip / Mux / CORS — **quota ≥12 probes**

> Staging `fxdknzrqjenzqcvnwqqq` · Stripe TEST · **NÃO CORRIGIR** · Fase 4 **não**.  
> CVDA: `batata_profile_is_hub_published` SECURITY DEFINER. Follow published deve OK.

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

Prefixo `RTDE-<timestamp>-` · pasta `tool/redteam_blind_de_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS`** ≥**12** linhas.
2. Colunas: `probe_id | poço | published? | HTTP/RPC | BD | HOLD|FAIL|SKIP`.
3. Controlo CORS chrome-extension → ACAO `https://fleaber.pt` (1 linha; HOLD não contar).
4. Sem quota → `INCONCLUSIVO`.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Follow/favorite **published** → 201. Unpublished → deny.  
> CORS preflight **não** ecoa extensão / evil subdomain. Tip/Mux residual.

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
Não contar HOLD: follow published 201 · favorite published · CORS ext→fleaber.pt · follow unpublished clássico.

--------------------------------------------------
## MATRIZ OBRIGATÓRIA (≥12)
--------------------------------------------------

### DE-A Follow / favorite (≥6)
A1 follow **published** → **201** (obrigatório feliz)  
A2 follow unpublished → deny  
A3 favorite published SKU Hub → 201  
A4 favorite unpublished → deny  
A5 UUID inválido / self  
A6 race follow ∥ unpublish

### DE-B Tip (≥3)
B1 tip mid-unpublish unpaid  
B2 amount/tip_id hostil  
B3 settle unpaid

### DE-C Mux / CORS (≥3)
C1 create-mux buyer ≠owner  
C2 OPTIONS Origin chrome-extension **e** `https://evil.fleaber.pt` → ACAO fleaber.pt (não eco)  
C3 resolve unpublished anon vs dono

**Total mínimo = 12.**

--------------------------------------------------
## LENTES (≥5/7)
--------------------------------------------------
DE1 follow · DE2 favorite · DE3 tip · DE4 Mux · DE5 CORS · DE6 race · DE7 composição

--------------------------------------------------
## SATURAÇÃO
--------------------------------------------------
A1+A3 201 · unpublished deny · CORS não ecoa · P0–P2=0 → `PASS_CEGO_SATURADO`.

```
AUDITOR: REDTEAM_BLIND_DE_HUB_EDGE_POS_CVDA_v1
production_touched: false · fase4: false · corrections_applied: false
probes_na_tabela: N
VEREDICTO: FAIL_P*|INCONCLUSIVO|PASS_CEGO_SATURADO|ATROFIA_ABORT
```
**NÃO CORRIGIR.**
