# FLEABER — RED TEAM CEGO BI
## Auditor independente · PÓS-FECHO ATBE · HUB / EDGE / MUX / TIP · v1

> Fechámos ATBE residual Hub: `hub_lives_public` **sem** draft/error; `mux_vod` **só** `ended`; playback live **só** `live`+active; tip GET **sem** oráculo Stripe; `total_qty` anon revogado; stock JWT gated. Hostile residual + ANAS PASS.  
> **Poço:** ainda VOD prematuro, tip capture alheia, CORS/Connect hijack, RPC oráculo?  
> Staging · TEST · **não corrigir**.

--------------------------------------------------
## CONTAGEM (obrigatório)
--------------------------------------------------
Ver `tool/prompts/REDTEAM_CONTAGEM_OBRIGATORIO.md`.

```
## CONTAGEM
P0 aberto: SIM | NÃO          → quantos: N
P1 aberto: SIM | NÃO          → quantos: N
P2 aberto: SIM | NÃO          → quantos: N
P3 aberto: SIM | NÃO          → quantos: N
P4 aberto: SIM | NÃO          → quantos: N
TOTAL P0–P3 abertos: N
```

**Sem TOTAL → INVÁLIDO.**

--------------------------------------------------
AMBIENTE / MISSÃO
--------------------------------------------------
Prefixo `RTBI-<timestamp>-` · `tool/redteam_blind_bi_<timestamp>/`.

> Depois do fecho Hub/CDN ATBE, ainda assisto VOD sem Edge, ou tiro dinheiro/tip por bypass?

**Exactos BC/AW (não contar):** scheduled+VOD na view · draft `is_active` na grelha · tip `No such checkout.session` · total_qty anon.  
**Novas:** FOMO RPC · handle_suggested · embed `lives(*)` keys · resolve-mux estados novos · CDN com ID obtido por outro canal · tip unpaid B2 · Connect `web_return_origin` IP/decimal · CORS · storage buckets · complete-mux cruzado.

--------------------------------------------------
LENTES BI (7/7)
--------------------------------------------------
BI1 Hub/FOMO · BI2 origin/CORS/Connect · BI3 tip settle · BI4 Edge body · BI5 Mux/LiveKit · BI6 storage · BI7 composição Hub+Edge+CDN.

Não ler BC/AW/AQ/AK.

```
AUDITOR: REDTEAM_BLIND_BI_HUB_EDGE_POS_ATBE_v1
production_touched: false · fase4: false · corrections_applied: false
```

Checklist 28. **NÃO CORRIGIR.**
