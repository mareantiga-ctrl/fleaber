# FLEABER — RED TEAM CEGO CM · DEEP v2 · PÓS-FECHO CDCI
## Hub / Edge / tip / follow — **quota ≥16 discovery + tip + Edge**

> Staging · TEST · **NÃO CORRIGIR**.  
> CG trouxe 3 P2; muitos HOLDs cedo — **agora checklist fechada ≥24 probes**.

--------------------------------------------------
## CONTAGEM (topo — INVÁLIDO sem TOTAL)
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

Prefixo `RTCM-<timestamp>-` · `tool/redteam_blind_cm_<timestamp>/`.

--------------------------------------------------
## REGRA DE OURO
--------------------------------------------------
1. **`## TABELA DE PROVAS` ≥24 linhas**.
2. **≥16** discovery/follow/stock/reviews (CM-A).
3. **≥4** tip mid-unpublish / settle (CM-B).
4. **≥4** Edge Mux/CORS/create-mux (CM-C).
5. Controlo residual CDCI (resolve unpublished, tip unpublished clássico) ≤3.
6. Sem quota → **`INCONCLUSIVO`**.

--------------------------------------------------
## MISSÃO
--------------------------------------------------
> Tip após unpublish a meio, create-mux hostil, CORS null, follow UUID oracle — além do hub_published exacto?

--------------------------------------------------
## ANTI-ATROFIA
--------------------------------------------------
resolve/redirect unpublished · lives/products hub_published · tip unpublished clássico · mux_playback revoke. Residual só.

--------------------------------------------------
## MATRIZ CM-A — ≥16 probes
--------------------------------------------------
A1–A4: hub_lives_public / discovery / hub_live_items / hub_products unpublished → []  
A5–A6: REST lives live+active unpublished (buyer) · scheduled unpublished  
A7–A8: live_items + batata_live_item_stock unpublished (anon+buyer)  
A9–A12: **follow** UUID unpublished · published · timing · anon follow  
A13: favorite unpublished  
A14: reviews hub unpublished  
A15: search/RPC handle slug  
A16: products qty=0 + unpublished enum

### CM-B Tip ≥4
B1 Session tip published → unpublish → pay/return  
B2 tip bind live acaba unpublished  
B3 tip_id cliente / amount hostil  
B4 settle unpaid GET

### CM-C Edge ≥4
C1 create-mux body hostil (buyer / seller≠owner)  
C2 complete-mux cruzado  
C3 CORS Origin `null` / evil  
C4 resolve-mux dono vs buyer unpublished

--------------------------------------------------
## LENTES ≥5/7
--------------------------------------------------
CM1 Hub · CM2 origin · CM3 tip · CM4 Edge · CM5 Mux · CM6 storage · CM7 composição

```
AUDITOR: REDTEAM_BLIND_CM_HUB_EDGE_POS_CDCI_v1
probes_na_tabela: N (≥24)
VEREDICTO: …
```
**NÃO CORRIGIR.**
